/// ChatService —— 外部聊天客户端核心编排器。
/// 串联：登录(login_v3+WS心跳) → ChatPush 长连接 → 好友/群消息收发 → 推送分发。
/// 对齐反编译源码：friend.msg 推送(cmd 分发) + buddysvr speek/chat_query。
library;

import 'dart:async';
import 'dart:convert';

import '../models/messages.dart';
import '../storage/app_database.dart';
import '../storage/chat_mapper.dart';
import 'auth.dart';
import 'chatpush.dart';
import 'friend.dart';
import 'group.dart';
import 'profile.dart';

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
  final _stateCtrl = StreamController<ChatServiceState>.broadcast();
  final _eventCtrl = StreamController<ChatEvent>.broadcast();
  final _sessionCtrl = StreamController<SessionSnapshot>.broadcast();

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
  /// 返回稳定升序副本（缓存以升序为规范，此处兜底保证对外契约）。
  List<ChatMessage> historyOf(ChatSessionType type, int id) =>
      List.unmodifiable(
        sortMessagesAscending(_messagesCache[_sessionKey(type, id)] ?? const []),
      );

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
        authToken: auth.jwt, // 握手用（Lua container.conn.token = 登录 jwt）
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
    // 真实推送帧（实机抓包确认）:
    //   ChatPushConnection 按 [11, service, method, seq, ts, args] 派发，
    //   实际收到 service="client", method="on" → eventName="client.on"
    //   args = ["friend.msg", {...data...}]
    // 所以事件名不是 "friend.msg"，data 在 args[1]。
    final eventName = push.eventName;
    if (eventName == 'client.on' && push.args.length >= 2) {
      final kind = push.args[0]?.toString();
      final data = push.args[1];
      if (kind == 'friend.msg' && data is Map) {
        final m = data.cast<String, Object?>();
        _handleFriendMsg(m);
      }
      return;
    }
    if (eventName == 'buddysvr.speek') {
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
        // {cmd, src_uin, des_uin, chat_msg, send_time, ts, extend_data, online}
        // 注意 send_time/src_uin 是字符串，需兼容解析。
        final src = _toNum(data['src_uin']);
        final des = _toNum(data['des_uin']);
        final otherUin = src == myUin ? des : src;
        final time = _toNum(data['send_time']) != 0
            ? _toNum(data['send_time'])
            : _toNum(data['ts']);
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

  /// 兼容解析数字：int / num / 数字字符串。
  int _toNum(dynamic v) {
    if (v is int) return v;
    if (v is num) return v.toInt();
    return int.tryParse('$v') ?? 0;
  }

  // ── 消息读写 ───────────────────────────────────────────────────────────

  /// 构造真实客户端风格的 extend_data：
  /// `url_encode(base64(JSON{nickname, shareType:0, bubble, interCode}))`
  /// （mainchatinterface.lua:114-123 原样复刻）。真实客户端总是携带，
  /// 缺了它接收方可能无法正常渲染气泡/昵称。
  String _buildExtendData() {
    final auth = _auth;
    final tShare = <String, Object?>{
      'nickname': auth?.name ?? '',
      'shareType': 0, // ShareType.TEXT
      'bubble': 0,
      'interCode': null,
    };
    final raw = base64Encode(utf8.encode(jsonEncode(tShare)));
    return Uri.encodeQueryComponent(raw);
  }

  /// 发送好友私聊消息。
  Future<Map<String, Object?>> sendFriendMessage(int desUin, String msg) async {
    final friend = _friend;
    if (friend == null) throw StateError('not logged in');
    final resp = await friend.sendChatMsg(
      desUin: desUin,
      msg: msg,
      extendData: _buildExtendData(),
    );
    return resp;
  }

  /// 发送群聊消息。
  Future<Map<String, Object?>> sendGroupMessage(int groupId, String msg) async {
    final group = _group;
    if (group == null) throw StateError('not logged in');
    return group.sendMsg(groupId: groupId, text: msg);
  }

  /// 拉取好友离线/最近聊天记录（buddysvr chat_query）。
  ///
  /// 独立客户端**不走 WS RPC**：反编译源码 `buddymanager.lua` 中
  /// `chat_query` 在 WS 打开时走 `cluster.buddysvr.chat_query`（游戏 cluster
  /// 连接专属），chatpushconn 只是推送通道——WS 上发 RPC 永不响应（实测超时）。
  /// 所以直接走 HTTP 后备 `chatpush_rpc`（POST /minilb/rpc）。
  Future<void> requestFriendHistory(int uin2) async {
    final auth = _auth;
    if (auth == null) return;
    try {
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
      // 恢复好友信息缓存（昵称/头像/在线/游玩状态）
      final friendRows = await db.allFriends();
      if (friendRows.isNotEmpty) {
        _contacts.clear();
        for (final r in friendRows) {
          _contacts.add(friendFromRecord(r));
          // 若会话尚未恢复（无历史），用好友缓存补建会话，保证列表完整
          final existing = _friendSessions[r.uin];
          if (existing == null) {
            _friendSessions[r.uin] = ChatSession(
              id: r.uin,
              type: ChatSessionType.friend,
              name: r.nickname.isNotEmpty ? r.nickname : '$r.uin',
              avatar: r.avatar,
              isOnline: r.isOnline,
              gameStatus: r.gameStatus,
            );
          } else {
            _friendSessions[r.uin] = ChatSession(
              id: existing.id,
              type: existing.type,
              name: r.nickname.isNotEmpty ? r.nickname : existing.name,
              avatar: r.avatar ?? existing.avatar,
              isOnline: r.isOnline,
              gameStatus: r.gameStatus,
              lastMessage: existing.lastMessage,
              unreadCount: existing.unreadCount,
              lastReadTime: existing.lastReadTime,
            );
          }
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
          isOnline: _friendOnline(m),
          gameStatus: _friendGameStatus(m),
        );
      }
      // 批量拉取昵称/头像（buddysvr batch_friend_info，走 WS；HTTP chatpush 不支持）
      unawaited(_fetchFriendInfos(items));
      // 保存好友信息缓存（下次启动免等待网络拉取）
      await _saveFriendCache();
    } catch (e) {
      // ignore: avoid_print
      print('query_friend_list failed: $e');
    }
  }

  /// 把内存好友信息写入 SQLite（昵称/头像/在线/游玩状态）。
  Future<void> _saveFriendCache() async {
    final db = _db;
    if (db == null || _contacts.isEmpty) return;
    try {
      final now = DateTime.now().millisecondsSinceEpoch ~/ 1000;
      final records = _contacts.map((c) {
        final s = _friendSessions[c.uin];
        return friendToRecord(
          c,
          updatedAt: now,
          isOnline: s?.isOnline ?? false,
          gameStatus: s?.gameStatus,
        );
      }).toList();
      await db.replaceFriends(records);
    } catch (e) {
      // ignore: avoid_print
      print('save friend cache failed: $e');
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

  /// 从好友记录提取头像 URL（嵌套 profile.header3/header2/header.url）。
  static String? _friendAvatar(Map<String, Object?> m) {
    final direct = m['IconUrl'] ?? m['HeadIconUrl'] ?? m['headurl'];
    final profile = m['profile'];
    if (profile is Map) {
      // 优先级：header3 → header2 → header
      for (final key in ['header3', 'header2', 'header']) {
        final header = profile[key];
        if (header is Map) {
          final url = header['url'] ?? header['Url'];
          if (url != null && url.toString().isNotEmpty) return url.toString();
        }
      }
    }
    if (direct != null && direct.toString().isNotEmpty) return direct.toString();
    return null;
  }

  /// 好友是否在线（query_friend_list 的 `online` 字段：1=在线）。
  static bool _friendOnline(Map<String, Object?> m) {
    final v = m['online'];
    if (v is num) return v.toInt() == 1;
    if (v is String) return v == '1' || v.toLowerCase() == 'true';
    // 嵌套 baseinfo.online
    final bi = m['baseinfo'];
    if (bi is Map) {
      final b = bi['online'];
      if (b is num) return b.toInt() == 1;
      if (b is String) return b == '1' || b.toLowerCase() == 'true';
    }
    return false;
  }

  /// 好友游玩状态文本（statusinfo[1]: "ingame"/"inteam"；[3] 为游戏详情）。
  /// 返回如「游戏中」「组队中」，未知返回 null。
  static String? _friendGameStatus(Map<String, Object?> m) {
    Object? si = m['statusinfo'];
    if (si == null) {
      final bi = m['baseinfo'];
      if (bi is Map) si = bi['statusinfo'];
    }
    if (si is List && si.isNotEmpty) {
      final kind = si[0]?.toString();
      if (kind == 'ingame') return '游戏中';
      if (kind == 'inteam') return '组队中';
    }
    if (si is String) {
      final lower = si.toLowerCase();
      if (lower.contains('ingame')) return '游戏中';
      if (lower.contains('inteam')) return '组队中';
      // "online" 视为在线但无游玩状态
    }
    return null;
  }

  /// 批量拉取好友昵称/头像（/miniw/profile getProfileBatch3）。
  /// friend_list 仅含 {mark, uin, relation}；昵称头像由此 HTTP 接口获取
  /// （batch_friend_info 走游戏 cluster 连接，独立客户端无法使用）。
  ///
  /// 头像优先级（与游戏主界面一致）：
  ///   DIY 自定义头像 getPersonCenterHeadInfo(diy_header.pass/pre_url)
  ///   → getProfileBatch3 的 header3 → header2 → header → 首字母占位。
  Future<void> _fetchFriendInfos(List<Map<String, Object?>> items) async {
    final auth = _auth;
    if (auth == null) return;
    final uins = items.map(_friendUin).where((u) => u != 0).toList();
    if (uins.isEmpty) return;
    try {
      final profile = ProfileClient(uin: auth.uin, s2: auth.s2, s2t: auth.s2t);
      // ① 先拉 DIY 自定义头像（游戏主界面头像来源）
      final diyAvatars = await profile.getPersonCenterHeadInfo(uins);
      // ② 再拉普通资料（昵称 + header3/2/1 兜底头像）
      bool updated = false;
      for (var i = 0; i < uins.length; i += 20) {
        final batch = uins.sublist(i, (i + 20).clamp(0, uins.length));
        final infos = await profile.getProfileBatch3(batch);
        for (final p in infos) {
          final s = _friendSessions[p.uin];
          if (s != null) {
            final avatar = diyAvatars[p.uin] ?? p.avatarUrl ?? s.avatar;
            _friendSessions[p.uin] = ChatSession(
              id: s.id,
              type: s.type,
              name: p.nickname.isNotEmpty ? p.nickname : s.name,
              avatar: avatar,
              isOnline: s.isOnline, // 保留好友列表已有的在线状态
              gameStatus: s.gameStatus,
              lastMessage: s.lastMessage,
              unreadCount: s.unreadCount,
              lastReadTime: s.lastReadTime,
            );
            updated = true;
          }
        }
      }
      if (updated) {
        _emitSessionSnapshot();
        await _saveFriendCache(); // 头像/昵称更新持久化
      }
    } catch (e) {
      // ignore: avoid_print
      print('getProfileBatch3/getPersonCenterHeadInfo failed: $e');
    }
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
    unawaited(db.insertMessage(chatMessageToCompanion(m, key, myUin: myUin)));
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
    // 缓存以 time 升序为规范（离线/网络历史乱序到达时归位）。
    _messagesCache[key] = sortMessagesAscending(msgs);
    _persistHistory(type, id, msgs);
    // 通知已打开的聊天窗口刷新（复用 ChatEvent：provider 只按 type/id 匹配，
    // 收到后重新 yield historyOf）
    _eventCtrl.add(ChatEvent(type, id, msgs.last));
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
      await db.insertMessage(chatMessageToCompanion(m, key, myUin: myUin));
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

  /// 登出时调用：关闭连接、清空缓存，保留控制器以支持重新登录。
  Future<void> reset() async {
    _shouldReconnect = false;
    _reconnectTimer?.cancel();
    _reconnectTimer = null;
    await _conn?.close();
    _conn = null;
    _auth = null;
    _friend = null;
    _group = null;
    _friendSessions.clear();
    _groupSessions.clear();
    _contacts.clear();
    _messagesCache.clear();
    _state = ChatServiceState.unauthenticated;
    _lastError = null;
    _setState(ChatServiceState.unauthenticated);
  }

  Future<void> dispose() async {
    await reset();
  }

  // ── 内部 ──────────────────────────────────────────────────────────────

  void _setState(ChatServiceState s) {
    _state = s;
    if (!_stateCtrl.isClosed) _stateCtrl.add(s);
  }
}