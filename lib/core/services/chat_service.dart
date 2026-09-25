/// ChatService —— 外部聊天客户端核心编排器。
/// 串联：登录(login_v3+WS心跳) → ChatPush 长连接 → 好友/群消息收发 → 推送分发。
/// 对齐反编译源码：friend.msg 推送(cmd 分发) + buddysvr speek/chat_query。
library;

import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart' show visibleForTesting;

import '../models/messages.dart';
import '../storage/app_database.dart';
import '../storage/chat_mapper.dart';
import 'auth.dart';
import 'chat/command_client.dart';
import 'chat/connection_manager.dart';
import 'chat/group_name_cache.dart';
import 'chat/push_dispatcher.dart';
import 'chatpush.dart';
import 'friend.dart';
import 'group.dart';
import 'message_center.dart';
import 'name_rules.dart';
import 'player_home.dart';
import 'profile.dart';
import 'social_sign.dart';
import '../protocol/lua_table.dart' show decodeHttpResponse;
import '../utils/log.dart';

/// 本模块日志标签。
const String _logTag = 'ChatService';

/// 服务状态。
enum ChatServiceState {
  unauthenticated,
  authenticating,
  connected,
  connectingChatPush,
  error,
}

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
  MessageCenterClient? _messageCenter;
  SocialSignClient? _socialSign;
  PlayerHomeClient? _playerHome;

  /// 纯 RPC 命令客户端（好友/群/conn 的网络调用剥离至此）。
  final ChatCommandClient _commands = ChatCommandClient();

  // ── 连接 ───────────────────────────────────────────────────────────────
  /// ChatPush 长连接生命周期管理器（连接/重连/保活）。
  late final ChatConnectionManager _connection;

  // ── 事件 ───────────────────────────────────────────────────────────────
  final _stateCtrl = StreamController<ChatServiceState>.broadcast();
  final _eventCtrl = StreamController<ChatEvent>.broadcast();
  final _sessionCtrl = StreamController<SessionSnapshot>.broadcast();

  // ── 会话缓存 ───────────────────────────────────────────────────────────
  final Map<int, ChatSession> _friendSessions = {};
  final Map<int, ChatSession> _groupSessions = {};
  final List<Contact> _contacts = [];
  final Map<String, List<ChatMessage>> _messagesCache = {};
  final Map<int, GroupInfo> _groupInfos = {};
  // 群成员资料缓存：groupId → (uin → PlayerProfile)。
  final Map<int, Map<int, PlayerProfile>> _groupMemberProfiles = {};

  // ── 排序/过滤缓存（数据变更时置 null，getter 惰性重算，避免热路径反复排序）──
  List<ChatSession>? _sessionsCache;

  /// 推送分发器（好友申请/在线状态/消息推送）。
  late final ChatPushDispatcher _dispatcher;

  /// 群名磁盘缓存（重启后立刻显示真实群名，不必等网络）。
  late final GroupNameCache _groupNames;

  /// 可选本地持久化（drift）。null 时纯内存运行（测试/无存储环境）。
  final AppDatabase? _db;

  // 私有字段无法跨库用 this._db 初始化形参，故保留显式赋值
  ChatService({AppDatabase? db}) : this._(
        db,
        loginClient: null,
        chatPushClient: null,
      );

  /// 测试专用注入构造：允许为登录 / chatpush 网络客户端、好友/群客户端、
  /// 数据库以及 WS 心跳提供假件，使 [ChatService] 在无网络环境下可测。
  /// **不改变**公开构造 `ChatService({db})` 的签名，业务代码完全不受影响。
  /// null 表示按默认创建真实客户端 / 走真实心跳路径。
  @visibleForTesting
  ChatService.forTest({
    AppDatabase? db,
    LoginClient? loginClient,
    ChatPushClient? chatPushClient,
    FriendClient? friendClient,
    GroupClient? groupClient,
    MessageCenterClient? messageCenterClient,
    SocialSignClient? socialSignClient,
    PlayerHomeClient? playerHomeClient,
    Future<(String, String)> Function(MiniAuth auth)? heartbeatOverride,
  }) : this._(
          db,
          loginClient: loginClient,
          chatPushClient: chatPushClient,
          friendClient: friendClient,
          groupClient: groupClient,
          messageCenterClient: messageCenterClient,
          socialSignClient: socialSignClient,
          playerHomeClient: playerHomeClient,
          heartbeatOverride: heartbeatOverride,
        );

  ChatService._(
    AppDatabase? db, {
    LoginClient? loginClient,
    ChatPushClient? chatPushClient,
    FriendClient? friendClient,
    GroupClient? groupClient,
    MessageCenterClient? messageCenterClient,
    SocialSignClient? socialSignClient,
    PlayerHomeClient? playerHomeClient,
    Future<(String, String)> Function(MiniAuth auth)? heartbeatOverride,
  })  : _db = db,
        // ignore: prefer_initializing_formals
        _heartbeatOverride = heartbeatOverride {
    _login = loginClient ?? LoginClient();
    _chatpush = chatPushClient ?? ChatPushClient();
    _friend = friendClient;
    _group = groupClient;
    _messageCenter = messageCenterClient;
    _socialSign = socialSignClient;
    _playerHome = playerHomeClient;
    _dispatcher = ChatPushDispatcher(
      getMyUin: () => myUin,
      upsertFriendMessage: _upsertFriendMessage,
      upsertGroupMessage: _upsertGroupMessage,
      loadSessions: loadSessions,
      emitSessionSnapshot: _emitSessionSnapshot,
      getConn: () => _connection.conn,
      friendSessions: _friendSessions,
    );
    _connection = ChatConnectionManager(
      chatpush: _chatpush,
      onStateChange: _setState,
      onPush: _dispatcher.handlePush,
      onReconnected: _refreshAfterReconnect,
      onError: (e) => _lastError = e,
      onConnectionChanged: (c) => _commands.conn = c,
    );
    _groupNames = GroupNameCache(
      getDb: () => _db,
      getMyUin: () => myUin,
      groupSessions: _groupSessions,
    );
  }

  /// 测试注入的 WS 心跳实现（登录时换 s2/s2t）；null 走真实 [WsConnection]。
  final Future<(String, String)> Function(MiniAuth auth)? _heartbeatOverride;

  /// 把当前客户端/认证状态同步到 [_commands]（login / reset / 连接变更时调用）。
  void _syncCommandClient() {
    _commands
      ..auth = _auth
      ..friend = _friend
      ..group = _group
      ..conn = _connection.conn
      ..playerHome = _playerHome;
  }

  // ── Getters ────────────────────────────────────────────────────────────

  ChatServiceState get state => _state;
  String? get lastError => _lastError;
  MiniAuth? get auth => _auth;
  int get myUin => _auth?.uin ?? 0;
  String get myNickname => _auth?.name ?? '';

  Stream<ChatServiceState> get stateStream => _stateCtrl.stream;
  Stream<ChatEvent> get eventStream => _eventCtrl.stream;
  /// 会话快照流：**订阅时先回放当前状态**，再转发后续事件。
  ///
  /// [_sessionCtrl] 是 broadcast 流、没有回放缓冲；而 UI 侧 `MainShell` 要等
  /// 登录状态变化后才挂载（见 `main.dart` 的 `loggedIn`），`login()` 里的
  /// `_bootstrapSessions()` 很可能在订阅建立之前就已 emit 完毕 —— 那样订阅者
  /// 只能干等下一个事件，重启后表现就是「会话列表空 / 会话丢失」。
  /// 先回放当前状态可彻底消除这个竞态。
  Stream<SessionSnapshot> get sessionStream async* {
    yield SessionSnapshot(sessions, _contacts);
    yield* _sessionCtrl.stream;
  }
  Stream<List<FriendRequest>> get friendRequestStream =>
      _dispatcher.friendRequestStream;

  /// 待处理好友申请（pending 优先，按时间倒序）。结果缓存，数据变更时失效。
  List<FriendRequest> get friendRequests => _dispatcher.friendRequests;

  int get friendRequestCount => _dispatcher.friendRequestCount;

  /// 会话列表（按最后消息时间倒序）。结果缓存，数据变更时失效。
  List<ChatSession> get sessions =>
      _sessionsCache ??= [..._friendSessions.values, ..._groupSessions.values]
        ..sort(
          (a, b) =>
              (b.lastMessage?.time ?? 0).compareTo(a.lastMessage?.time ?? 0),
        );

  List<Contact> get contacts => List.unmodifiable(_contacts);

  /// 群详情。
  GroupInfo? groupInfo(int groupId) => _groupInfos[groupId];

  /// 群聊成员 uin 列表（拉详情时兜底，不依赖 server 已缓存）。
  List<int> groupMembers(int groupId) =>
      _groupInfos[groupId]?.members ?? const [];

  /// 群成员资料（昵称/头像），未拉取到则 null。
  PlayerProfile? groupMemberProfile(int groupId, int uin) =>
      _groupMemberProfiles[groupId]?[uin];

  /// 消息中心/邮件客户端（登录后可用，未登录返回 null）。
  MessageCenterClient? get messageCenter => _messageCenter;

  /// 群客户端（登录后可用，未登录返回 null）。
  GroupClient? get group => _group;

  /// 社交签名客户端（登录后可用，未登录返回 null）。
  SocialSignClient? get socialSign => _socialSign;

  /// 玩家主页客户端（登录后可用，未登录返回 null）。
  PlayerHomeClient? get playerHome => _playerHome;

  /// 会话消息历史（按时间升序）。key = sessionKey(type, id)。
  /// 返回稳定升序副本（缓存以升序为规范，此处兜底保证对外契约）。
  List<ChatMessage> historyOf(ChatSessionType type, int id) =>
      List.unmodifiable(
        sortMessagesAscending(
          _messagesCache[_sessionKey(type, id)] ?? const [],
        ),
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
        final hb = _heartbeatOverride;
        if (hb != null) {
          final (s2, s2t) = await hb(auth);
          auth = MiniAuth(
            uin: auth.uin,
            apiId: auth.apiId,
            name: auth.name,
            s2: s2,
            s2t: s2t,
            jwt: auth.jwt,
          );
        } else {
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
        }
      } catch (e) {
        // WS 心跳失败不阻断（login_v3 的 sign 仍可用）
        log.warn('WS heartbeat failed (using login_v3 sign): $e', tag: _logTag);
      }
      _auth = auth;
      _friend ??= FriendClient(uin: uin, s2: auth.s2, s2t: auth.s2t);
      _group ??= GroupClient(uin: uin, s2: auth.s2, s2t: auth.s2t);
      _messageCenter ??= MessageCenterClient(
        uin: uin,
        s2: auth.s2,
        s2t: auth.s2t,
      );
      _socialSign ??= SocialSignClient(uin: uin, s2: auth.s2, s2t: auth.s2t);
      _playerHome ??= PlayerHomeClient(uin: uin, s2: auth.s2, s2t: auth.s2t);
      _syncCommandClient();
      _setState(ChatServiceState.connected);
      await _connectChatPush();
      await _bootstrapSessions();
      final uins = _contacts.map((c) => c.uin).toList();
      unawaited(
        _probeBuddyMain(uins),
      ); // 经 chatpush 主动拉在线状态（buddy 方法 usechatpush=true）
      return auth;
    } catch (e) {
      _lastError = e.toString();
      _setState(ChatServiceState.error);
      rethrow;
    }
  }

  // ── ChatPush 连接 ──────────────────────────────────────────────────────

  /// 建立 ChatPush 长连接（委托 [_connection]）。
  Future<void> _connectChatPush() {
    _connection.auth = _auth;
    return _connection.connect();
  }

  /// 重连成功后的数据刷新：好友列表/群（含未读状态）+ 好友在线状态。
  Future<void> _refreshAfterReconnect() async {
    try {
      await loadSessions(); // 好友/群列表重新拉（query_friend_list 未读/关系）
      final uins = _contacts.map((c) => c.uin).toList();
      await _probeBuddyMain(uins); // 在线/游玩状态经 chatpush 拉最新
      // 逐个好友补拉离线期间的消息历史（前 N 个会话）
      final chatted =
          _friendSessions.values.where((s) => s.lastMessage != null).toList()
            ..sort(
              (a, b) => (b.lastMessage?.time ?? 0).compareTo(
                a.lastMessage?.time ?? 0,
              ),
            );
      for (final s in chatted.take(20)) {
        try {
          await requestFriendHistory(s.id);
        } catch (_) {
          // 单个失败不阻断
        }
      }
    } catch (e) {
      log.warn('refresh after reconnect failed: $e', tag: _logTag);
    }
  }

  /// 经 **chatpush** 主动拉好友在线状态（buddysvr.batch_friend_info）。
  /// 响应 result=[0, {uin: {online, statusinfo, baseinfo, profile}}]。
  Future<void> _probeBuddyMain(List<int> uins) async {
    final conn = _connection.conn; // chatpush 连接
    if (conn == null || uins.isEmpty) return;
    try {
      final r = await conn.sendRpc('buddysvr', 'batch_friend_info', [
        uins,
        false,
      ], timeout: const Duration(seconds: 8));
      _applyBatchFriendStatus(r.result);
    } catch (e) {
      log.warn('main batch_friend_info ERR: $e', tag: _logTag);
    }
  }

  /// 解析 batch_friend_info 结果并更新好友在线/游玩状态。
  void _applyBatchFriendStatus(dynamic result) {
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
      final status = ChatPushDispatcher.friendStatusText(info);
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

  /// 确保长连接存活：若已断开/无连接则立即重连；连接活跃则强制发一次心跳。
  /// 供生命周期（回前台）与手动保活调用。
  Future<void> ensureConnection() => _connection.ensureConnection();

  // ── 推送分发（委托 [_dispatcher]）──────────────────────────────────────

  /// 好友申请状态更新（供 acceptFriendRequest/rejectFriendRequest 调用）。
  void _removeFriendRequest(int uin, FriendRequestStatus status) =>
      _dispatcher.removeFriendRequest(uin, status);

  // ── 消息读写 ───────────────────────────────────────────────────────────

  /// 发送好友私聊消息。
  Future<Map<String, Object?>> sendFriendMessage(int desUin, String msg) =>
      _commands.sendFriendMessage(desUin, msg);

  /// 发送"动态分享"卡片消息（shareType=19 DYNAMIC_NOTICE）。
  ///
  /// extend_data 对齐反编译 DYNAMIC_NOTICE 分享：`url_encode(base64(JSON{
  /// nickname, shareType:19, pid, content, pic_list}))`。对方客户端渲染为
  /// 动态卡片，我方 RichMedia 解析同样识别。
  Future<Map<String, Object?>> sendDynamicsShare(
    int desUin, {
    required String pid,
    String content = '',
    List<String> picList = const [],
  }) async {
    final friend = _friend;
    final auth = _auth;
    if (friend == null || auth == null) throw StateError('not logged in');
    final tShare = <String, Object?>{
      'nickname': auth.name,
      'shareType': 19, // ShareType.DYNAMIC_NOTICE
      'pid': pid,
      'content': Uri.encodeQueryComponent(content),
      'pic_list': picList,
      'bubble': 0,
    };
    final raw = base64Encode(utf8.encode(jsonEncode(tShare)));
    final extend = Uri.encodeQueryComponent(raw);
    final resp = await friend.sendChatMsg(
      desUin: desUin,
      msg: '[动态] $content',
      msgtype: 4, // 分享类消息（对齐 ReqSendInviteChatMessage）
      issys: 1,
      extendData: extend,
    );
    return resp;
  }

  // ── 好友申请 ─────────────────────────────────────────────────────────

  /// 发起好友申请（按 uin 搜索添加）。
  Future<Map<String, Object?>> applyFriend(int desUin) =>
      _commands.applyFriend(desUin);

  /// 通过好友申请。
  Future<Map<String, Object?>> acceptFriendRequest(int uin) async {
    final resp = await _commands.acceptFriendRequest(uin);
    _removeFriendRequest(uin, FriendRequestStatus.accepted);
    await loadSessions();
    return resp;
  }

  /// 拒绝好友申请。
  Future<Map<String, Object?>> rejectFriendRequest(int uin) async {
    final resp = await _commands.rejectFriendRequest(uin);
    _removeFriendRequest(uin, FriendRequestStatus.rejected);
    return resp;
  }

  /// 发送群聊消息。
  Future<Map<String, Object?>> sendGroupMessage(int groupId, String msg) =>
      _commands.sendGroupMessage(groupId, msg);

  // ── 黑名单（对齐 friendservice.lua handle_black / clear_black）─────────

  /// 加入黑名单（op_type=1）。成功后本地标记 relation 黑名单位并刷新列表。
  Future<Map<String, Object?>> addBlacklist(int desUin) async {
    final resp = await _commands.addBlacklist(desUin);
    await loadSessions();
    return resp;
  }

  /// 移出黑名单（op_type=0）。
  Future<Map<String, Object?>> removeBlacklist(int desUin) async {
    final resp = await _commands.removeBlacklist(desUin);
    await loadSessions();
    return resp;
  }

  /// 清空黑名单。
  Future<Map<String, Object?>> clearBlacklist() async {
    final resp = await _commands.clearBlacklist();
    await loadSessions();
    return resp;
  }

  /// 关注/取关玩家（cmd=attention_friend）。
  Future<Map<String, Object?>> followPlayer(
    int desUin, {
    required bool follow,
  }) async {
    final friend = _friend;
    if (friend == null) throw StateError('not logged in');
    final resp = await friend.attentionFriend(desUin, follow: follow);
    await loadSessions(); // 关系变化后刷新（关注列表会出现在好友里）
    return resp;
  }

  // ── 群管理 ───────────────────────────────────────────────────────────

  /// 查询群详情（刷新 [GroupInfo] 并返回 group_id）。
  Future<Map<String, Object?>> refreshGroupInfo(int groupId) =>
      _commands.refreshGroupInfo(groupId);

  /// 退出群。
  Future<Map<String, Object?>> quitGroup(int groupId) async {
    final resp = await _commands.quitGroup(groupId);
    await loadSessions(); // 退出后刷新列表
    return resp;
  }

  /// 解散群（仅群主）。
  Future<Map<String, Object?>> dissolveGroup(int groupId) async {
    final resp = await _commands.dissolveGroup(groupId);
    await loadSessions();
    return resp;
  }

  /// 转让群主（仅群主）。
  Future<Map<String, Object?>> transferGroup(int groupId, int newLord) async {
    final resp = await _commands.transferGroup(groupId, newLord);
    await loadSessions();
    return resp;
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
        message: [
          'buddysvr',
          'chat_query',
          seq,
          msec,
          [uin2],
          <String, Object?>{},
        ],
      );
      // 响应格式 [code?, ...]，chat_query 返回 [0, msglist]
      if (resp.length >= 2 && resp[1] is List) {
        _applyChatQueryResult(uin2, resp[1] as List);
      } else if (resp.isNotEmpty && resp[0] is List) {
        _applyChatQueryResult(uin2, resp[0] as List);
      }
    } catch (e) {
      log.warn('chat_query failed for $uin2: $e', tag: _logTag);
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
      final msgs = list
          .map((m) => ChatMessage.fromGroupNotify(m, groupId: groupId))
          .toList();
      _replaceHistory(ChatSessionType.group, groupId, msgs);
    } catch (e) {
      log.warn('send_cache_msg failed for $groupId: $e', tag: _logTag);
    }
  }

  // ── 会话加载 ───────────────────────────────────────────────────────────

  /// 加载好友 + 群列表，构建会话。
  Future<void> loadSessions() async {
    await _loadFriendSessions();
    await _loadGroupSessions();
    _emitSessionSnapshot();
  }

  Future<void> _bootstrapSessions() async {
    // 先加载本地离线缓存（SQLite），让 UI 立即有内容
    await _loadOfflineCache();
    await loadSessions();
    // 拉取每个好友的历史（后台；分批并发，每批最多 5 个，避免
    // 大量好友时同时发起上百个 HTTP 请求压垮服务端/客户端）
    const batchSize = 5;
    for (var i = 0; i < _contacts.length; i += batchSize) {
      final end = (i + batchSize).clamp(0, _contacts.length);
      await Future.wait(
        _contacts.sublist(i, end).map((c) => requestFriendHistory(c.uin)),
      );
    }
  }

  /// 从 SQLite 恢复上次的会话与消息（离线缓存，按账号隔离）。
  Future<void> _loadOfflineCache() async {
    final db = _db;
    if (db == null) return;
    try {
      final owner = myUin;
      if (owner == 0) return;
      // v6→v7 迁移：把旧数据（ownerUin=0）收养到当前账号，避免升级丢历史
      await db.adoptOrphanData(owner);
      final sessionRows = await db.allSessions(owner);
      // 一次查询全部消息再内存分组，消除逐会话查询的 N+1
      final allMsgs = await db.allMessages(owner);
      final msgsByKey = <String, List<ChatMessageRecord>>{};
      for (final r in allMsgs) {
        msgsByKey.putIfAbsent(r.sessionKey, () => []).add(r);
      }
      for (final r in sessionRows) {
        final s = chatSessionFromRecord(r);
        if (s.type == ChatSessionType.friend) {
          _friendSessions[s.id] = s;
        } else {
          _groupSessions[s.id] = s;
        }
        final key = sessionKeyOf(s.type, s.id);
        final msgRows = msgsByKey[key];
        if (msgRows != null && msgRows.isNotEmpty) {
          // 与 messagesOf 语义一致：升序取最早 200 条
          _messagesCache[key] = msgRows
              .take(200)
              .map(chatMessageFromRecord)
              .toList();
        }
      }
      // 恢复好友信息缓存（昵称/头像/在线/游玩状态）
      final friendRows = await db.allFriends(owner);
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
              // 缓存昵称可能为空、或被历史插值 bug 写坏成 FriendRecord(...)，
              // 统一净化（见 friendDisplayName），否则坏名字会直接显示出来。
              name: friendDisplayName(r.nickname, r.uin),
              avatar: r.avatar,
              isOnline: r.isOnline,
              gameStatus: r.gameStatus,
              relation: r.relation,
            );
          } else {
            // 净化缓存昵称与已有会话名：空值 / 被写坏的 FriendRecord(...) 都
            // 视为无名字，优先沿用已有会话名，最后回退迷你号。
            final uinText = '${r.uin}';
            final cachedName = friendDisplayName(r.nickname, r.uin);
            final prevName = friendDisplayName(existing.name, r.uin);
            _friendSessions[r.uin] = ChatSession(
              id: existing.id,
              type: existing.type,
              // cachedName 已净化：等于迷你号即表示缓存里没有有效昵称，
              // 此时优先沿用已有会话名（可能来自服务端），最后才回退迷你号。
              name: cachedName != uinText
                  ? cachedName
                  : (prevName != uinText ? prevName : uinText),
              avatar: r.avatar ?? existing.avatar,
              isOnline: r.isOnline,
              gameStatus: r.gameStatus,
              lastMessage: existing.lastMessage,
              unreadCount: existing.unreadCount,
              lastReadTime: existing.lastReadTime,
              relation: r.relation,
              // 离线缓存里没有 head 字段（表未存），但内存中的旧值要保留。
              headType: existing.headType,
              headId: existing.headId,
              headFrameId: existing.headFrameId,
            );
          }
        }
      }
      // 群名缓存恢复：重启后群聊立刻用真实群名（否则会先闪「群 123456」）
      await _groupNames.load();
      // 兜底一：库里有消息、却没有对应会话行时，用消息把会话补出来。
      // messages 才是真正的事实来源 —— 历史上出现过「消息写得进、会话行写不进」
      // 的 bug（见 app_database 的迁移说明），这类会话原先在列表里完全看不到。
      for (final entry in msgsByKey.entries) {
        final key = entry.key;
        final rows = entry.value;
        if (rows.isEmpty || _messagesCache.containsKey(key)) continue;
        final sep = key.lastIndexOf('_');
        if (sep <= 0) continue;
        final id = int.tryParse(key.substring(sep + 1));
        if (id == null || id == 0) continue;
        final isGroup = key.substring(0, sep) == ChatSessionType.group.name;
        final msgs = rows.take(200).map(chatMessageFromRecord).toList();
        _messagesCache[key] = msgs;
        final target = isGroup ? _groupSessions : _friendSessions;
        if (target.containsKey(id)) continue;
        // 名字先用迷你号 / 「群 N」兜底，登录后由好友列表、群列表刷新成真名。
        target[id] = ChatSession(
          id: id,
          type: isGroup ? ChatSessionType.group : ChatSessionType.friend,
          name: isGroup ? '群 $id' : '$id',
          lastMessage: msgs.last,
        );
      }
      // 兜底二：会话有本地消息、但会话行的 last_time/last_text 缺失（或会话是刚由
      // 好友缓存补建的）时，用本地最后一条消息补上 —— 否则列表按 lastMessage 排序
      // 会把它排到最后、也不显示消息预览。
      _messagesCache.forEach((key, msgs) {
        if (msgs.isEmpty) return;
        final sep = key.lastIndexOf('_');
        if (sep <= 0) return;
        final id = int.tryParse(key.substring(sep + 1));
        if (id == null || id == 0) return;
        final isGroup = key.substring(0, sep) == ChatSessionType.group.name;
        final target = isGroup ? _groupSessions : _friendSessions;
        final s = target[id];
        if (s == null || s.lastMessage != null) return;
        target[id] = s.copyWith(lastMessage: msgs.last);
      });
      _emitSessionSnapshot();
    } catch (e) {
      log.warn('load offline cache failed: $e', tag: _logTag);
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
      // 已聊过的好友会话不因刷新而消失：合并而不是全量清空重建。
      // 之前每次刷新 clear 后重建（无 lastMessage），会话列表短暂消失，
      // 直到历史请求逐个回填才恢复 —— 表现为"聊过的人闪现后消失"。
      final oldContacts = <int, Contact>{for (final c in _contacts) c.uin: c};
      final oldSessions = <int, ChatSession>{..._friendSessions};
      final newContacts = <Contact>[];
      final newSessions = <int, ChatSession>{};
      final seen = <int>{};

      for (final m in items) {
        final uin2 = ChatPushDispatcher.friendUin(m);
        if (uin2 == 0) continue;
        if (uin2 == myUin || uin2 == 1000) continue;
        final relation = _friendRelation(m);
        final mark = _friendMark(m);
        seen.add(uin2);
        // relation & 2 = 对方申请我（待处理好友申请）→ 归入申请列表，不建普通会话
        if ((relation & 2) != 0) {
          final exists = _dispatcher.rawFriendRequests.any(
            (r) => r.uin == uin2 && r.status == FriendRequestStatus.pending,
          );
          if (!exists) {
            _dispatcher.rawFriendRequests.add(
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
        // 昵称/头像优先保留旧值（离线缓存/资料拉取已有），新列表给的可覆盖
        final keepName = nickname.isNotEmpty
            ? nickname
            : (oldSession?.name ?? '$uin2');
        // 保留聊天状态（最后消息/未读/已读时间），不清零
        final merged = ChatSession(
          id: uin2,
          type: ChatSessionType.friend,
          name: keepName.isNotEmpty ? keepName : '$uin2',
          avatar: ChatPushDispatcher.friendAvatar(m) ?? oldSession?.avatar,
          // 在线状态的真相来自 chatpush 好友探测（_applyBatchFriendStatus），
          // 而好友列表接口的 online 字段经常缺失或恒为 0 —— 直接采用会把全部好友
          // 判成离线（用户反馈：一刷新就全离线）。故保留上一次已知状态，等探测
          // 结果刷新；首次加载无旧值时先按离线。
          isOnline: oldSession?.isOnline ?? false,
          gameStatus: ChatPushDispatcher.friendGameStatus(m) ?? oldSession?.gameStatus,
          relation: relation,
          lastMessage: oldSession?.lastMessage,
          unreadCount: oldSession?.unreadCount ?? 0,
          lastReadTime: oldSession?.lastReadTime ?? 0,
          // 头像本体/头像框只在资料拉取时才有，必须透传旧值，
          // 否则每次好友列表刷新都会把它们清掉（表现为"头像框不显示"）。
          headType: oldSession?.headType,
          headId: oldSession?.headId,
          headFrameId: oldSession?.headFrameId,
        );
        newSessions[uin2] = merged;
        // 昵称以会话名为准（getProfileBatch3 回填到 session.name）
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

      // 移除不再出现在好友列表中的占位会话：仅清理从未聊过天、
      // 也无消息历史的（不丢已保存的聊天记录）；有历史的保留，
      // 避免误删离线缓存恢复的会话。
      oldSessions.forEach((uin2, s) {
        if (seen.contains(uin2)) return;
        if (s.lastMessage == null &&
            (_messagesCache[_sessionKey(ChatSessionType.friend, uin2)]
                    ?.isEmpty ??
                true)) {
          _friendSessions.remove(uin2);
        } else {
          // 保留已聊天但已不在列表的好友（黑名单/被删仍可看历史）
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
      // 批量拉取昵称/头像（buddysvr batch_friend_info，走 WS；HTTP chatpush 不支持）
      unawaited(_fetchFriendInfos(items));
      _dispatcher.emitFriendRequests();
      _emitSessionSnapshot();
      // 保存好友信息缓存（下次启动免等待网络拉取）
      await _saveFriendCache();
    } catch (e) {
      log.warn('query_friend_list failed: $e', tag: _logTag);
    }
  }

  /// 把内存好友信息写入 SQLite（昵称/头像/在线/游玩状态，按账号隔离）。
  /// 昵称以好友会话名为准（getProfileBatch3 已回填），保证缓存有名字。
  Future<void> _saveFriendCache() async {
    final db = _db;
    if (db == null || (_contacts.isEmpty && _friendSessions.isEmpty)) return;
    try {
      final now = DateTime.now().millisecondsSinceEpoch ~/ 1000;
      final owner = myUin;
      if (owner == 0) return;
      // 以 contacts 为主键集合，昵称/头像从 friendSessions 同步（资料更全）
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

  /// 好友关系位掩码（query_friend_list 的 relation 字段）。
  static int _friendRelation(Map<String, Object?> m) {
    final v = m['relation'];
    if (v is num) return v.toInt();
    return int.tryParse('$v') ?? 0;
  }

  /// 好友时间戳（mark；成为好友/最近互动时间，不足为 0）。
  static int _friendMark(Map<String, Object?> m) {
    final v = m['mark'];
    if (v is num) return v.toInt();
    return int.tryParse('$v') ?? 0;
  }

  /// 批量拉取好友昵称/头像（/miniw/profile getProfileBatch3）。
  /// friend_list 仅含 {mark, uin, relation}；昵称头像由此 HTTP 接口获取
  /// （batch_friend_info 走游戏 cluster 连接，独立客户端无法使用）。
  ///
  /// 头像优先级（与游戏主界面一致）：
  ///   DIY 自定义头像 getPersonCenterHeadInfo(diy_header.pass/pre_url)
  ///   → getProfileBatch3 的 header3 → header2 → header → 首字母占位。
  Future<void> _fetchFriendInfos(List<Map<String, Object?>> items) async {
    final uins = items.map(ChatPushDispatcher.friendUin).where((u) => u != 0).toList();
    if (uins.isEmpty) return;
    var updated = false;
    await _fetchProfiles(
      uins,
      onProfile: (p, head) {
        final s = _friendSessions[p.uin];
        if (s == null) return;
        // 人物中心头信息缺失 / type=2（头套无 2D 资源）时，用资料的
        // RoleInfo.SkinID / Model 回退角色头像（官方 GetPlayerHeadPath 降级链）。
        final fallback = PlayerProfile.resolveRoleHeadFallback(
          headType: head?.type,
          headId: head?.id,
          skinId: p.headSkinId,
          model: p.headModel,
        );
        // DIY 自定义头像是玩家显式选择的形象，必须压过角色头像：AvatarView 的规则是
        // 「头像本体优先于 URL」，所以有 DIY 头像时要把头像本体清空 —— 否则自定义
        // 头像会被角色头像盖掉（用户反馈：刚进会话能显示，刷新后就变角色头像了）。
        final useDiy = head?.diyUrl != null;
        _friendSessions[p.uin] = ChatSession(
          id: s.id,
          type: s.type,
          name: p.nickname.isNotEmpty ? p.nickname : s.name,
          avatar: head?.diyUrl ?? p.avatarUrl ?? s.avatar,
          isOnline: s.isOnline, // 保留好友列表已有的在线状态
          gameStatus: s.gameStatus,
          lastMessage: s.lastMessage,
          unreadCount: s.unreadCount,
          lastReadTime: s.lastReadTime,
          relation: s.relation,
          headType: useDiy ? null : (fallback?.type ?? s.headType),
          headId: useDiy ? null : (fallback?.id ?? s.headId),
          headFrameId: p.headFrameId ?? s.headFrameId,
        );
        _updateContactHead(
          p.uin,
          head,
          p.headFrameId,
          fallbackType: fallback?.type,
          fallbackId: fallback?.id,
        );
        updated = true;
      },
    );
    if (updated) {
      _emitSessionSnapshot();
      await _saveFriendCache(); // 头像/昵称更新持久化
    }
  }

  /// 同步联系人（好友页数据源）的头像信息（DIY url + 头像本体 + 头像框）。
  ///
  /// [fallbackType]/[fallbackId]：人物中心头信息不可用（缺失 / type=2）时，
  /// 由 [PlayerProfile.resolveRoleHeadFallback] 从资料 SkinID/Model 解析出的
  /// 角色头像回退；为空则保留联系人旧值。
  void _updateContactHead(
    int uin,
    HeadSlot? head,
    int? headFrameId, {
    int? fallbackType,
    int? fallbackId,
  }) {
    if (head == null && headFrameId == null && fallbackType == null) return;
    // 同上：有 DIY 头像时清空头像本体，否则角色头像会盖掉自定义头像。
    final useDiy = head?.diyUrl != null;
    for (var i = 0; i < _contacts.length; i++) {
      final c = _contacts[i];
      if (c.uin != uin) continue;
      _contacts[i] = Contact(
        uin: c.uin,
        nickname: c.nickname,
        avatar: head?.diyUrl ?? c.avatar,
        relation: c.relation,
        mark: c.mark,
        headType: useDiy ? null : (fallbackType ?? c.headType),
        headId: useDiy ? null : (fallbackId ?? c.headId),
        headFrameId: headFrameId ?? c.headFrameId,
      );
      return;
    }
  }

  /// 批量拉取资料（DIY 头像 + getProfileBatch3，每批最多 20 个 uin）。
  ///
  /// 公共实现：好友昵称/头像与群成员资料共用同一套 HTTP 接口与分片逻辑，
  /// 差异仅在结果落点（由 [onProfile] 回调决定）。任何异常内部吞掉，
  /// 由调用方决定是否降级。
  Future<void> _fetchProfiles(
    List<int> uins, {
    required void Function(PlayerProfile p, HeadSlot? head) onProfile,
  }) async {
    final auth = _auth;
    if (auth == null || uins.isEmpty) return;
    try {
      final profile = ProfileClient(uin: auth.uin, s2: auth.s2, s2t: auth.s2t);
      // ① 先拉头像槽位（DIY 自定义头像 + 头像本体 type/id）
      final heads = await profile.getPersonCenterHeadInfos(uins);
      // ② 再拉普通资料（昵称 + header3/2/1 兜底头像），按 20 个一批
      for (var i = 0; i < uins.length; i += 20) {
        final batch = uins.sublist(i, (i + 20).clamp(0, uins.length));
        final infos = await profile.getProfileBatch3(batch);
        for (final p in infos) {
          onProfile(p, heads[p.uin]);
        }
      }
    } catch (e) {
      log.warn(
        'getProfileBatch3/getPersonCenterHeadInfo failed: $e',
        tag: _logTag,
      );
    }
  }

  /// 把 friend_list 各种可能结构归一化成 List<Map>。
  static List<Map<String, Object?>> _asFriendItems(Object? data) {
    if (data is List) {
      return data
          .whereType<Map>()
          .map((m) => m.cast<String, Object?>())
          .toList();
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
        // 与 [_loadFriendSessions] 一样做「新旧合并」而不是直接 clear：网络列表
        // 可能不包含本地已有聊天记录的群（已退群、或本次返回不完整），直接清空
        // 会把整段群会话从列表里抹掉 —— 重启后就是「会话丢失」。
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
          // 沿用本地已有的最后消息 / 未读数等，仅把群名刷新为服务端值。
          newSessions[g] = old != null
              ? old.copyWith(name: gname)
              : ChatSession(id: g, type: ChatSessionType.group, name: gname);
          newInfos[g] = _groupInfoFrom(m, g, gname);
        }
        // 网络列表里没有、但本地有历史的群会话继续保留（判据同好友路径）。
        oldSessions.forEach((g, s) {
          if (seen.contains(g)) return;
          final cached = _messagesCache[_sessionKey(ChatSessionType.group, g)];
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
        _groupNames.persist();
      }
    } catch (e) {
      log.warn('query_user_groups failed: $e', tag: _logTag);
    }
  }

  /// 从 query_user_groups 的单条群记录解析群详情（creator / members / 静默）。
  /// 字段对齐反编译源码 friendservice.lua:6002-6068（identity==1 为群主）。
  GroupInfo _groupInfoFrom(Map<String, Object?> m, int gid, String name) {
    int creator = 0;
    final members = <int>[];
    var muteAll = false;
    final memberList = m['members'];
    if (memberList is List) {
      for (final member in memberList) {
        if (member is! Map) continue;
        final mm = member.cast<String, Object?>();
        final uin = ChatPushDispatcher.toNum(mm['uin']);
        if (uin == 0) continue;
        members.add(uin);
        if (mm['identity'] == 1) creator = uin;
        if (myUin == uin && mm['ban_group'] == 1) muteAll = true;
      }
    }
    // creator 兜底（groupList 顶层也常带 creator 字段）
    if (creator == 0) creator = ChatPushDispatcher.toNum(m['creator']);
    if (creator == 0 && members.isNotEmpty) creator = members.first;
    // 后台批量拉取成员昵称/头像
    if (members.isNotEmpty) {
      _groupMemberProfiles[gid] = {};
      unawaited(_fetchGroupMemberProfiles(gid, members));
    }
    return GroupInfo(
      groupId: gid,
      name: name,
      creatorUin: creator,
      members: members,
      isMuteAll: muteAll,
    );
  }

  /// 批量拉群成员资料（getProfileBatch3 + DIY 头像），存进 [_groupMemberProfiles]。
  Future<void> _fetchGroupMemberProfiles(int gid, List<int> uins) async {
    if (uins.isEmpty) return;
    await _fetchProfiles(
      uins,
      onProfile: (p, head) {
        final member = _groupMemberProfiles[gid];
        if (member == null) return;
        // 与好友同源：人物中心缺失/type=2 时用资料 SkinID/Model 回退角色头像。
        final fallback = PlayerProfile.resolveRoleHeadFallback(
          headType: head?.type,
          headId: head?.id,
          skinId: p.headSkinId,
          model: p.headModel,
        );
        final useDiy = head?.diyUrl != null;
        member[p.uin] = PlayerProfile(
          uin: p.uin,
          nickname: p.nickname,
          avatarUrl: head?.diyUrl ?? p.avatarUrl,
          // 有 DIY 头像时清空头像本体（否则自定义头像会被角色头像盖掉，
          // 规则与好友路径一致，见 _fetchFriendInfos）。
          headType: useDiy ? null : fallback?.type,
          headId: useDiy ? null : fallback?.id,
          headFrameId: p.headFrameId,
          headSkinId: p.headSkinId,
          headModel: p.headModel,
        );
      },
    );
    _emitSessionSnapshot(); // 触发群详情刷新
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

  /// 同一逻辑消息判定：与 [message_adapter] 的确定性消息 id 一致，
  /// (uin, time, text) 三元组唯一决定一条消息。
  static bool _sameMessage(ChatMessage a, ChatMessage b) =>
      a.uin == b.uin && a.time == b.time && a.text == b.text;

  void _upsertFriendMessage(int uin2, ChatMessage m) {
    final key = _sessionKey(ChatSessionType.friend, uin2);
    final list = _messagesCache.putIfAbsent(key, () => []);
    // 去重：乐观本地回显与服务器确认推送是同一逻辑消息（共享
    // uin/time/text → 同一 id），已存在则跳过，避免同 id 重复记录
    //（flutter_chat_core 控制器在 debug 下断言 id 唯一）。
    if (list.any((e) => _sameMessage(e, m))) return;
    list.add(m);
    if (list.length > 50) list.removeRange(0, list.length - 50);

    final existing = _friendSessions[uin2];
    // 自己发的、或正在查看该会话 → 不计未读（消息就在眼前，亮红点没有意义）。
    final muted = m.uin == myUin || _isViewing(ChatSessionType.friend, uin2);
    if (existing != null) {
      _friendSessions[uin2] = existing.copyWith(
        lastMessage: m,
        unreadCount: muted ? existing.unreadCount : existing.unreadCount + 1,
      );
    } else {
      // 会话不存在时补建（与 [_upsertGroupMessage] 的群路径一致）：从好友列表
      // 直接进聊天时可能还没有会话对象，若不补建，消息虽然照常落库却没有
      // `chat_sessions` 行（[_persistSession] 以会话已存在为前提）—— 于是重启后
      // 该会话根本不会出现在列表里，表现为「聊天记录/会话丢失」。
      // 昵称先用迷你号兜底，登录时 `_loadFriendSessions` / 好友缓存会补成真昵称。
      _friendSessions[uin2] = ChatSession(
        id: uin2,
        type: ChatSessionType.friend,
        name: '$uin2',
        lastMessage: m,
        unreadCount: muted ? 0 : 1,
      );
    }
    _eventCtrl.add(ChatEvent(ChatSessionType.friend, uin2, m));
    _persistMessage(ChatSessionType.friend, uin2, m);
    _emitSessionSnapshot();
  }

  void _upsertGroupMessage(int groupId, ChatMessage m) {
    final key = _sessionKey(ChatSessionType.group, groupId);
    final list = _messagesCache.putIfAbsent(key, () => []);
    // 去重逻辑同 _upsertFriendMessage。
    if (list.any((e) => _sameMessage(e, m))) return;
    list.add(m);
    if (list.length > 100) list.removeRange(0, list.length - 100);

    final existing = _groupSessions[groupId];
    // 同好友路径：自己发的 / 正在查看该会话 → 不计未读。
    final muted = m.uin == myUin || _isViewing(ChatSessionType.group, groupId);
    if (existing != null) {
      _groupSessions[groupId] = existing.copyWith(
        lastMessage: m,
        unreadCount: muted ? existing.unreadCount : existing.unreadCount + 1,
      );
    } else if (!muted) {
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

  /// 持久化一条消息 + 更新会话行。写库失败仅记录日志，不阻断消息链路。
  void _persistMessage(ChatSessionType type, int id, ChatMessage m) {
    final db = _db;
    if (db == null || myUin == 0) return;
    final key = _sessionKey(type, id);
    final owner = myUin;
    unawaited(() async {
      try {
        await db.insertMessage(
          chatMessageToCompanion(m, key, myUin: owner, ownerUin: owner),
        );
      } catch (e) {
        log.error('persist message failed: $e', tag: _logTag);
      }
    }());
    _persistSession(type, id);
  }

  /// 持久化会话行（未读/最后消息，按账号隔离）。
  void _persistSession(ChatSessionType type, int id) {
    final db = _db;
    if (db == null || myUin == 0) return;
    final s = type == ChatSessionType.friend
        ? _friendSessions[id]
        : _groupSessions[id];
    if (s == null) return;
    unawaited(() async {
      try {
        await db.upsertSession(chatSessionToCompanion(s, ownerUin: myUin));
      } catch (e) {
        // 写会话行失败必须留痕：历史上这里没有 try/catch，schema 与 drift 生成的
        // ON CONFLICT 不匹配时抛的是「未捕获的异步异常」，只在 logcat 里刷
        // Unhandled Exception，应用侧完全无感 —— 表现就是重启后会话丢失。
        log.error('persist session failed: $e', tag: _logTag);
      }
    }());
  }

  void _replaceHistory(ChatSessionType type, int id, List<ChatMessage> msgs) {
    if (msgs.isEmpty) return;
    final key = _sessionKey(type, id);
    // 缓存以 time 升序为规范（离线/网络历史乱序到达时归位）。
    final sorted = sortMessagesAscending(msgs);
    _messagesCache[key] = sorted;
    _persistHistory(type, id, sorted);
    // 回填会话摘要（最后一条消息）：否则网络历史拉回后会话列表
    // 不显示最近消息，也无法区分"已聊过"与"纯好友"。
    final map = type == ChatSessionType.friend
        ? _friendSessions
        : _groupSessions;
    final existing = map[id];
    if (existing != null) {
      map[id] = existing.copyWith(lastMessage: sorted.last);
      _persistSession(type, id);
    }
    _emitSessionSnapshot();
    // 通知已打开的聊天窗口刷新（复用 ChatEvent：provider 只按 type/id 匹配，
    // 收到后重新 yield historyOf）
    _eventCtrl.add(ChatEvent(type, id, sorted.last));
  }

  /// 持久化整段历史（先清空该会话旧消息再批量写入，避免重复）。
  void _persistHistory(ChatSessionType type, int id, List<ChatMessage> msgs) {
    final db = _db;
    if (db == null) return;
    final key = _sessionKey(type, id);
    unawaited(_replaceHistoryInDb(db, key, msgs));
  }

  Future<void> _replaceHistoryInDb(
    AppDatabase db,
    String key,
    List<ChatMessage> msgs,
  ) async {
    // 原子替换：清空 + 批量写入在一个事务内完成，中途失败不留半写状态。
    final owner = myUin;
    if (owner == 0) return;
    await db.replaceMessages(
      owner,
      key,
      msgs
          .map(
            (m) =>
                chatMessageToCompanion(m, key, myUin: owner, ownerUin: owner),
          )
          .toList(),
    );
  }

  void _emitSessionSnapshot() {
    _sessionsCache = null; // 会话数据变更 → 下次访问重算
    _sessionCtrl.add(SessionSnapshot(sessions, _contacts));
  }

  // ── 正在查看的会话 ───────────────────────────────────────────────────

  /// 用户此刻正在看的会话（聊天页进入时登记、离开时清空）。
  ChatSessionType? _viewingType;
  int? _viewingId;

  /// [type]/[id] 是否正是用户此刻在看的那个会话。
  bool _isViewing(ChatSessionType type, int id) =>
      _viewingType == type && _viewingId == id;

  /// 登记 / 清空「当前正在查看的会话」。
  ///
  /// - 传具体会话：登记为正在查看；[autoRead] 为 true 时顺带标记已读。
  /// - 传 null：表示离开聊天页，此时会把**上一个**会话补标已读。
  ///
  /// 为什么需要它：消息到达时只看「谁发的」就累加未读，会出现在聊天页里亲眼看着
  /// 消息进来、返回列表后却仍亮红点的情况。登记后这类消息不再计入未读；
  /// 离开时再补一次已读，保证红点一定消掉。
  void setViewing(ChatSessionType? type, int? id, {bool autoRead = true}) {
    final prevType = _viewingType;
    final prevId = _viewingId;
    _viewingType = type;
    _viewingId = id;
    if (type != null && id != null) {
      if (autoRead) markRead(type, id);
    } else if (prevType != null && prevId != null && autoRead) {
      markRead(prevType, prevId);
    }
  }

  // ── 已读/刷新 ─────────────────────────────────────────────────────────

  /// 标记会话已读（重置未读）。
  void markRead(ChatSessionType type, int id) {
    final sessionsMap = type == ChatSessionType.friend
        ? _friendSessions
        : _groupSessions;
    final existing = sessionsMap[id];
    if (existing != null) {
      sessionsMap[id] = existing.copyWith(
        unreadCount: 0,
        lastReadTime: DateTime.now().millisecondsSinceEpoch ~/ 1000,
      );
    }
    _persistSession(type, id);
    _emitSessionSnapshot();
  }

  // ── 个人资料 ──────────────────────────────────────────────────────────

  /// 修改当前账号昵称。
  ///
  /// 对齐反编译 `AccountManager:requestModifyRole`：
  /// `remote_call("baseinfo", "rename", name, forfree, useChangeCard)`。
  /// [useChangeCard] 为"改名卡"分支（有卡则免费）；返回业务码：
  /// `0` 成功，其余见 [renameErrorText]。
  ///
  /// 注意：改名会真实作用于游戏账号，可能消耗迷你币并进入审核。
  Future<int> renameSelf(String newName, {bool useChangeCard = false}) async {
    final code = await _commands.renameSelf(newName, useChangeCard: useChangeCard);
    if (code == 0) applyLocalNickname(newName);
    return code;
  }

  /// 改名成功后本地更新当前账号昵称，并广播状态让 UI（设置页/账号信息）刷新。
  /// [MiniAuth] 不可变，故整体替换。
  void applyLocalNickname(String name) {
    final a = _auth;
    if (a == null) return;
    _auth = a.copyWith(name: name);
    _emitSessionSnapshot();
    _setState(_state);
  }

  /// 拉取某玩家的冒险家等级（`mini_season` get_other_player_score）。
  Future<Map<String, Object?>?> otherPlayerScore(int uin) =>
      _commands.otherPlayerScore(uin);

  /// 拉取玩家主页数据（get_user_homepage）。
  ///
  /// [moduleList] 默认 [PlayerHomeModule.fullList]（主页全部组件模块），
  /// 返回的 `data` map 以模块名为键（`{模块名: {data: {...}}}`），
  /// 交由 `core/models/homepage_modules.dart` 的纯解析器取值。
  Future<Map<String, Object?>?> userHomepage(
    int uin, {
    String moduleList = PlayerHomeModule.fullList,
  }) async {
    final a = _auth;
    if (a == null) return null;
    final client = PlayerHomeClient(uin: a.uin, s2: a.s2, s2t: a.s2t);
    return client.getUserHomepage(uin, moduleList: moduleList);
  }

  /// 拉取角色等级（miniw/upgrade get_level_info_batch）。无则返回 0。
  Future<int> platformLevel(int uin) => _commands.platformLevel(uin);

  /// 称号名称（远程 visual-cfg `title_manager`，进程内缓存）。无则 null。
  Future<String?> titleName(int titleId) => _commands.titleName(titleId);

  /// 删除好友（对齐反编译 `buddysvr.buddy_rm`，参数 uin）。成功返回 true。
  Future<bool> removeFriend(int uin) async {
    final code = await _commands.removeFriend(uin);
    if (code == 0) {
      _friendSessions.remove(uin);
      _contacts.removeWhere((c) => c.uin == uin);
      _emitSessionSnapshot();
      await _saveFriendCache();
    }
    return code == 0;
  }

  // ── 清理 ──────────────────────────────────────────────────────────────

  /// 登出时调用：关闭连接、清空缓存，保留控制器以支持重新登录。
  Future<void> reset() async {
    await _connection.close();
    _auth = null;
    _friend = null;
    _group = null;
    _messageCenter = null;
    _socialSign = null;
    _playerHome = null;
    _syncCommandClient();
    _friendSessions.clear();
    _groupSessions.clear();
    _contacts.clear();
    _messagesCache.clear();
    _groupInfos.clear();
    _dispatcher.clear();
    _sessionsCache = null;
    _state = ChatServiceState.unauthenticated;
    _lastError = null;
    _setState(ChatServiceState.unauthenticated);
  }

  /// 释放服务：先 reset 清理状态与连接，再关闭 4 个事件流控制器。
  /// 控制器若不关闭，监听者永远等不到 done 事件，造成泄漏。
  Future<void> dispose() async {
    await reset();
    await _stateCtrl.close();
    await _eventCtrl.close();
    await _sessionCtrl.close();
    await _dispatcher.dispose();
  }

  // ── 内部 ──────────────────────────────────────────────────────────────

  void _setState(ChatServiceState s) {
    _state = s;
    if (!_stateCtrl.isClosed) _stateCtrl.add(s);
  }
}
