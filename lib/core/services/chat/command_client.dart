/// ChatCommandClient —— 纯业务 RPC 包装器。
///
/// 只依赖网络客户端（friend/group/chatpush conn）+ 认证状态（myUin/extend data），
/// **不触碰**会话缓存 / 推送分发 / 持久化等副作用——那些由 [ChatService] 编排。
///
/// 可变引用由 [ChatService] 在 login / reset / connect 时同步更新。
library;

import 'dart:convert';

import '../auth.dart';
import '../chatpush.dart';
import '../friend.dart';
import '../group.dart';
import '../name_rules.dart' show extractRpcCode;
import '../player_home.dart';
import '../title_config.dart';

/// 纯 RPC 命令客户端：把网络调用从 [ChatService] 剥离，降低耦合。
class ChatCommandClient {
  ChatCommandClient();

  /// 当前认证状态（login 后设置，reset 后清空）。
  MiniAuth? auth;

  /// 好友客户端（login 后设置）。
  FriendClient? friend;

  /// 群客户端（login 后设置）。
  GroupClient? group;

  /// ChatPush 长连接（connect 后设置，断开后清空）。
  ChatPushConnection? conn;

  /// 玩家主页客户端（login 后设置）。
  PlayerHomeClient? playerHome;

  /// 称号配置客户端（进程单例）。
  static final TitleConfigClient titleConfig = TitleConfigClient();

  int get myUin => auth?.uin ?? 0;

  // ── extend_data ────────────────────────────────────────────────────────

  /// 构造真实客户端风格的 extend_data：
  /// `url_encode(base64(JSON{nickname, shareType:0, bubble, interCode}))`
  /// （mainchatinterface.lua:114-123 原样复刻）。
  String buildExtendData() {
    final a = auth;
    final tShare = <String, Object?>{
      'nickname': a?.name ?? '',
      'shareType': 0, // ShareType.TEXT
      'bubble': 0,
      'interCode': null,
    };
    final raw = base64Encode(utf8.encode(jsonEncode(tShare)));
    return Uri.encodeQueryComponent(raw);
  }

  // ── 消息发送 ────────────────────────────────────────────────────────────

  /// 发送好友私聊消息（纯 RPC，不含乐观回显）。
  Future<Map<String, Object?>> sendFriendMessage(int desUin, String msg) async {
    final friend = this.friend;
    if (friend == null) throw StateError('not logged in');
    return friend.sendChatMsg(
      desUin: desUin,
      msg: msg,
      extendData: buildExtendData(),
    );
  }

  /// 发送群聊消息（纯 RPC）。
  Future<Map<String, Object?>> sendGroupMessage(int groupId, String msg) async {
    final group = this.group;
    if (group == null) throw StateError('not logged in');
    return group.sendMsg(groupId: groupId, text: msg);
  }

  // ── 好友申请 ─────────────────────────────────────────────────────────────

  /// 发起好友申请（纯 RPC；副作用由 ChatService 编排）。
  Future<Map<String, Object?>> applyFriend(int desUin) async {
    final friend = this.friend;
    if (friend == null) throw StateError('not logged in');
    return friend.applyFriend(desUin: desUin, from: '5');
  }

  /// 通过好友申请（纯 RPC）。
  Future<Map<String, Object?>> acceptFriendRequest(int uin) async {
    final friend = this.friend;
    if (friend == null) throw StateError('not logged in');
    return friend.acceptApply(desUin: uin);
  }

  /// 拒绝好友申请（纯 RPC）。
  Future<Map<String, Object?>> rejectFriendRequest(int uin) async {
    final friend = this.friend;
    if (friend == null) throw StateError('not logged in');
    return friend.rejectApply(desUin: uin);
  }

  // ── 黑名单（纯 RPC）─────────────────────────────────────────────────────

  /// 加入黑名单（op_type=1）。
  Future<Map<String, Object?>> addBlacklist(int desUin) async {
    final friend = this.friend;
    if (friend == null) throw StateError('not logged in');
    return friend.addBlacklist(desUin);
  }

  /// 移出黑名单（op_type=0）。
  Future<Map<String, Object?>> removeBlacklist(int desUin) async {
    final friend = this.friend;
    if (friend == null) throw StateError('not logged in');
    return friend.removeBlacklist(desUin);
  }

  /// 清空黑名单。
  Future<Map<String, Object?>> clearBlacklist() async {
    final friend = this.friend;
    if (friend == null) throw StateError('not logged in');
    return friend.clearBlacklist();
  }

  // ── 群管理（纯 RPC）─────────────────────────────────────────────────────

  /// 查询群详情（返回 group_id；刷新 GroupInfo 由 ChatService 编排）。
  Future<Map<String, Object?>> refreshGroupInfo(int groupId) async {
    final group = this.group;
    if (group == null) throw StateError('not logged in');
    return group.queryGroup(groupId);
  }

  /// 退出群（纯 RPC）。
  Future<Map<String, Object?>> quitGroup(int groupId) async {
    final group = this.group;
    if (group == null) throw StateError('not logged in');
    return group.quitGroup(groupId);
  }

  /// 解散群（纯 RPC）。
  Future<Map<String, Object?>> dissolveGroup(int groupId) async {
    final group = this.group;
    if (group == null) throw StateError('not logged in');
    return group.dissolveGroup(groupId);
  }

  /// 转让群主（纯 RPC）。
  Future<Map<String, Object?>> transferGroup(int groupId, int newLord) async {
    final group = this.group;
    if (group == null) throw StateError('not logged in');
    return group.transferGroup({
      'group_id': '$groupId',
      'op_uin': '$newLord',
    });
  }

  // ── 经 chatpush conn 的 RPC ─────────────────────────────────────────────

  /// 改名（baseinfo.rename）。返回业务码；本地昵称更新由 ChatService 编排。
  /// 未连接返回 20（NOT_YET）。
  Future<int> renameSelf(String newName, {bool useChangeCard = false}) async {
    final conn = this.conn;
    if (conn == null) return 20; // NOT_YET：未连接
    final r = await conn.sendRpc('baseinfo', 'rename', [
      newName,
      useChangeCard,
      useChangeCard,
    ], timeout: const Duration(seconds: 12));
    return extractRpcCode(code: r.code, result: r.result);
  }

  /// 删除好友（buddysvr.buddy_rm）。返回业务码（0=成功）；会话清理由 ChatService 编排。
  /// 未连接返回 -1（≠0 → 调用方判 false）。
  Future<int> removeFriend(int uin) async {
    final conn = this.conn;
    if (conn == null) return -1;
    final r = await conn.sendRpc('buddysvr', 'buddy_rm', [uin]);
    return extractRpcCode(code: r.code, result: r.result);
  }

  // ── 资料查询 ────────────────────────────────────────────────────────────

  /// 拉取某玩家的冒险家等级（mini_season get_other_player_score）。
  Future<Map<String, Object?>?> otherPlayerScore(int uin) async {
    final client = _playerHomeClient();
    if (client == null) return null;
    return client.getOtherPlayerScore(uin);
  }

  /// 拉取角色等级（miniw/upgrade get_level_info_batch）。无则返回 0。
  Future<int> platformLevel(int uin) async {
    final client = _playerHomeClient();
    if (client == null) return 0;
    final map = await client.getPlatformLevels([uin]);
    return map[uin] ?? 0;
  }

  /// 复用同一个 [PlayerHomeClient]。
  ///
  /// 它带实例级缓存（见 kPlayerHomeCacheTtl）：玩家卡片与玩家主页共享同一份
  /// `get_level_info_batch` / `get_user_homepage` —— 以前这两处各 new 一个
  /// 客户端，缓存等于没有，卡片→主页就是重复发。
  PlayerHomeClient? _playerHomeClient() {
    final existing = playerHome;
    if (existing != null) return existing;
    final a = auth;
    if (a == null) return null;
    return playerHome = PlayerHomeClient(uin: a.uin, s2: a.s2, s2t: a.s2t);
  }

  /// 称号名称（远程 visual-cfg `title_manager`，进程内缓存）。无则 null。
  Future<String?> titleName(int titleId) async {
    final id = titleId;
    if (id <= 0) return null;
    return titleConfig.titleName(id);
  }
}
