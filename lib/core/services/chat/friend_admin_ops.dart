/// 好友申请 / 黑名单 / 关注：服务端调用与申请状态清理。
///
/// 从 ChatService 拆出的协作者；会话刷新与申请状态由回调注入，公开方法仍留在
/// ChatService 上并转发。
library;

import '../../models/messages.dart' show FriendRequestStatus;
import '../friend.dart' show FriendClient;
import 'command_client.dart' show ChatCommandClient;

class FriendAdminOps {
  FriendAdminOps({
    required this.getCommands,
    required this.getFriend,
    required this.removeRequest,
    required this.refreshSessions,
  });

  final ChatCommandClient Function() getCommands;
  final FriendClient? Function() getFriend;
  final void Function(int uin, FriendRequestStatus status) removeRequest;
  final Future<void> Function() refreshSessions;

  ChatCommandClient get _commands => getCommands();

  Future<Map<String, Object?>> applyFriend(int desUin) =>
      _commands.applyFriend(desUin);

  Future<Map<String, Object?>> acceptFriendRequest(int uin) async {
    final resp = await _commands.acceptFriendRequest(uin);
    removeRequest(uin, FriendRequestStatus.accepted);
    await refreshSessions();
    return resp;
  }

  Future<Map<String, Object?>> rejectFriendRequest(int uin) async {
    final resp = await _commands.rejectFriendRequest(uin);
    removeRequest(uin, FriendRequestStatus.rejected);
    return resp;
  }

  Future<Map<String, Object?>> addBlacklist(int desUin) async {
    final resp = await _commands.addBlacklist(desUin);
    await refreshSessions();
    return resp;
  }

  Future<Map<String, Object?>> removeBlacklist(int desUin) async {
    final resp = await _commands.removeBlacklist(desUin);
    await refreshSessions();
    return resp;
  }

  Future<Map<String, Object?>> clearBlacklist() async {
    final resp = await _commands.clearBlacklist();
    await refreshSessions();
    return resp;
  }

  Future<Map<String, Object?>> followPlayer(
    int desUin, {
    required bool follow,
  }) async {
    final friend = getFriend();
    if (friend == null) throw StateError('not logged in');
    final resp = await friend.attentionFriend(desUin, follow: follow);
    await refreshSessions();
    return resp;
  }
}
