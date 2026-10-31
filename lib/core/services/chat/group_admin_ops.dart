/// 群管理协议层：成员/申请/群设置的服务端调用。
///
/// 从 ChatService 拆出的协作者：只持有群客户端与命令客户端的取用回调，
/// 不碰会话缓存与事件流；ChatService 保留同名公开方法并转发，调用方不变。
library;

import '../group.dart' show GroupClient;
import 'command_client.dart' show ChatCommandClient;

class GroupAdminOps {
  GroupAdminOps({
    required this.getGroup,
    required this.getCommands,
    required this.refreshSessions,
  });

  final GroupClient? Function() getGroup;
  final ChatCommandClient Function() getCommands;

  /// 退群/解散后刷新会话列表。
  final Future<void> Function() refreshSessions;

  GroupClient get _group =>
      getGroup() ?? (throw StateError('not logged in'));

  ChatCommandClient get _commands => getCommands();

  /// 查询群详情（刷新 [GroupInfo] 并返回 group_id）。
  Future<Map<String, Object?>> refreshGroupInfo(int groupId) =>
      _commands.refreshGroupInfo(groupId);

  Future<Map<String, Object?>> quitGroup(int groupId) async {
    final resp = await _commands.quitGroup(groupId);
    await refreshSessions();
    return resp;
  }

  Future<Map<String, Object?>> dissolveGroup(int groupId) async {
    final resp = await _commands.dissolveGroup(groupId);
    await refreshSessions();
    return resp;
  }

  Future<Map<String, Object?>> transferGroup(int groupId, int newLord) async {
    final resp = await _commands.transferGroup(groupId, newLord);
    await refreshSessions();
    return resp;
  }

  Future<Map<String, Object?>> setGroupTop(
    int groupId, {
    required bool top,
  }) => _group.setGroupTop(groupId, top: top);

  Future<Map<String, Object?>> setGroupMemberSilent(
    int groupId, {
    required int opUin,
    required bool silent,
  }) => _group.setSilent(groupId, opUin: opUin, silent: silent);

  Future<Map<String, Object?>> setGroupMemberBanned(
    int groupId, {
    required int opUin,
    required bool ban,
  }) => _group.setBan(groupId, opUin: opUin, ban: ban);

  Future<Map<String, Object?>> reportGroupMember(
    int groupId, {
    required int opUin,
  }) => _group.reportGroupUser(groupId, opUin: opUin);

  Future<Map<String, Object?>> rejectAllGroupApplies(int groupId) =>
      _group.rejectGroupApplyAll(groupId);

  Future<Map<String, Object?>> kickGroupMembers(
    int groupId, {
    required List<int> uins,
    int groupCreator = 0,
    String groupName = '',
  }) => _group.kickMembers(
    groupId: groupId,
    uins: uins,
    groupCreator: groupCreator,
    groupName: groupName,
  );

  Future<Map<String, Object?>> setGroupIgnore(
    int groupId, {
    required bool ignore,
  }) => _group.setGroupIgnore(groupId, ignore: ignore);

  Future<Map<String, Object?>> updateGroupInfo(
    int groupId, {
    required String name,
    required int iconId,
    required int iconType,
  }) async {
    final resp = await _group.updateGroupInfo(
      groupId: groupId,
      groupName: name,
      iconId: iconId,
      iconType: iconType,
    );
    await refreshGroupInfo(groupId);
    return resp;
  }

  Future<Map<String, Object?>> groupApplyList() =>
      _group.queryGroupApplyList();

  Future<Map<String, Object?>> agreeGroupApply(int groupId) =>
      _group.agreeGroupApply(groupId);

  Future<Map<String, Object?>> rejectGroupApply(int groupId) =>
      _group.rejectGroupApply(groupId);

  Future<Map<String, Object?>> quitGroupRecords() =>
      _group.queryUserGroupsQuitList();

  Future<Map<String, Object?>> delQuitGroupRecord(int groupId) =>
      _group.delGroupQuitList(groupId);

  Future<Map<String, Object?>> setAllowInvitedToGroup({
    required bool allow,
  }) => _group.updateUserGroupsJoin(allow: allow);

  Future<Map<String, Object?>> setAllowAutoJoinGroup({
    required bool allow,
  }) => _group.updateUserGroupsAutoJoin(allow: allow);
}
