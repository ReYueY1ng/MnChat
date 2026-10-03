import 'dart:async';

import '../../models/messages.dart';
import '../../utils/log.dart';
import '../auth.dart';
import '../profile.dart';
import 'push_dispatcher.dart';

/// 资料缓存：批量拉取好友/群成员的昵称、头像（含 DIY 自定义头像与头像框），
/// 以及群详情解析。HTTP 接口与分片逻辑在此统一，落点由调用方回调决定。
///
/// 依赖经构造注入（认证、好友/群会话表、成员资料表、快照与落盘回调），
/// ChatService 仅作门面。
class ProfileCache {
  ProfileCache({
    required this._getAuth,
    required this._getMyUin,
    required this._friendSessions,
    required this._contacts,
    required this._groupMemberProfiles,
    required this._emitSessionSnapshot,
    required this._saveFriendCache,
  });

  final MiniAuth? Function() _getAuth;
  final int Function() _getMyUin;
  final Map<int, ChatSession> _friendSessions;
  final List<Contact> _contacts;
  final Map<int, Map<int, PlayerProfile>> _groupMemberProfiles;
  final void Function() _emitSessionSnapshot;
  final Future<void> Function() _saveFriendCache;

  static const String _logTag = 'ProfileCache';

  /// 批量拉取好友昵称/头像（/miniw/profile getProfileBatch3）。
  ///
  /// 头像优先级：DIY 自定义头像 → getProfileBatch3 header3/2/1 → 角色头像回退
  /// → 首字母占位。
  Future<void> fetchFriendInfos(List<Map<String, Object?>> items) async {
    final uins = items
        .map(ChatPushDispatcher.friendUin)
        .where((u) => u != 0)
        .toList();
    if (uins.isEmpty) return;
    var updated = false;
    await fetchProfiles(
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
        // 「头像本体优先于 URL」，所以有 DIY 头像时要把头像本体清空。
        final useDiy = head?.diyUrl != null;
        _friendSessions[p.uin] = ChatSession(
          id: s.id,
          type: s.type,
          name: p.nickname.isNotEmpty ? p.nickname : s.name,
          avatar: head?.diyUrl ?? p.avatarUrl ?? s.avatar,
          isOnline: s.isOnline,
          gameStatus: s.gameStatus,
          lastMessage: s.lastMessage,
          unreadCount: s.unreadCount,
          lastReadTime: s.lastReadTime,
          relation: s.relation,
          headType: useDiy ? null : (fallback?.type ?? s.headType),
          headId: useDiy ? null : (fallback?.id ?? s.headId),
          headFrameId: p.headFrameId ?? s.headFrameId,
        );
        updateContactHead(
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
      await _saveFriendCache();
    }
  }

  /// 同步联系人（好友页数据源）的头像信息（DIY url + 头像本体 + 头像框）。
  void updateContactHead(
    int uin,
    HeadSlot? head,
    int? headFrameId, {
    int? fallbackType,
    int? fallbackId,
  }) {
    if (head == null && headFrameId == null && fallbackType == null) return;
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
  /// 任何异常内部吞掉，由调用方决定是否降级。
  Future<void> fetchProfiles(
    List<int> uins, {
    required void Function(PlayerProfile p, HeadSlot? head) onProfile,
  }) async {
    final auth = _getAuth();
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

  /// 从 query_user_groups 的单条群记录解析群详情（creator / members / 静默）。
  /// 字段对齐反编译源码 friendservice.lua:6002-6068（identity==1 为群主）。
  GroupInfo groupInfoFrom(Map<String, Object?> m, int gid, String name) {
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
        if (_getMyUin() == uin && mm['ban_group'] == 1) muteAll = true;
      }
    }
    if (creator == 0) creator = ChatPushDispatcher.toNum(m['creator']);
    if (creator == 0 && members.isNotEmpty) creator = members.first;
    if (members.isNotEmpty) {
      _groupMemberProfiles[gid] = {};
      unawaited(fetchGroupMemberProfiles(gid, members));
    }
    return GroupInfo(
      groupId: gid,
      name: name,
      creatorUin: creator,
      members: members,
      isMuteAll: muteAll,
      iconId: ChatPushDispatcher.toNum(m['IconID'] ?? m['group_iconid']),
      iconType: ChatPushDispatcher.toNum(m['IconType'] ?? m['group_icontype']),
    );
  }

  /// 批量拉群成员资料（getProfileBatch3 + DIY 头像），存进 [groupMemberProfiles]。
  Future<void> fetchGroupMemberProfiles(int gid, List<int> uins) async {
    if (uins.isEmpty) return;
    await fetchProfiles(
      uins,
      onProfile: (p, head) {
        final member = _groupMemberProfiles[gid];
        if (member == null) return;
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
}
