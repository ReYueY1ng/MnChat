/// ChatService —— 外部聊天客户端核心编排器。
/// 串联：登录(login_v3+WS心跳) → ChatPush 长连接 → 好友/群消息收发 → 推送分发。
/// 对齐反编译源码：friend.msg 推送(cmd 分发) + buddysvr speek/chat_query。
library;

import 'dart:async';

import '../models/messages.dart';
import '../storage/app_database.dart';
import '../storage/chat_mapper.dart';
import 'auth.dart';
import 'chatpush.dart';
import 'friend.dart';
import 'group.dart';

/// 服务状态。
enum ChatServiceState { unauthenticated, authenticating, connected, connectingChatPush, error }

/// 收到的新消息事件（好友/群）。
class ChatEvent {
  /// 会话类型。
  final ChatSessionType sessionType;

  /// 会话 id（好友=对方uin / 群=groupId）。
  final int sessionId;

  final ChatMessage message;

  const ChatEvent(this.sessionType, this.sessionId, this.message);
}

/// 会话列表快照。
class SessionSnapshot {
  final List<ChatSession> sessions;
  final List<Contact> contacts;

  const SessionSnapshot(this.sessions, this.contacts);
}

/// 聊天服务。
class ChatService {
  // ── 认证状态 ────────────────────────────────────────────────────────────
  MiniAuth? _auth;
  ChatServiceState _state = ChatServiceState.unauthenticated;
  String? _lastError;

  // ── 客户端 ─────────────────────────────────────────────────────────────
  late final LoginClient _login;
  late final ChatPushClient _chatpush;
  FriendClient? _friend;
  GroupClient? _group;

  // ── 连接 ───────────────────────────────────────────────────────────────
  ChatPushConnection? _conn;
  Timer? _reconnectTimer;
  bool _shouldReconnect = false;

  // ── 事件 ───────────────────────────────────────────────────────────────
  final StreamController<ChatServiceState> _stateCtrl = StreamController.broadcast();
  final StreamController<ChatEvent> _eventCtrl = StreamController.broadcast();
  final StreamController<SessionSnapshot> _sessionCtrl = StreamController.broadcast();

  // ── 会话缓存 ───────────────────────────────────────────────────────────
  final Map<int, ChatSession> _friendSessions = {};
  final Map<int, ChatSession> _groupSessions = {};
  final List<Contact> _contacts = [];
  final Map<String, List<ChatMessage>> _messagesCache = {};

  /// 可选本地持久化（drift）。null 时纯内存运行（测试/无存储环境）。
  final AppDatabase? _db;

  // 私有字段无法跨库用 this._db 初始化形参，故保留显式赋值
  ChatService({AppDatabase? db})
      : _db = db { // ignore: prefer_initializing_formals
    _login = LoginClient();
    _chatpush = ChatPushClient();
  }

  // ── Getters ────────────────────────────────────────────────────────────

  ChatServiceState get state => _state;
  String? get lastError => _lastError;
  MiniAuth? get auth => _auth;
  int get myUin => _auth?.uin ?? 0;
  String get myNickname => _auth?.name ?? '';

  Stream<ChatServiceState> get stateStream => _stateCtrl.stream;
  Stream<ChatEvent> get eventStream => _eventCtrl.stream;
  Stream<SessionSnapshot> get sessionStream => _sessionCtrl.stream;

  List<ChatSession> get sessions =>
      [..._friendSessions.values, ..._groupSessions.values]
        ..sort((a, b) => (b.lastMessage?.time ?? 0).compareTo(a.lastMessage?.time ?? 0));

  List<Contact> get contacts => List.unmodifiable(_contacts);

  /// 会话消息历史（按时间升序）。key = sessionKey(type, id)。
  List<ChatMessage> historyOf(ChatSessionType type, int id) =>
      List.unmodifiable(_messagesCache[_sessionKey(type, id)] ?? []);

  static String _sessionKey(ChatSessionType type, int id) => '${type.name}_$id';

  // ── 认证流程 ───────────────────────────────────────────────────────────

  /// 完整登录：login_v3 → (可选) WS 心跳换 s2/s2t → 进入聊天态。
  Future<MiniAuth> login({required int uin, required String password}) async {
    _setState(ChatServiceState.authenticating);
    try {
      var auth = await _login.login(uin: uin, passwd: password);
      // 用 jwt 换准确 s2/s2t（可选；login_v3 已返回 sign，心跳用于刷新）
      try {
        final ws = WsConnection();
        final (s2, s2t) = await ws.fetchS2(jwt: auth.jwt, uin: uin);
        auth = MiniAuth(
          uin: auth.uin,
          apiId: auth.apiId,
          name: auth.name,
          s2: s2,
          s2t: s2t,
          jwt: auth.jwt,
        );
      } catch (e) {
        // WS 心跳失败不阻断（login_v3 的 sign 仍可用）
        // ignore: avoid_print
        print('WS heartbeat failed (using login_v3 sign): $e');
      }
      _auth = auth;
      _friend = FriendClient(uin: uin, s2: auth.s2, s2t: auth.s2t);
      _group = GroupClient(uin: uin, s2: auth.s2, s2t: auth.s2t);
      _setState(ChatServiceState.connected);
      await _connectChatPush();
      await _loadSessions();
      return auth;
    } catch (e) {
      _lastError = e.toString();
      _setState(ChatServiceState.error);
      rethrow;
    }
  }

  // ── ChatPush 连接 ──────────────────────────────────────────────────────

  Future<void> _connectChatPush() async {
    final auth = _auth;
    if (auth == null) return;
    _setState(ChatServiceState.connectingChatPush);
    try {
      final (host, token) = await _chatpush.alloc(
        uin: auth.uin,
        s2: auth.s2,
        s2t: auth.s2t,
        jwt: auth.jwt,
      );
      final conn = await _chatpush.connectGate(
        host: host,
        token: token,
        uin: auth.uin,
        onPush: _handlePush,
        onRpc: _handleRpc,
      );
      // 保留旧连接并关闭
      final old = _conn;
      _conn = conn;
      await old?.close();
      _shouldReconnect = true;
      _setState(ChatServiceState.connected);
    } catch (e) {
      _lastError = 'ChatPush connect failed: $e';
      _setState(ChatServiceState.error);
      _scheduleReconnect();
    }
  }

  void _scheduleReconnect() {
    if (!_shouldReconnect || _reconnectTimer?.isActive == true) return;
    _reconnectTimer = Timer(const Duration(seconds: 10), () {
      if (_shouldReconnect) _connectChatPush();
    });
  }

  // ── 推送分发（对齐反编译源码）────────────────────────────────────────

  void _handlePush(ChatPushPush push) {
    final eventName = push.eventName;
    if (eventName == 'friend.msg') {
      // friend.msg: args[0] 是 data dict，按 cmd 分发
      final data = push.args.isNotEmpty ? push.args.first : null;
      if (data is Map) {
        final m = data.cast<String, Object?>();
        _handleFriendMsg(m);
      }
    } else if (eventName == 'buddysvr.speek') {
      // speek(ts, msg, who, speeker) 位置参数
      if (push.args.length >= 3) {
        final ts = (push.args[0] as num?)?.toInt() ?? DateTime.now().millisecondsSinceEpoch ~/ 1000;
        final msg = push.args[1]?.toString() ?? '';
        final who = (push.args[2] as num?)?.toInt() ?? 0;
        if (who != 0 && who != myUin) {
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
        // 好友私聊推送: {cmd, src_uin, des_uin, chat_msg, send_time, extend_data, online}
        final src = (data['src_uin'] as num?)?.toInt() ?? 0;
        final otherUin = src == myUin ? (data['des_uin'] as num?)?.toInt() ?? 0 : src;
        final time = (data['send_time'] as num?)?.toInt() ?? 0;
        final m = ChatMessage(
          uin: src,
          text: data['chat_msg']?.toString() ?? '',
          time: time,
          extendData: data['extend_data']?.toString(),
        );
        _upsertFriendMessage(otherUin, m);
        break;
      case 'group_chat_notify':
        // 群聊推送: {cmd, extend_data}，消息体藏在 extend_data (url→b64→json)
        final rawExt = data['extend_data']?.toString();
        final notify = rawExt != null ? GroupNotify.fromExtendData(rawExt) : null;
        if (notify != null) {
          final m = ChatMessage.fromGroupNotify(
            {
              'uin': notify.uin,
              'text': notify.text,
              'send_time': notify.sendTime,
              'extend_data': notify.shareData,
              'groupid': notify.groupId,
            },
            groupId: notify.groupId,
          );
          _upsertGroupMessage(notify.groupId, m);
        }
        break;
      case 'applyed_notify':
      case 'accepted_notify':
      case 'rejected_notify':
      case 'removed_notify':
        // 好友/群申请与结果通知：触发会话刷新
        unawaited(loadSessions());
        break;
    }
  }

  void _handleRpc(ChatPushRpcResult rpc) {
    // 未被 pending 匹配的 RPC 响应（一般不会到这）
  }

  // ── 消息读写 ───────────────────────────────────────────────────────────

  /// 发送好友私聊消息。
  Future<Map<String, Object?>> sendFriendMessage(int desUin, String msg) async {
    final friend = _friend;
    if (friend == null) throw StateError('not logged in');
    final resp = await friend.sendChatMsg(desUin: desUin, msg: msg);
    return resp;
  }

  /// 发送群聊消息。
  Future<Map<String, Object?>> sendGroupMessage(int groupId, String msg) async {
    final group = _group;
    if (group == null) throw StateError('not logged in');
    return group.sendMsg(groupId: groupId, text: msg);
  }

  /// 拉取好友离线/最近聊天记录（buddysvr chat_query）。
  /// 优先 WS 长连接；失败自动降级 HTTP 后备（chatpush_rpc）。
  Future<void> requestFriendHistory(int uin2) async {
    final auth = _auth;
    try {
      final conn = _conn;
      if (conn != null) {
        try {
          final rpc = await conn.sendRpc('buddysvr', 'chat_query', [uin2]);
          if (rpc.result is List) {
            _applyChatQueryResult(uin2, rpc.result as List);
            return;
          }
        } catch (e) {
          // WS 失败 → 落到 HTTP 后备
          // ignore: avoid_print
          print('chat_query WS failed for $uin2, falling back to HTTP: $e');
        }
      }
      if (auth != null) {
        final seq = DateTime.now().microsecondsSinceEpoch % 100000;
        final msec = DateTime.now().millisecondsSinceEpoch % 100000000;
        final resp = await _chatpush.rpcHttp(
          uin: auth.uin,
          s2: auth.s2,
          s2t: auth.s2t,
          message: ['buddysvr', 'chat_query', seq, msec, [uin2], <String, Object?>{}],
        );
        // 响应格式 [code?, ...]，chat_query 返回 [0, msglist]
        if (resp.length >= 2 && resp[1] is List) {
          _applyChatQueryResult(uin2, resp[1] as List);
        } else if (resp.isNotEmpty && resp[0] is List) {
          _applyChatQueryResult(uin2, resp[0] as List);
        }
      }
    } catch (e) {
      // ignore: avoid_print
      print('chat_query failed for $uin2: $e');
    }
  }

  void _applyChatQueryResult(int uin2, List<dynamic> msglist) {
    final msgs = <ChatMessage>[];
    for (final item in msglist) {
      if (item is List) msgs.add(ChatMessage.fromChatQueryTriple(item));
    }
    _replaceHistory(ChatSessionType.friend, uin2, msgs);
  }

  /// 拉取群聊历史（send_cache_msg）。
  Future<void> requestGroupHistory(int groupId) async {
    final group = _group;
    if (group == null) return;
    try {
      final list = await group.sendCacheMsg(groupId);
      final msgs = list.map((m) => ChatMessage.fromGroupNotify(m, groupId: groupId)).toList();
      _replaceHistory(ChatSessionType.group, groupId, msgs);
    } catch (e) {
      // ignore: avoid_print
      print('send_cache_msg failed for $groupId: $e');
    }
  }

  // ── 会话加载 ───────────────────────────────────────────────────────────

  /// 加载好友 + 群列表，构建会话。
  Future<void> loadSessions() async {
    await _loadFriendSessions();
    await _loadGroupSessions();
    _emitSessionSnapshot();
  }

  Future<void> _loadSessions() async {
    // 先加载本地离线缓存（SQLite），让 UI 立即有内容
    await _loadOfflineCache();
    await loadSessions();
    // 拉取每个好友的历史（后台）
    for (final c in _contacts) {
      unawaited(requestFriendHistory(c.uin));
    }
  }

  /// 从 SQLite 恢复上次的会话与消息（离线缓存）。
  Future<void> _loadOfflineCache() async {
    final db = _db;
    if (db == null) return;
    try {
      final sessionRows = await db.allSessions();
      for (final r in sessionRows) {
        final s = chatSessionFromRecord(r);
        if (s.type == ChatSessionType.friend) {
          _friendSessions[s.id] = s;
        } else {
          _groupSessions[s.id] = s;
        }
        final key = sessionKeyOf(s.type, s.id);
        final msgRows = await db.messagesOf(key);
        if (msgRows.isNotEmpty) {
          _messagesCache[key] = msgRows.map(chatMessageFromRecord).toList();
        }
      }
      _emitSessionSnapshot();
    } catch (e) {
      // ignore: avoid_print
      print('load offline cache failed: $e');
    }
  }

  Future<void> _loadFriendSessions() async {
    final friend = _friend;
    if (friend == null) return;
    try {
      final resp = await friend.queryFriendList();
      // 真实响应: {friend_list: {...}, result: 0} —— friend_list 是顶层 key，
      // 可能是 Map(uin→info) 或 List。
      final data = resp['friend_list'] ?? resp['data'] ?? resp;
      final items = _asFriendItems(data);
      if (items.isNotEmpty) {
        _contacts.clear();
        _friendSessions.clear();
      }
      for (final m in items) {
        final uin2 = _friendUin(m);
        if (uin2 == 0) continue;
        if (uin2 == myUin || uin2 == 1000) continue;
        final nickname = _friendNickname(m);
        // friend_list 只返回 {mark, uin, relation}，无昵称 → 用 uin 兜底显示
        final displayName = nickname.isNotEmpty ? nickname : '$uin2';
        _contacts.add(Contact(uin: uin2, nickname: nickname));
        _friendSessions[uin2] = ChatSession(
          id: uin2,
          type: ChatSessionType.friend,
          name: displayName,
          avatar: _friendAvatar(m),
        );
      }
      // 批量拉取昵称/头像（buddysvr batch_friend_info，走 WS；HTTP chatpush 不支持）
      unawaited(_fetchFriendInfos(items));
    } catch (e) {
      // ignore: avoid_print
      print('query_friend_list failed: $e');
    }
  }

  /// 从好友记录提取 uin（兼容嵌套 baseinfo 结构）。
  static int _friendUin(Map<String, Object?> m) {
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
  static String _friendNickname(Map<String, Object?> m) {
    final direct = m['NickName'] ?? m['nickname'] ?? m['Name'];
    if (direct != null && direct.toString().isNotEmpty) return direct.toString();
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

  /// 从好友记录提取头像 URL（嵌套 profile.header.url）。
  static String? _friendAvatar(Map<String, Object?> m) {
    final direct = m['IconUrl'] ?? m['HeadIconUrl'] ?? m['headurl'];
    final profile = m['profile'];
    if (profile is Map) {
      final header = profile['header'];
      if (header is Map) {
        final url = header['url'] ?? header['Url'];
        if (url != null && url.toString().isNotEmpty) return url.toString();
      }
    }
    if (direct != null && direct.toString().isNotEmpty) return direct.toString();
    return null;
  }

  /// 批量拉取好友昵称/头像（buddysvr batch_friend_info）。
  /// friend_list 仅含 {mark, uin, relation}；昵称头像需此 RPC（WS 通道）。
  Future<void> _fetchFriendInfos(List<Map<String, Object?>> items) async {
    final uins = items.map(_friendUin).where((u) => u != 0).toList();
    if (uins.isEmpty) return;
    final conn = _conn;
    if (conn == null) return;
    try {
      final rpc = await conn.sendRpc('buddysvr', 'batch_friend_info', [
        uins,
        false, // issimple
      ]);
      final infos = rpc.result;
      if (infos is List) {
        for (final entry in infos) {
          if (entry is! Map) continue;
          final parsed = _parseFriendInfo(entry.cast<String, Object?>());
          if (parsed == null) continue;
          final u2 = parsed.$1;
          final s = _friendSessions[u2];
          if (s != null) {
            _friendSessions[u2] = ChatSession(
              id: s.id,
              type: s.type,
              name: parsed.$2.isNotEmpty ? parsed.$2 : s.name,
              avatar: parsed.$3 ?? s.avatar,
              lastMessage: s.lastMessage,
              unreadCount: s.unreadCount,
              lastReadTime: s.lastReadTime,
            );
          }
        }
        _emitSessionSnapshot();
      }
    } catch (e) {
      // ignore: avoid_print
      print('batch_friend_info failed: $e');
    }
  }

  /// 从 friend_info 条目提取 (uin, nickname, avatar)。
  /// 结构: {uin, baseinfo:{Uin, RoleInfo:{NickName}}, profile:{header:{url}}}。
  static (int, String, String?)? _parseFriendInfo(Map<String, Object?> m) {
    int? u;
    final topUin = m['uin'] ?? m['Uin'];
    if (topUin is num) u = topUin.toInt();
    var nickname = m['NickName']?.toString() ?? '';
    String? avatar = _friendAvatar(m);
    final bi = m['baseinfo'];
    if (bi is Map) {
      final u2 = bi['Uin'] ?? bi['uin'];
      if (u == null && u2 is num) u = u2.toInt();
      if (nickname.isEmpty) {
        final ri = bi['RoleInfo'];
        if (ri is Map) {
          final n = ri['NickName'] ?? ri['nickname'];
          nickname = n?.toString() ?? '';
        }
      }
    }
    if (u == null) return null;
    return (u, nickname, avatar);
  }

  /// 把 friend_list 各种可能结构归一化成 List<Map>。
  static List<Map<String, Object?>> _asFriendItems(Object? data) {
    if (data is List) {
      return data.whereType<Map>().map((m) => m.cast<String, Object?>()).toList();
    }
    if (data is Map) {
      final out = <Map<String, Object?>>[];
      // 若 Map 本身就是一条好友记录（含 Uin/uin key）
      if (data.containsKey('Uin') || data.containsKey('uin')) {
        out.add(data.cast<String, Object?>());
        return out;
      }
      // 否则视为 uin→info 的映射
      for (final v in data.values) {
        if (v is Map) out.add(v.cast<String, Object?>());
      }
      return out;
    }
    return const [];
  }

  Future<void> _loadGroupSessions() async {
    final group = _group;
    if (group == null) return;
    try {
      final resp = await group.queryUserGroups();
      // 响应结构可能是 {data: {groups: [...]}} 或 {groups: [...]}
      Map<String, Object?> data;
      if (resp['data'] is Map) {
        data = (resp['data'] as Map).cast<String, Object?>();
      } else {
        data = resp;
      }
      final list = data['groups'] ?? data['groupList'] ?? data['list'];
      if (list is List) {
        _groupSessions.clear();
        for (final item in list) {
          if (item is! Map) continue;
          final m = item.cast<String, Object?>();
          final gid = (m['group_id'] ?? m['groupId'] ?? m['GroupId'] ?? 0);
          if (gid is! num) continue;
          final g = gid.toInt();
          _groupSessions[g] = ChatSession(
            id: g,
            type: ChatSessionType.group,
            name: (m['group_name'] ?? m['groupName'] ?? '群 $g').toString(),
          );
        }
      }
    } catch (e) {
      // ignore: avoid_print
      print('query_user_groups failed: $e');
    }
  }

  // ── 内部消息维护 ───────────────────────────────────────────────────────

  /// 本地乐观消息：发送成功后立即回显（不等服务端推送）。
  void addLocalMessage(ChatSessionType type, int sessionId, String text) {
    final m = ChatMessage(
      uin: myUin,
      text: text,
      time: DateTime.now().millisecondsSinceEpoch ~/ 1000,
      isSuccess: true,
      groupId: type == ChatSessionType.group ? sessionId : null,
    );
    if (type == ChatSessionType.friend) {
      _upsertFriendMessage(sessionId, m);
    } else {
      _upsertGroupMessage(sessionId, m);
    }
  }

  void _upsertFriendMessage(int uin2, ChatMessage m) {
    final key = _sessionKey(ChatSessionType.friend, uin2);
    final list = _messagesCache.putIfAbsent(key, () => []);
    list.add(m);
    if (list.length > 50) list.removeRange(0, list.length - 50);

    final existing = _friendSessions[uin2];
    if (existing != null) {
      _friendSessions[uin2] = existing.copyWith(
        lastMessage: m,
        unreadCount: m.uin == myUin ? existing.unreadCount : existing.unreadCount + 1,
      );
    }
    _eventCtrl.add(ChatEvent(ChatSessionType.friend, uin2, m));
    _persistMessage(ChatSessionType.friend, uin2, m);
    _emitSessionSnapshot();
  }

  void _upsertGroupMessage(int groupId, ChatMessage m) {
    final key = _sessionKey(ChatSessionType.group, groupId);
    final list = _messagesCache.putIfAbsent(key, () => []);
    list.add(m);
    if (list.length > 100) list.removeRange(0, list.length - 100);

    final existing = _groupSessions[groupId];
    if (existing != null) {
      _groupSessions[groupId] = existing.copyWith(
        lastMessage: m,
        unreadCount: m.uin == myUin ? existing.unreadCount : existing.unreadCount + 1,
      );
    } else if (m.uin != myUin) {
      _groupSessions[groupId] = ChatSession(
        id: groupId,
        type: ChatSessionType.group,
        name: '群 $groupId',
        lastMessage: m,
        unreadCount: 1,
      );
    }
    _eventCtrl.add(ChatEvent(ChatSessionType.group, groupId, m));
    _persistMessage(ChatSessionType.group, groupId, m);
    _emitSessionSnapshot();
  }

  /// 持久化一条消息 + 更新会话行。
  void _persistMessage(ChatSessionType type, int id, ChatMessage m) {
    final db = _db;
    if (db == null) return;
    final key = _sessionKey(type, id);
    unawaited(db.insertMessage(chatMessageToCompanion(m, key)));
    _persistSession(type, id);
  }

  /// 持久化会话行（未读/最后消息）。
  void _persistSession(ChatSessionType type, int id) {
    final db = _db;
    if (db == null) return;
    final s = type == ChatSessionType.friend
        ? _friendSessions[id]
        : _groupSessions[id];
    if (s == null) return;
    unawaited(db.upsertSession(chatSessionToCompanion(s)));
  }

  void _replaceHistory(ChatSessionType type, int id, List<ChatMessage> msgs) {
    if (msgs.isEmpty) return;
    final key = _sessionKey(type, id);
    _messagesCache[key] = msgs;
    _persistHistory(type, id, msgs);
  }

  /// 持久化整段历史（先清空该会话旧消息再批量写入，避免重复）。
  void _persistHistory(ChatSessionType type, int id, List<ChatMessage> msgs) {
    final db = _db;
    if (db == null) return;
    final key = _sessionKey(type, id);
    unawaited(_replaceHistoryInDb(db, key, msgs));
  }

  Future<void> _replaceHistoryInDb(AppDatabase db, String key, List<ChatMessage> msgs) async {
    await db.clearMessages(key);
    for (final m in msgs) {
      await db.insertMessage(chatMessageToCompanion(m, key));
    }
  }

  void _emitSessionSnapshot() {
    _sessionCtrl.add(SessionSnapshot(sessions, _contacts));
  }

  // ── 已读/刷新 ─────────────────────────────────────────────────────────

  /// 标记会话已读（重置未读）。
  void markRead(ChatSessionType type, int id) {
    final sessionsMap = type == ChatSessionType.friend ? _friendSessions : _groupSessions;
    final existing = sessionsMap[id];
    if (existing != null) {
      sessionsMap[id] = existing.copyWith(unreadCount: 0, lastReadTime: DateTime.now().millisecondsSinceEpoch ~/ 1000);
    }
    _persistSession(type, id);
    _emitSessionSnapshot();
  }

  // ── 清理 ──────────────────────────────────────────────────────────────

  Future<void> dispose() async {
    _shouldReconnect = false;
    _reconnectTimer?.cancel();
    await _conn?.close();
    await _stateCtrl.close();
    await _eventCtrl.close();
    await _sessionCtrl.close();
  }

  // ── 内部 ──────────────────────────────────────────────────────────────

  void _setState(ChatServiceState s) {
    _state = s;
    if (!_stateCtrl.isClosed) _stateCtrl.add(s);
  }
}

void unawaited(Future<void> future) {
  // ignore: discarded_futures
  future;
}