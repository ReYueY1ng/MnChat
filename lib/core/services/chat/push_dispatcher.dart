/// ChatPushDispatcher —— ChatPush 推送帧分发 + 好友申请/在线状态管理。
///
/// 职责：
/// - 解析 `client.on` / `buddysvr.speek` 推送帧，分发到消息 upsert；
/// - 管理好友申请列表（applyed/accepted/rejected_notify）；
/// - 经 chatpush conn 拉好友在线状态（batch_friend_info）。
///
/// 通过回调与 [ChatService] 解耦，不直接访问会话存储 / 持久化。
library;

import 'dart:async';
import 'dart:convert';

import '../../models/messages.dart';
import '../chatpush.dart';
import '../profile.dart';
import '../../protocol/lua_table.dart' show decodeHttpResponse;
import '../../utils/log.dart';

/// 本模块日志标签。
const String _logTag = 'ChatPushDispatcher';

/// ChatPush 推送分发器。
class ChatPushDispatcher {
  ChatPushDispatcher({
    required int Function() getMyUin,
    required void Function(int uin, ChatMessage m) upsertFriendMessage,
    required void Function(int groupId, ChatMessage m) upsertGroupMessage,
    required Future<void> Function() loadSessions,
    required void Function() emitSessionSnapshot,
    required ChatPushConnection? Function() getConn,
    required Map<int, ChatSession> friendSessions,
  })  : _getMyUin = getMyUin,
        _upsertFriendMessage = upsertFriendMessage,
        _upsertGroupMessage = upsertGroupMessage,
        _loadSessions = loadSessions,
        _emitSessionSnapshot = emitSessionSnapshot,
        _getConn = getConn,
        _friendSessions = friendSessions;

  final int Function() _getMyUin;
  final void Function(int uin, ChatMessage m) _upsertFriendMessage;
  final void Function(int groupId, ChatMessage m) _upsertGroupMessage;
  final Future<void> Function() _loadSessions;
  final void Function() _emitSessionSnapshot;
  final ChatPushConnection? Function() _getConn;
  final Map<int, ChatSession> _friendSessions;

  // ── 好友申请状态（由 dispatcher 持有）──────────────────────────────────
  final List<FriendRequest> _friendRequests = [];
  final StreamController<List<FriendRequest>> _friendReqCtrl =
      StreamController<List<FriendRequest>>.broadcast();
  List<FriendRequest>? _friendReqsCache;

  /// 待处理好友申请（pending 优先，按时间倒序）。结果缓存，数据变更时失效。
  List<FriendRequest> get friendRequests =>
      _friendReqsCache ??= List.unmodifiable(
        _friendRequests
            .where((r) => r.status == FriendRequestStatus.pending)
            .toList()
          ..sort((a, b) => b.time.compareTo(a.time)),
      );

  int get friendRequestCount =>
      _friendRequests.where((r) => r.status == FriendRequestStatus.pending).length;

  Stream<List<FriendRequest>> get friendRequestStream => _friendReqCtrl.stream;

  /// 好友申请列表（内部，供 _loadFriendSessions 写入）。
  List<FriendRequest> get rawFriendRequests => _friendRequests;

  // ── 推送分发 ────────────────────────────────────────────────────────────

  /// 处理 ChatPush 推送帧。
  void handlePush(ChatPushPush push) {
    final eventName = push.eventName;
    log.debug('push $eventName args=${push.args.length}', tag: _logTag);
    if (eventName == 'client.on' && push.args.length >= 2) {
      final kind = push.args[0]?.toString();
      final data = push.args[1];
      if (kind == 'friend.msg' && data is Map) {
        _handleFriendMsg(data.cast<String, Object?>());
      }
      return;
    }
    if (eventName == 'buddysvr.speek') {
      if (push.args.length >= 3) {
        final ts =
            (push.args[0] as num?)?.toInt() ??
            DateTime.now().millisecondsSinceEpoch ~/ 1000;
        final msg = push.args[1]?.toString() ?? '';
        final who = (push.args[2] as num?)?.toInt() ?? 0;
        if (who != 0 && who != _getMyUin()) {
          final m = ChatMessage(uin: who, text: msg, time: ts);
          _upsertFriendMessage(who, m);
        }
      }
    }
  }

  void _handleFriendMsg(Map<String, Object?> data) {
    final cmd = data['cmd']?.toString() ?? '';
    switch (cmd) {
      case 'chat_notify':
        final src = toNum(data['src_uin']);
        final des = toNum(data['des_uin']);
        if (des != _getMyUin()) break; // 收件人不是我 → 忽略
        final time = toNum(data['send_time']) != 0
            ? toNum(data['send_time'])
            : toNum(data['ts']);
        final m = ChatMessage(
          uin: src,
          text: data['chat_msg']?.toString() ?? '',
          time: time,
          extendData: data['extend_data']?.toString(),
        );
        _upsertFriendMessage(src, m);
        // 推送携带好友在线状态（online 字段）→ 更新会话在线标识。
        final onlineVal = data['online'];
        if (onlineVal != null) {
          final isOnline = onlineVal == true || onlineVal == 1;
          final s = _friendSessions[src];
          if (s != null && s.isOnline != isOnline) {
            _friendSessions[src] = s.copyWith(isOnline: isOnline);
            _emitSessionSnapshot();
          }
        }
        break;
      case 'group_chat_notify':
        final rawExt = data['extend_data']?.toString();
        final notify = rawExt != null
            ? GroupNotify.fromExtendData(rawExt)
            : null;
        if (notify != null) {
          final m = ChatMessage.fromGroupNotify({
            'uin': notify.uin,
            'text': notify.text,
            'send_time': notify.sendTime,
            'extend_data': notify.shareData,
            'groupid': notify.groupId,
            'Type': notify.type,
          }, groupId: notify.groupId);
          _upsertGroupMessage(notify.groupId, m);
        }
        break;
      case 'applyed_notify':
        _onFriendApply(data);
        break;
      case 'accepted_notify':
        _onFriendAccepted(data);
        unawaited(_loadSessions());
        break;
      case 'rejected_notify':
        _onFriendRejected(data);
        break;
      case 'removed_notify':
        unawaited(_loadSessions());
        break;
    }
  }

  /// 好友申请推送：解析 uin/昵称 → 加入待处理列表。
  void _onFriendApply(Map<String, Object?> data) {
    final time = toNum(data['beapply_time']) != 0
        ? toNum(data['beapply_time'])
        : DateTime.now().millisecondsSinceEpoch ~/ 1000;
    final uin = friendUin(data);
    if (uin == 0) return;
    final existing = _friendRequests.where((r) => r.uin == uin).firstOrNull;
    if (existing != null) {
      _friendRequests.remove(existing);
      _friendRequests.add(
        FriendRequest(
          uin: uin,
          name: existing.name,
          avatar: existing.avatar,
          time: time,
        ),
      );
    } else {
      _friendRequests.add(
        FriendRequest(
          uin: uin,
          name: friendNickname(data),
          avatar: friendAvatar(data),
          time: time,
        ),
      );
    }
    emitFriendRequests();
  }

  void _onFriendAccepted(Map<String, Object?> data) {
    final uin = friendUin(data);
    if (uin != 0) removeFriendRequest(uin, FriendRequestStatus.accepted);
  }

  void _onFriendRejected(Map<String, Object?> data) {
    final uin = friendUin(data);
    if (uin != 0) removeFriendRequest(uin, FriendRequestStatus.rejected);
  }

  /// 更新好友申请状态并发出流事件。
  void removeFriendRequest(int uin, FriendRequestStatus status) {
    final idx = _friendRequests.indexWhere((r) => r.uin == uin);
    if (idx >= 0) {
      final r = _friendRequests[idx];
      _friendRequests[idx] = FriendRequest(
        uin: r.uin,
        name: r.name,
        avatar: r.avatar,
        time: r.time,
        status: status,
      );
    }
    emitFriendRequests();
  }

  void emitFriendRequests() {
    _friendReqsCache = null;
    if (!_friendReqCtrl.isClosed) _friendReqCtrl.add(friendRequests);
  }

  // ── 好友在线状态探测 ────────────────────────────────────────────────────

  /// 经 **chatpush** 主动拉好友在线状态（buddysvr.batch_friend_info）。
  Future<void> probeBuddyMain(List<int> uins) async {
    final conn = _getConn();
    if (conn == null || uins.isEmpty) return;
    try {
      final r = await conn.sendRpc('buddysvr', 'batch_friend_info', [
        uins,
        false,
      ], timeout: const Duration(seconds: 8));
      applyBatchFriendStatus(r.result);
    } catch (e) {
      log.warn('main batch_friend_info ERR: $e', tag: _logTag);
    }
  }

  /// 解析 batch_friend_info 结果并更新好友在线/游玩状态。
  void applyBatchFriendStatus(dynamic result) {
    if (result is! List || result.length < 2) return;
    final data = result[1];
    if (data is! Map) return;
    var updated = false;
    for (final e in data.entries) {
      final uin = int.tryParse('${e.key}');
      if (uin == null || e.value is! Map) continue;
      final info = (e.value as Map).cast<String, Object?>();
      final session = _friendSessions[uin];
      if (session == null) continue;
      final online = info['online'] == true || info['online'] == 1;
      final status = friendStatusText(info);
      if (session.isOnline != online || session.gameStatus != status) {
        _friendSessions[uin] = session.copyWith(
          isOnline: online,
          gameStatus: status,
        );
        updated = true;
      }
    }
    if (updated) _emitSessionSnapshot();
  }

  // ── 清理 ────────────────────────────────────────────────────────────────

  /// 清空好友申请状态（reset 时调用）。
  void clear() {
    _friendRequests.clear();
    _friendReqsCache = null;
  }

  /// 关闭好友申请流控制器（dispose 时调用）。
  Future<void> dispose() async {
    await _friendReqCtrl.close();
  }

  // ── 静态工具方法（供 dispatcher 与 session store 共用）──────────────────

  /// 兼容解析数字：int / num / 数字字符串。
  static int toNum(dynamic v) {
    if (v is int) return v;
    if (v is num) return v.toInt();
    return int.tryParse('$v') ?? 0;
  }

  /// 从好友记录提取 uin（兼容嵌套 baseinfo 结构）。
  static int friendUin(Map<String, Object?> m) {
    final outer = m['Uin'] ?? m['uin'];
    if (outer is num) return outer.toInt();
    final bi = m['baseinfo'];
    if (bi is Map) {
      final u = bi['Uin'] ?? bi['uin'];
      if (u is num) return u.toInt();
    }
    return 0;
  }

  /// 从好友记录提取昵称（嵌套 baseinfo.RoleInfo.NickName）。
  static String friendNickname(Map<String, Object?> m) {
    final direct = m['NickName'] ?? m['nickname'] ?? m['Name'];
    if (direct != null && direct.toString().isNotEmpty) {
      return direct.toString();
    }
    final bi = m['baseinfo'];
    if (bi is Map) {
      final ri = bi['RoleInfo'];
      if (ri is Map) {
        final n = ri['NickName'] ?? ri['nickname'];
        if (n != null && n.toString().isNotEmpty) return n.toString();
      }
    }
    return '';
  }

  /// 从好友记录提取头像 URL（嵌套 profile.header3/header2/header.url）。
  static String? friendAvatar(Map<String, Object?> m) {
    final direct = m['IconUrl'] ?? m['HeadIconUrl'] ?? m['headurl'];
    final profile = m['profile'];
    if (profile is Map) {
      for (final key in ['header3', 'header2', 'header']) {
        final header = profile[key];
        if (header is Map) {
          final url = header['url'] ?? header['Url'];
          if (url != null && url.toString().isNotEmpty) return url.toString();
        }
      }
    }
    if (direct != null && direct.toString().isNotEmpty) {
      return direct.toString();
    }
    return null;
  }

  /// 从 baseinfo.statusinfo 生成游玩状态文本（游戏中/组队中/在线）。
  static String? friendStatusText(Map<String, Object?> info) {
    final si = info['statusinfo'];
    final kind = statusKind(si);
    if (kind == 'ingame') {
      final room = si is List && si.length >= 3 ? statusRoomData(si[2]) : null;
      final map = room?['mapname']?.toString() ?? '';
      final cur = room?['curPlayerNum'];
      final max = room?['maxPlayerNum'];
      final playerText = (cur is num && max is num)
          ? '(${cur.toInt()}/${max.toInt()})'
          : '';
      return '游戏中${map.isNotEmpty ? ' $map' : ''}$playerText';
    }
    if (kind == 'inteam') return '组队中';
    return null;
  }

  /// 好友游玩状态文本（statusinfo[1]: "ingame"/"inteam"；[3] 为游戏详情）。
  static String? friendGameStatus(Map<String, Object?> m) {
    Object? si = m['statusinfo'];
    if (si == null) {
      final bi = m['baseinfo'];
      if (bi is Map) si = bi['statusinfo'];
    }
    return switch (statusKind(si)) {
      'ingame' => '游戏中',
      'inteam' => '组队中',
      _ => null,
    };
  }

  /// 从 statusinfo 提取状态类别（ingame/inteam/其余返回 null）。
  static String? statusKind(Object? si) {
    if (si is List && si.isNotEmpty) return si[0]?.toString();
    if (si is String) {
      final lower = si.toLowerCase();
      if (lower.contains('ingame')) return 'ingame';
      if (lower.contains('inteam')) return 'inteam';
    }
    return null;
  }

  /// statusinfo 第 3 项可能是 Map 或序列化字符串（LuaTable/JSON）。
  static Map<String, Object?>? statusRoomData(dynamic v) {
    if (v is Map) return v.cast<String, Object?>();
    if (v is String && v.isNotEmpty) {
      try {
        final d = jsonDecode(v);
        if (d is Map) return d.cast<String, Object?>();
      } catch (_) {}
      try {
        final d = decodeHttpResponse(v);
        if (d is Map) return d.cast<String, Object?>();
      } catch (_) {}
    }
    return null;
  }
}
