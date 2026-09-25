import 'dart:async';

import '../../models/messages.dart';
import '../../storage/app_database.dart';
import '../../storage/chat_mapper.dart';
import '../../utils/log.dart';
import '../friend.dart';
import '../group.dart';
import 'message_store.dart';
import 'push_dispatcher.dart';

/// 会话加载：从网络拉好友/群列表并与本地已有会话**合并**（而非清空重建），
/// 以及把好友信息写回 SQLite 缓存；另含启动引导（离线恢复 → 加载 → 历史拉取）
/// 与 chat_query 结果落库。
///
/// 依赖经构造注入；缓存为 ChatService 的实时表（共享引用，直接增删）。
class SessionLoader {
  SessionLoader({
    required FriendClient? Function() getFriend,
    required GroupClient? Function() getGroup,
    required AppDatabase? Function() getDb,
    required int Function() getMyUin,
    required List<Contact> contacts,
    required Map<int, ChatSession> friendSessions,
    required Map<int, ChatSession> groupSessions,
    required Map<int, GroupInfo> groupInfos,
    required Map<String, List<ChatMessage>> messagesCache,
    required List<FriendRequest> Function() rawFriendRequests,
    required void Function() emitFriendRequests,
    required Future<void> Function(List<Map<String, Object?>> items)
    fetchFriendInfos,
    required GroupInfo Function(Map<String, Object?> m, int gid, String name)
    groupInfoFrom,
    required void Function() emitSessionSnapshot,
    required void Function() persistGroupNames,
    required Future<void> Function() offlineLoad,
    required Future<void> Function(int uin) requestFriendHistory,
  }) : _getFriend = getFriend,
       _getGroup = getGroup,
       _getDb = getDb,
       _getMyUin = getMyUin,
       _contacts = contacts,
       _friendSessions = friendSessions,
       _groupSessions = groupSessions,
       _groupInfos = groupInfos,
       _messagesCache = messagesCache,
       _rawFriendRequests = rawFriendRequests,
       _emitFriendRequests = emitFriendRequests,
       _fetchFriendInfos = fetchFriendInfos,
       _groupInfoFrom = groupInfoFrom,
       _emitSessionSnapshot = emitSessionSnapshot,
       _persistGroupNames = persistGroupNames,
       _offlineLoad = offlineLoad,
       _requestFriendHistory = requestFriendHistory;

  final FriendClient? Function() _getFriend;
  final GroupClient? Function() _getGroup;
  final AppDatabase? Function() _getDb;
  final int Function() _getMyUin;
  final List<Contact> _contacts;
  final Map<int, ChatSession> _friendSessions;
  final Map<int, ChatSession> _groupSessions;
  final Map<int, GroupInfo> _groupInfos;
  final Map<String, List<ChatMessage>> _messagesCache;
  final List<FriendRequest> Function() _rawFriendRequests;
  final void Function() _emitFriendRequests;
  final Future<void> Function(List<Map<String, Object?>> items)
  _fetchFriendInfos;
  final GroupInfo Function(Map<String, Object?> m, int gid, String name)
  _groupInfoFrom;
  final void Function() _emitSessionSnapshot;
  final void Function() _persistGroupNames;
  final Future<void> Function() _offlineLoad;
  final Future<void> Function(int uin) _requestFriendHistory;

  static const String _logTag = 'SessionLoader';

  // ── 静态解析工具 ────────────────────────────────────────────────────────

  /// 好友关系位掩码（query_friend_list 的 relation 字段）。
  static int friendRelation(Map<String, Object?> m) {
    final v = m['relation'];
    if (v is num) return v.toInt();
    return int.tryParse('$v') ?? 0;
  }

  /// 好友时间戳（mark；成为好友/最近互动时间，不足为 0）。
  static int friendMark(Map<String, Object?> m) {
    final v = m['mark'];
    if (v is num) return v.toInt();
    return int.tryParse('$v') ?? 0;
  }

  /// 把 friend_list 各种可能结构归一化成 List<Map>。
  static List<Map<String, Object?>> asFriendItems(Object? data) {
    if (data is List) {
      return data
          .whereType<Map>()
          .map((m) => m.cast<String, Object?>())
          .toList();
    }
    if (data is Map) {
      final out = <Map<String, Object?>>[];
      if (data.containsKey('Uin') || data.containsKey('uin')) {
        out.add(data.cast<String, Object?>());
        return out;
      }
      for (final v in data.values) {
        if (v is Map) out.add(v.cast<String, Object?>());
      }
      return out;
    }
    return const [];
  }

  // ── 加载 ────────────────────────────────────────────────────────────────

  /// 启动引导：先离线恢复让 UI 立即有内容 → 加载会话 → 后台分批拉每个好友历史。
  Future<void> bootstrap() async {
    await _offlineLoad();
    await loadAll();
    const batchSize = 5;
    for (var i = 0; i < _contacts.length; i += batchSize) {
      final end = (i + batchSize).clamp(0, _contacts.length);
      await Future.wait(
        _contacts.sublist(i, end).map((c) => _requestFriendHistory(c.uin)),
      );
    }
  }

  /// 加载好友 + 群列表并发出快照。
  Future<void> loadAll() async {
    await loadFriendSessions();
    await loadGroupSessions();
    _emitSessionSnapshot();
  }

  Future<void> loadFriendSessions() async {
    final friend = _getFriend();
    if (friend == null) return;
    try {
      final resp = await friend.queryFriendList();
      // 真实响应: {friend_list: {...}, result: 0} —— friend_list 是顶层 key。
      final data = resp['friend_list'] ?? resp['data'] ?? resp;
      final items = asFriendItems(data);
      // 已聊过的好友会话不因刷新而消失：合并而不是全量清空重建。
      final oldContacts = <int, Contact>{for (final c in _contacts) c.uin: c};
      final oldSessions = <int, ChatSession>{..._friendSessions};
      final newContacts = <Contact>[];
      final newSessions = <int, ChatSession>{};
      final seen = <int>{};

      for (final m in items) {
        final uin2 = ChatPushDispatcher.friendUin(m);
        if (uin2 == 0) continue;
        if (uin2 == _getMyUin() || uin2 == 1000) continue;
        final relation = friendRelation(m);
        final mark = friendMark(m);
        seen.add(uin2);
        // relation & 2 = 对方申请我 → 归入申请列表，不建普通会话
        if ((relation & 2) != 0) {
          final exists = _rawFriendRequests().any(
            (r) => r.uin == uin2 && r.status == FriendRequestStatus.pending,
          );
          if (!exists) {
            _rawFriendRequests().add(
              FriendRequest(
                uin: uin2,
                name: ChatPushDispatcher.friendNickname(m).isNotEmpty
                    ? ChatPushDispatcher.friendNickname(m)
                    : '$uin2',
                time: ChatPushDispatcher.toNum(m['beapply_time']) != 0
                    ? ChatPushDispatcher.toNum(m['beapply_time'])
                    : mark,
              ),
            );
          }
          continue;
        }
        final oldSession = oldSessions[uin2];
        final oldContact = oldContacts[uin2];
        final nickname = ChatPushDispatcher.friendNickname(m);
        final keepName = nickname.isNotEmpty
            ? nickname
            : (oldSession?.name ?? '$uin2');
        // 保留聊天状态（最后消息/未读/已读时间），不清零
        final merged = ChatSession(
          id: uin2,
          type: ChatSessionType.friend,
          name: keepName.isNotEmpty ? keepName : '$uin2',
          avatar: ChatPushDispatcher.friendAvatar(m) ?? oldSession?.avatar,
          // 在线状态真相来自 chatpush 好友探测；好友列表的 online 常缺失/恒 0，
          // 直接采用会把全部好友判成离线，故保留上一次已知状态。
          isOnline: oldSession?.isOnline ?? false,
          gameStatus:
              ChatPushDispatcher.friendGameStatus(m) ?? oldSession?.gameStatus,
          relation: relation,
          lastMessage: oldSession?.lastMessage,
          unreadCount: oldSession?.unreadCount ?? 0,
          lastReadTime: oldSession?.lastReadTime ?? 0,
          // 头像本体/头像框只在资料拉取时才有，必须透传旧值，否则每次刷新都会清掉。
          headType: oldSession?.headType,
          headId: oldSession?.headId,
          headFrameId: oldSession?.headFrameId,
        );
        newSessions[uin2] = merged;
        final contactName = oldContact?.nickname.isNotEmpty == true
            ? oldContact!.nickname
            : (keepName != '$uin2' ? keepName : '');
        newContacts.add(
          Contact(
            uin: uin2,
            nickname: contactName,
            avatar: oldContact?.avatar ?? merged.avatar,
            relation: relation,
            mark: mark,
            headType: oldContact?.headType,
            headId: oldContact?.headId,
            headFrameId: oldContact?.headFrameId,
          ),
        );
      }

      // 移除不再出现的占位会话：仅清理从未聊过天、也无消息历史的；有历史的保留。
      oldSessions.forEach((uin2, s) {
        if (seen.contains(uin2)) return;
        if (s.lastMessage == null &&
            (_messagesCache[MessageStore.sessionKey(
                        ChatSessionType.friend,
                        uin2,
                      )]
                    ?.isEmpty ??
                true)) {
          _friendSessions.remove(uin2);
        } else {
          newSessions.putIfAbsent(uin2, () => s);
          if (!newContacts.any((c) => c.uin == uin2)) {
            newContacts.add(
              oldContacts[uin2] ??
                  Contact(uin: uin2, nickname: s.name, relation: s.relation),
            );
          }
        }
      });

      _contacts
        ..clear()
        ..addAll(newContacts);
      _friendSessions
        ..clear()
        ..addAll(newSessions);
      // 批量拉取昵称/头像（buddysvr batch_friend_info，走 WS）
      unawaited(_fetchFriendInfos(items));
      _emitFriendRequests();
      _emitSessionSnapshot();
      await saveFriendCache();
    } catch (e) {
      log.warn('query_friend_list failed: $e', tag: _logTag);
    }
  }

  Future<void> loadGroupSessions() async {
    final group = _getGroup();
    if (group == null) return;
    try {
      final resp = await group.queryUserGroups();
      Map<String, Object?> data;
      if (resp['data'] is Map) {
        data = (resp['data'] as Map).cast<String, Object?>();
      } else {
        data = resp;
      }
      final list = data['groups'] ?? data['groupList'] ?? data['list'];
      if (list is List) {
        // 与好友路径一样做「新旧合并」而不是直接 clear。
        final oldSessions = <int, ChatSession>{..._groupSessions};
        final oldInfos = <int, GroupInfo>{..._groupInfos};
        final newSessions = <int, ChatSession>{};
        final newInfos = <int, GroupInfo>{};
        final seen = <int>{};
        for (final item in list) {
          if (item is! Map) continue;
          final m = item.cast<String, Object?>();
          final gid = (m['group_id'] ?? m['groupId'] ?? m['GroupId'] ?? 0);
          if (gid is! num) continue;
          final g = gid.toInt();
          final gname = (m['group_name'] ?? m['groupName'] ?? '群 $g')
              .toString();
          final old = oldSessions[g];
          seen.add(g);
          newSessions[g] = old != null
              ? old.copyWith(name: gname)
              : ChatSession(id: g, type: ChatSessionType.group, name: gname);
          newInfos[g] = _groupInfoFrom(m, g, gname);
        }
        oldSessions.forEach((g, s) {
          if (seen.contains(g)) return;
          final cached = _messagesCache[MessageStore.sessionKey(
            ChatSessionType.group,
            g,
          )];
          if (s.lastMessage != null || (cached?.isNotEmpty ?? false)) {
            newSessions[g] = s;
          }
        });
        oldInfos.forEach((g, i) => newInfos.putIfAbsent(g, () => i));
        _groupSessions
          ..clear()
          ..addAll(newSessions);
        _groupInfos
          ..clear()
          ..addAll(newInfos);
        _persistGroupNames();
      }
    } catch (e) {
      log.warn('query_user_groups failed: $e', tag: _logTag);
    }
  }

  /// 把内存好友信息写入 SQLite（昵称/头像/在线/游玩状态，按账号隔离）。
  Future<void> saveFriendCache() async {
    final db = _getDb();
    if (db == null || (_contacts.isEmpty && _friendSessions.isEmpty)) return;
    try {
      final now = DateTime.now().millisecondsSinceEpoch ~/ 1000;
      final owner = _getMyUin();
      if (owner == 0) return;
      final uins = <int>{..._contacts.map((c) => c.uin)};
      final records = uins.map((uin) {
        final c = _contacts.where((x) => x.uin == uin).firstOrNull;
        final s = _friendSessions[uin];
        final nick = c?.nickname.isNotEmpty == true
            ? c!.nickname
            : ((s != null && s.name != '$uin') ? s.name : '');
        return friendToRecord(
          Contact(
            uin: uin,
            nickname: nick,
            avatar: c?.avatar ?? s?.avatar,
            relation: c?.relation ?? s?.relation ?? 0,
            mark: c?.mark ?? 0,
          ),
          updatedAt: now,
          isOnline: s?.isOnline ?? false,
          gameStatus: s?.gameStatus,
          ownerUin: owner,
        );
      }).toList();
      await db.replaceFriends(owner, records);
    } catch (e) {
      log.warn('save friend cache failed: $e', tag: _logTag);
    }
  }
}
