/// ChatService —— 外部聊天客户端核心编排器。
/// 串联：登录(login_v3+WS心跳) → ChatPush 长连接 → 好友/群消息收发 → 推送分发。
/// 对齐反编译源码：friend.msg 推送(cmd 分发) + buddysvr speek/chat_query。
library;

import 'dart:async';
import 'dart:convert';
import 'dart:math' show Random;

import 'package:flutter/foundation.dart' show visibleForTesting;

import '../models/emoji_catalog.dart' show ImfcEmoji, imfcInterCode, imfcMessageText;
import '../models/messages.dart';
import '../storage/app_database.dart';
import 'auth.dart';
import 'chat/command_client.dart';
import 'chat/connection_manager.dart';
import 'chat/group_name_cache.dart';
import 'chat/message_store.dart';
import 'chat/message_upserter.dart';
import 'chat/offline_cache.dart';
import 'chat/profile_cache.dart';
import 'chat/session_loader.dart';
import 'chat/push_dispatcher.dart';
import 'chatpush.dart';
import 'friend.dart';
import 'group.dart';
import 'message_center.dart';
import 'miniw_extra.dart';
import 'name_rules.dart';
import 'player_home.dart';
import 'profile.dart';
import 'social_sign.dart';
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
  EmojiClient? _emoji;
  BubbleClient? _bubble;
  FriendGiftClient? _gift;
  RedPacketClient? _redPacket;

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

  /// 资料缓存（好友/群成员昵称头像 + 群详情解析）。
  late final ProfileCache _profiles;

  /// 消息/会话本地持久化。
  late final MessageStore _store;

  /// 新消息写入（内存 upsert + 去重 + 未读计数 + 通知）。
  late final MessageUpserter _upserter;

  /// 离线缓存加载（启动时从 SQLite 恢复会话/消息/好友）。
  late final OfflineCache _offlineCache;

  /// 会话加载（好友/群列表合并 + 写回好友缓存）。
  late final SessionLoader _sessionLoader;

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
      upsertFriendMessage: (uin, m) => _upserter.upsertFriend(uin, m),
      upsertGroupMessage: (gid, m) => _upserter.upsertGroup(gid, m),
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
    _profiles = ProfileCache(
      getAuth: () => _auth,
      getMyUin: () => myUin,
      friendSessions: _friendSessions,
      contacts: _contacts,
      groupMemberProfiles: _groupMemberProfiles,
      emitSessionSnapshot: _emitSessionSnapshot,
      saveFriendCache: () => _sessionLoader.saveFriendCache(),
    );
    _store = MessageStore(
      getDb: () => _db,
      getMyUin: () => myUin,
      friendSessions: _friendSessions,
      groupSessions: _groupSessions,
    );
    _upserter = MessageUpserter(
      messagesCache: _messagesCache,
      friendSessions: _friendSessions,
      groupSessions: _groupSessions,
      getMyUin: () => myUin,
      isViewing: _isViewing,
      emitEvent: (type, id, m) => _eventCtrl.add(ChatEvent(type, id, m)),
      store: _store,
      emitSessionSnapshot: _emitSessionSnapshot,
    );
    _offlineCache = OfflineCache(
      getDb: () => _db,
      getMyUin: () => myUin,
      friendSessions: _friendSessions,
      groupSessions: _groupSessions,
      contacts: _contacts,
      messagesCache: _messagesCache,
      loadGroupNames: () => _groupNames.load(),
      emitSessionSnapshot: _emitSessionSnapshot,
    );
    _sessionLoader = SessionLoader(
      getFriend: () => _friend,
      getGroup: () => _group,
      getDb: () => _db,
      getMyUin: () => myUin,
      contacts: _contacts,
      friendSessions: _friendSessions,
      groupSessions: _groupSessions,
      groupInfos: _groupInfos,
      messagesCache: _messagesCache,
      rawFriendRequests: () => _dispatcher.rawFriendRequests,
      emitFriendRequests: _dispatcher.emitFriendRequests,
      fetchFriendInfos: _profiles.fetchFriendInfos,
      groupInfoFrom: _profiles.groupInfoFrom,
      emitSessionSnapshot: _emitSessionSnapshot,
      persistGroupNames: _groupNames.persist,
      offlineLoad: _offlineCache.load,
      requestFriendHistory: requestFriendHistory,
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
  /// `_sessionLoader.bootstrap()` 很可能在订阅建立之前就已 emit 完毕 —— 那样订阅者
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

  /// 好友客户端（登录后可用，未登录返回 null）。
  FriendClient? get friend => _friend;

  /// 表情系统客户端（登录后可用，未登录返回 null）。
  EmojiClient? get emoji => _emoji;

  /// 聊天气泡客户端（登录后可用，未登录返回 null）。
  BubbleClient? get bubble => _bubble;

  /// 好友礼物客户端（登录后可用，未登录返回 null）。
  FriendGiftClient? get gift => _gift;

  /// 红包客户端（登录后可用，未登录返回 null）。
  RedPacketClient? get redPacket => _redPacket;

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
      _emoji ??= EmojiClient(uin: uin, s2: auth.s2, s2t: auth.s2t);
      _bubble ??= BubbleClient(uin: uin, s2: auth.s2, s2t: auth.s2t);
      _gift ??= FriendGiftClient(uin: uin, s2: auth.s2, s2t: auth.s2t);
      _redPacket ??= RedPacketClient(uin: uin, s2: auth.s2, s2t: auth.s2t);
      _syncCommandClient();
      _setState(ChatServiceState.connected);
      await _connectChatPush();
      await _sessionLoader.bootstrap();
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

  /// 群置顶/取消置顶（服务端，act=set_group_top）。
  /// 与「会话置顶」（本地 kv）不同：这是账号级的群置顶。
  Future<Map<String, Object?>> setGroupTop(
    int groupId, {
    required bool top,
  }) async {
    final group = _group;
    if (group == null) throw StateError('not logged in');
    return group.setGroupTop(groupId, top: top);
  }

  /// 禁言/取消禁言群成员（act=set_silent）。
  Future<Map<String, Object?>> setGroupMemberSilent(
    int groupId, {
    required int opUin,
    required bool silent,
  }) {
    final group = _group;
    if (group == null) throw StateError('not logged in');
    return group.setSilent(groupId, opUin: opUin, silent: silent);
  }

  /// 屏蔽/取消屏蔽群成员消息（act=set_ban）。
  Future<Map<String, Object?>> setGroupMemberBanned(
    int groupId, {
    required int opUin,
    required bool ban,
  }) {
    final group = _group;
    if (group == null) throw StateError('not logged in');
    return group.setBan(groupId, opUin: opUin, ban: ban);
  }

  /// 举报群成员（act=report_group_user）。
  Future<Map<String, Object?>> reportGroupMember(
    int groupId, {
    required int opUin,
  }) {
    final group = _group;
    if (group == null) throw StateError('not logged in');
    return group.reportGroupUser(groupId, opUin: opUin);
  }

  /// 一键拒绝全部入群申请（act=reject_group_apply_all）。
  Future<Map<String, Object?>> rejectAllGroupApplies(int groupId) {
    final group = _group;
    if (group == null) throw StateError('not logged in');
    return group.rejectGroupApplyAll(groupId);
  }

  // ── 好友设置 / 社交（服务端同步）────────────────────────────────────────

  /// 修改好友备注（cmd=set_note，服务端同步）。成功刷新会话列表使昵称生效。
  Future<Map<String, Object?>> setFriendNote(int uin, String note) async {
    final friend = _friend;
    if (friend == null) throw StateError('not logged in');
    final resp = await friend.setNote(uin, note);
    await loadSessions();
    return resp;
  }

  /// 设置好友上线提醒（cmd=set_online_notify_flag，服务端同步）。
  Future<Map<String, Object?>> setFriendOnlineNotify(
    int uin, {
    required bool on,
  }) {
    final friend = _friend;
    if (friend == null) throw StateError('not logged in');
    return friend.setOnlineNotifyFlag(uin, on: on);
  }

  /// 好友置顶/取消置顶（cmd=set_sort_flag）。
  Future<Map<String, Object?>> setFriendTop(
    int uin, {
    required bool top,
  }) {
    final friend = _friend;
    if (friend == null) throw StateError('not logged in');
    return friend.setSortFlag(uin, top: top);
  }

  /// 一键拒绝全部好友申请（cmd=reject_apply_all）。成功后清空本地待处理申请。
  Future<Map<String, Object?>> rejectAllFriendRequests() async {
    final friend = _friend;
    if (friend == null) throw StateError('not logged in');
    final resp = await friend.rejectApplyAll();
    _dispatcher.rejectAllPending();
    return resp;
  }

  /// 拍一拍好友（cmd=take_pat）。成功后本地回显一条拍一拍消息。
  Future<Map<String, Object?>> patFriend(int desUin, {String? myName}) async {
    final friend = _friend;
    if (friend == null) throw StateError('not logged in');
    final resp = await friend.takePat(desUin);
    final code = resp['result'] ?? resp['ret'];
    if (code is num && code == 0) {
      final me = myName ?? myNickname;
      final m = ChatMessage(
        uin: myUin,
        text: '$me 拍了拍你',
        time: DateTime.now().millisecondsSinceEpoch ~/ 1000,
        isSuccess: true,
      );
      _upserter.upsertFriend(desUin, m);
    }
    return resp;
  }

  /// 发送互动表情「骰子 / 猜拳」。
  ///
  /// 对齐反编译 `EmojiBtnTemplate_StructureSendText`：随机取 1..mod 作为结果，
  /// `interCode = "@IMFC&<序号>_<结果>"`；消息文本是
  /// `JSON{content: 低版本占位文案, extend_data: interCode}`；
  /// extend_data 里也带一份 `interCode`（`DeCodeIMFCMsg` 优先读它）。
  /// 返回实际结果（1 起），供 UI 提示。
  Future<int> sendImfcEmoji(int desUin, ImfcEmoji emoji) async {
    final friend = _friend;
    final auth = _auth;
    if (friend == null || auth == null) throw StateError('not logged in');
    final result = 1 + _random.nextInt(emoji.mod);
    final interCode = imfcInterCode(emoji.index, result);
    final text = imfcMessageText(emoji.index, result);
    final extend = _emojiExtendData(interCode);
    await friend.sendChatMsg(desUin: desUin, msg: text, extendData: extend);
    // 本地乐观回显：文本保持 JSON 信封，气泡会解析成结果图。
    _upserter.upsertFriend(
      desUin,
      ChatMessage(
        uin: myUin,
        text: text,
        time: DateTime.now().millisecondsSinceEpoch ~/ 1000,
        isSuccess: true,
        interCode: interCode,
        isLive: true,
      ),
    );
    return result;
  }

  /// 赠送礼物（`miniw/welfare?act=give_gift`）。
  ///
  /// 成功后按游戏客户端的做法，在聊天里补一条 `Type=SendFriendGift` 的卡片消息
  /// （`friendgiftdatamgr.lua:389-460` 的 `NewSendGiftMsg`）：游戏端也是自己发
  /// 这条消息的，不发的话对方只能拿到礼物、聊天里什么都没有。
  Future<bool> sendGift({
    required int desUin,
    required int itemId,
    required int num,
    required int payType,
    int addValue = 0,
  }) async {
    final friend = _friend;
    final gift = _gift;
    if (friend == null || gift == null) throw StateError('not logged in');
    final resp = await gift.giveGift(
      opUin: desUin,
      itemId: itemId,
      num: num,
      type: payType,
      roleName: myNickname,
    );
    final code = resp['ret'] ?? resp['code'];
    if (code == null || '$code' != '0') return false;

    final data = resp['data'];
    final token = data is Map ? (data['token']?.toString() ?? '') : '';
    final extend = _giftExtendData(
      itemId: itemId,
      num: num,
      addValue: addValue,
      desUin: desUin,
      token: token,
    );
    // 低版本提示文案（GetS(70974) 取逗号前那段），正文只为兼容旧客户端。
    final text = '收到来自「$myNickname」的默契礼物';
    try {
      await friend.sendChatMsg(desUin: desUin, msg: text, extendData: extend);
    } catch (_) {
      // 礼物已送出，卡片发失败不影响结果
    }
    _upserter.upsertFriend(
      desUin,
      ChatMessage(
        uin: myUin,
        text: text,
        time: DateTime.now().millisecondsSinceEpoch ~/ 1000,
        isSuccess: true,
        extendData: extend,
        type: ChatMsgType.custom,
        isLive: true,
      ),
    );
    return true;
  }

  /// 礼物卡的 extend_data：`url_encode(base64(JSON{Type:"SendFriendGift",...}))`。
  String _giftExtendData({
    required int itemId,
    required int num,
    required int addValue,
    required int desUin,
    required String token,
  }) {
    final t = <String, Object?>{
      'Type': 'SendFriendGift',
      'itemid': itemId,
      'num': num,
      'addValue': addValue,
      'des_uin': desUin,
      'src_uin': myUin,
      'src_name': myNickname,
      'token': token,
    };
    return Uri.encodeQueryComponent(
      base64Encode(utf8.encode(jsonEncode(t))),
    );
  }

  /// 组装带 [interCode] 的 extend_data：`url_encode(base64(JSON{...}))`
  /// （与 `ChatCommandClient.buildExtendData` 同一格式，额外带上 interCode）。
  String _emojiExtendData(String interCode) {
    final tShare = <String, Object?>{
      'nickname': myNickname,
      'shareType': 0, // ShareType.TEXT
      'bubble': 0,
      'interCode': interCode,
    };
    return Uri.encodeQueryComponent(
      base64Encode(utf8.encode(jsonEncode(tShare))),
    );
  }

  static final Random _random = Random();

  // ── 好友标签 / 分组（对齐 newfriendservice.lua:597-760）────────────────

  /// 批量设置好友上线通知（cmd=batch_set_online_notify_flag）。
  Future<Map<String, Object?>> setOnlineNotifyBatch(
    List<int> uins, {
    required bool on,
  }) {
    final friend = _friend;
    if (friend == null) throw StateError('not logged in');
    return friend.batchSetOnlineNotifyFlag(uins, on: on);
  }

  /// 好友标签池（cmd=query_friend_label_pool）。
  Future<Map<String, Object?>> friendLabelPool() {
    final friend = _friend;
    if (friend == null) throw StateError('not logged in');
    return friend.queryFriendLabelPool();
  }

  /// 新增（[opType]=1，需 [label]）/ 删除（=0，需 [tagId]）标签池里的标签。
  Future<Map<String, Object?>> setFriendLabelPool({
    required int opType,
    String? label,
    int? tagId,
  }) {
    final friend = _friend;
    if (friend == null) throw StateError('not logged in');
    return friend.setFriendLabelPool(
      opType: opType,
      label: label,
      tagId: tagId,
    );
  }

  /// 给好友批量打（[opType]=1）/ 去掉（=2）某个标签。
  Future<Map<String, Object?>> setFriendLabels(
    List<int> uins, {
    required int opType,
    int? tagId,
  }) {
    final friend = _friend;
    if (friend == null) throw StateError('not logged in');
    return friend.batchSetFriendLabel(uins, opType: opType, tagId: tagId);
  }

  /// 批量清除这些好友的全部标签。
  Future<Map<String, Object?>> clearFriendLabels(List<int> uins) {
    final friend = _friend;
    if (friend == null) throw StateError('not logged in');
    return friend.batchClearFriendLabels(uins);
  }

  /// 查询「拒绝陌生人加好友」开关（cmd=get_closeapply_flag）。开启返回 true。
  Future<bool> closeapplyEnabled() async {
    final friend = _friend;
    if (friend == null) throw StateError('not logged in');
    final resp = await friend.getCloseapplyFlag();
    final flag = resp['flag'] ?? resp['data'];
    return flag == 1 || flag == true || flag == '1';
  }

  /// 设置「拒绝陌生人加好友」开关（cmd=set_closeapply_flag）。
  Future<Map<String, Object?>> setCloseapplyEnabled({required bool on}) {
    final friend = _friend;
    if (friend == null) throw StateError('not logged in');
    return friend.setCloseapplyFlag(on: on);
  }

  /// 拉取好友离线/最近聊天记录（buddysvr chat_query）。
  ///
  /// 与游戏一致：**WS RPC 优先，HTTP 仅作后备**。`buddymanager.lua` 里
  /// `query_friend_info` / `batch_friend_info` / `friend_list` 都是
  /// `if not chatpushconn.isopen then self:chatpush_rpc(...) else cluster.*` 的分支，
  /// 即连接在就用 WS，只有连接不可用才走 HTTP `chatpush_rpc`（POST /minilb/rpc）。
  ///
  /// 2026-10-01 实测（真实账号，一条对方刚发来的离线消息）：
  /// - **WS `buddysvr.chat_query` 能取到**：`[0,[[uin, time, text, extendB64, "0"]]]`，
  ///   与 [ChatMessage.fromChatQueryTriple] 的期望形状一致；
  /// - **HTTP `/minilb/rpc` 同参返回 `[0,[]]`**（建 gate 连接前后都是空），
  ///   只有 WS 能拿到真实离线消息；
  /// - `chat_query` 是**消费式读取**：拿到一次后两边都变空。
  /// 所以这里 WS 优先，HTTP 仅作为连接不可用时的尽力后备（可能拿到空表）。
  Future<void> requestFriendHistory(int uin2) async {
    final auth = _auth;
    if (auth == null) return;
    try {
      List<dynamic>? resp;
      final conn = _connection.conn;
      if (conn != null) {
        try {
          final r = await conn.sendRpc(
            'buddysvr',
            'chat_query',
            <dynamic>[uin2],
            timeout: const Duration(seconds: 8),
          );
          final result = r.result;
          if (result is List) resp = result;
        } catch (e) {
          log.warn('chat_query WS 失败，退回 HTTP：$e', tag: _logTag);
        }
      }
      // 连接不可用（未登录 / 断线中）才走 HTTP 后备。
      resp ??= await _chatpush.rpcHttp(
        uin: auth.uin,
        s2: auth.s2,
        s2t: auth.s2t,
        message: [
          'buddysvr',
          'chat_query',
          DateTime.now().microsecondsSinceEpoch % 100000,
          DateTime.now().millisecondsSinceEpoch % 100000000,
          [uin2],
          <String, Object?>{},
        ],
      );
      // 两种通道响应同形：[0, msglist]
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
    _upserter.replaceHistory(ChatSessionType.friend, uin2, msgs);
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
      _upserter.replaceHistory(ChatSessionType.group, groupId, msgs);
    } catch (e) {
      log.warn('send_cache_msg failed for $groupId: $e', tag: _logTag);
    }
  }

  // ── 会话加载 ───────────────────────────────────────────────────────────

  /// 加载好友 + 群列表，构建会话。
  Future<void> loadSessions() => _sessionLoader.loadAll();

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
      _upserter.upsertFriend(sessionId, m);
    } else {
      _upserter.upsertGroup(sessionId, m);
    }
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
    _store.persistSession(type, id);
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
      await _sessionLoader.saveFriendCache();
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
    _emoji = null;
    _bubble = null;
    _gift = null;
    _redPacket = null;
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
