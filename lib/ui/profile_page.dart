/// 个人主页 —— 版块顺序与文案对齐游戏内「个人主页」（个人中心）参考图。
///
/// 版面（自上而下）：
///   1. 资料头卡：头像（含头像框）/ 昵称 / 等级与大会员徽标 / `迷你号`（可复制）
///      / `关注`·`粉丝`·`人气值`·`信用分` 统计行 / `最近访客`·`编辑布局`·
///      `修改昵称`·`家园` 入口；
///   2. 横幅：`交友宣言` 气泡 + `编辑`（→ 交友标签页）；
///   3. `个性装扮`：已拥有皮肤与立绘，点选即更换头像本体；
///   4. `头像框`：已拥有头像框，点选即更换（含默认框 1）；
///   5. `魅力值` / `称号`（窄屏堆叠，宽屏并排）；
///   6. `发布作品` / `动态`（同上并排）；
///   7. `最佳拍档`：头像 / 昵称 / 等级 / 默契度 / 大会员徽标；
///   8. `追光计划` / `勋章` / `我的收藏夹` / `迷你印迹`（2×2 紧凑网格）；
///   9. `交友宣言`：正文全文；
///  10. 页脚：`IP属地` + 迷你号。
///
/// 数据来源：
///   - 头像 / 头像框 / 皮肤 / 立绘：`ProfileClient`（`getProfile`、
///     `getPersonCenterHeadInfo`、`getProfileBatch3`、`query_portrait`）；
///   - 主页模块（`role_info` 统计 / `魅力值` / `发布作品` / `动态` / `追光计划` /
///     `个性装扮` / `称号` / `勋章` / `交友宣言`）：`ChatService.userHomepage`
///     （完整 `module_list`）+ `core/models/homepage_modules.dart` 纯解析器；
///   - 等级 / 大会员：`ChatService.platformLevel`、
///     `PartnerClient.getMyVipExpiry`；
///   - `最佳拍档`：`myPartnerListProvider` / `partnerLevelsProvider` /
///     `partnerProfilesProvider`（与最佳拍档页同源同款徽标）；
///   - `我的收藏夹` / `迷你印迹` 计数：独立接口 `miniw/favorite?act=get_collect_ids`
///     （`contentfavsservice.lua:205-209`）与 `miniw/camera?act=get_photo_homepage`
///     （`multimediaalbumservice.lua:255-261`），经 `PlayerHomeClient` 取数。
///
/// 已接入的独立协议 / 端点（逐条 file:line 出处见 `.omo/docs/protocol-notes.md`）：
///   - `置顶动态`：`set_top_flag`（module_id = posting 3）
///     （`playercenterv2homepageservice.lua:309-325`）；
///   - `编辑布局`：`get_homepage_layout` / `change_homepage_layout`
///     （同文件 `:26-66`）；
///   - 页脚 `IP属地`：`miniw/user_ext?act=get_user_addr`
///     （`playercenteripadressctrl.lua:77-105`）；空值回退 `GetS(4896)`=「未知」。
///
/// 已知缺口（外部客户端无对应协议，**只保留版块外壳与「—」占位，不臆造数据**）：
///   - `动态` 正文（本卡只展示条数，正文请在动态页查看）。
library;

import 'dart:async' show unawaited;

import 'package:material_ui/material_ui.dart';
import 'package:flutter/services.dart' show Clipboard, ClipboardData;
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/models/homepage_modules.dart';
import '../core/models/nickname.dart' show plainNickname;
import '../core/models/skin_head_catalog.dart';
import '../core/services/name_rules.dart'
    show renameErrorText, validateNickname;
import '../core/services/partner.dart' show PartnerDirectory, PartnerInfo;
import '../core/services/player_home.dart'
    show PlayerHomeClient, PlayerHomeModule, SetTopFlagResult;
import '../core/services/profile.dart'
    show PlayerProfile, PortraitItem, ProfileClient;
import '../core/services/social_sign.dart'
    show DeclarationCatalog, SocialDeclaration;
import '../core/utils/log.dart';
import '../state/providers.dart';
import 'player_home_page.dart';
import 'social_sign_page.dart';
import 'theme/app_tokens.dart';
import 'visitor_list_page.dart';
import 'widgets/avatar_edit_dialog.dart';
import 'widgets/dynamics_overlay.dart';
import 'widgets/avatar_view.dart';
import 'widgets/head_frame.dart';
import 'widgets/home_layout_dialog.dart';
import 'widgets/partner_badges.dart';
import 'widgets/rich_text_view.dart';

part 'profile_page_state_base.dart';
part 'profile_page_state_actions.dart';
part 'profile_page_widgets.dart';
part 'profile_page_widgets_compact.dart';

/// 本模块日志标签。
const String _logTag = 'ProfilePage';

/// 无协议数据版块的统一降级提示（见本文件「已知缺口」）。
const String kHomeUnavailableHint = '外部客户端暂未获取该项数据';

/// 统计项的降级占位（数值未知时展示，避免与真实的 0 混淆）。
const String kHomeUnknownValue = '—';

/// 统计值展示：有值 → 数字字符串；缺失（null）→ 「—」占位。
String _statText(int? v) => v == null ? kHomeUnknownValue : '$v';

/// 个人主页：展示头像 / 昵称 / 迷你号，以及头像框、皮肤、称号、勋章、
/// 最佳拍档等版块。
///
/// [targetUin] 为空 = 我自己的主页（多出编辑入口：头像、昵称、布局、装扮）；
/// 非空 = 看别人的主页 —— **同一套卡片**，只是把编辑相关的入口收起来，
/// 并额外提供关注 / 拉黑。
class ProfilePage extends ConsumerStatefulWidget {
  final int? targetUin;

  const ProfilePage({super.key, this.targetUin});

  @override
  ConsumerState<ProfilePage> createState() => _ProfilePageState();
}

class _ProfilePageState extends ConsumerState<ProfilePage>
    with _ProfilePageStateBase, _ProfilePageStateActions {
  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final auth = ref.watch(authProvider).auth;
    // 主页主人：他人主页时是对方（以前这里写死 auth.uin，他人主页会显示我的迷你号）
    final uin = widget.targetUin ?? auth?.uin ?? 0;
    final name = _displayName;
    // 已拥有的装扮只在看自己时才有（别人看不到"我拥有什么"）
    final skins = _isSelf ? _ownedSkins : const <int, int>{};
    final partners = _isSelf
        ? (ref.watch(myPartnerListProvider).asData?.value ??
              const <PartnerInfo>[])
        : const <PartnerInfo>[];
    final levels =
        ref.watch(partnerLevelsProvider).asData?.value ?? const <int, int>{};
    final profiles =
        ref.watch(partnerProfilesProvider).asData?.value ??
        const <int, PlayerProfile>{};
    final directory =
        ref.watch(partnerDirectoryProvider).asData?.value ??
        PartnerDirectory.empty;
    // 标签文案以服务端配置为准（拉不到才回退内置表）。
    final catalog =
        ref.watch(declarationCatalogProvider).asData?.value ??
        DeclarationCatalog.empty;
    final declaration = _declaration?.textWith(catalog) ?? '';
    // 主页模块（`get_user_homepage`）解析结果；缺失时为 null，UI 降级为「—」。
    final stats = homepageStats(_home);
    final charm = homepageCharmValue(_home);
    final workCount = homepageWorkCount(_home);
    final works = homepageWorks(_home);
    final postingCount = homepagePostingCount(_home);
    final chaseLightCount = homepageChaseLightCount(_home);
    final skinModuleCount = homepageSkinCount(_home);
    final medals = homepageMedals(_home);
    final medalCount = medals.isNotEmpty
        ? medals.length
        : homepageMedals2(_home).length;
    final decorCount = skins.length + _portraits.length;

    return Scaffold(
      appBar: AppBar(
        title: Text(_isSelf ? '个人主页' : _plainName),
        actions: [
          if (_isSelf)
            IconButton(
              tooltip: '头像编辑',
              icon: const Icon(Icons.badge_outlined),
              onPressed: _openAvatarEdit,
            ),
          IconButton(
            tooltip: '刷新',
            icon: const Icon(Icons.refresh),
            onPressed: () {
              _loadProfile();
              _loadHomeModules();
              _loadExtraCounts();
            },
          ),
        ],
      ),
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: AppSizes.narrowContent),
          child: ListView(
            padding: const EdgeInsets.all(AppSpacing.lg),
            children: [
              // 1. 资料头卡
              _ProfileHeaderCard(
                name: name,
                uin: uin,
                avatarUrl: _avatarUrl,
                headType: _headType,
                headId: _headId,
                frameId: _frameId,
                level: _level,
                isVip: _isVip,
                stats: stats,
                familyName: _familyName,
                onCopyUin: () => _copyUin(uin),
                onHomeland: _isSelf ? () => _openHomeland(uin) : null,
                onVisitors: _isSelf ? () => _openVisitors(uin) : null,
                onEditLayout: _isSelf ? _openLayoutEditor : null,
                onRename: _isSelf ? _editNickname : null,
                onEditAvatar: _isSelf ? _openAvatarEdit : null,
              ),
              if (!_isSelf) ...[
                const SizedBox(height: AppSpacing.md),
                _RelationActions(
                  following: _following,
                  blacklisted: _blacklisted,
                  busy: _relationBusy,
                  onFollow: _toggleFollow,
                  onBlacklist: _toggleBlacklist,
                ),
              ],
              const SizedBox(height: AppSpacing.md),
              // 2. 横幅：交友宣言 + 编辑
              _HomeBannerCard(
                name: name,
                declaration: declaration,
                onEdit: _isSelf ? _openSocialSign : null,
              ),
              const SizedBox(height: AppSpacing.md),
              // 3. 个性装扮（皮肤 / 立绘，点选即换头像本体）
              _HomeSectionCard(
                title: '个性装扮',
                count: '${decorCount > 0 ? decorCount : (skinModuleCount ?? 0)}',
                child: decorCount == 0
                    ? _UnavailableNote(
                        (skinModuleCount ?? 0) > 0
                            ? '已拥有 $skinModuleCount 件装扮（本地暂无对应图标）'
                            : '暂未获取到已拥有的皮肤或立绘',
                      )
                    : Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Wrap(
                            spacing: AppSpacing.sm,
                            runSpacing: AppSpacing.sm,
                            children: [
                              for (final e in skins.entries)
                                _skinTile(theme, e.key, e.value),
                            ],
                          ),
                          if (_portraits.isNotEmpty) ...[
                            const SizedBox(height: AppSpacing.md),
                            Text('立绘', style: theme.textTheme.labelMedium),
                            const SizedBox(height: AppSpacing.sm),
                            Wrap(
                              spacing: AppSpacing.sm,
                              runSpacing: AppSpacing.sm,
                              children: [
                                for (final p in _portraits)
                                  _portraitTile(theme, p),
                              ],
                            ),
                          ],
                        ],
                      ),
              ),
              const SizedBox(height: AppSpacing.md),
              // 4. 头像框（看自己时可点选更换；看别人时只报数量）
              _HomeSectionCard(
                title: '头像框',
                count: '${_ownedFrames.isNotEmpty ? _ownedFrames.length : (homepageHeadFrameCount(_home) ?? 0)}',
                child: _ownedFrames.isEmpty
                    ? _UnavailableNote(
                        (homepageHeadFrameCount(_home) ?? 0) > 0
                            ? '已拥有 ${homepageHeadFrameCount(_home)} 个头像框'
                            : kHomeUnavailableHint,
                      )
                    : Wrap(
                        spacing: AppSpacing.sm,
                        runSpacing: AppSpacing.sm,
                        children: [
                          for (final id in (_ownedFrames.toList()..sort()))
                            _frameTile(theme, id),
                        ],
                      ),
              ),
              const SizedBox(height: AppSpacing.md),
              // 5. 魅力值 / 称号
              _ResponsivePair(
                first: _CompactModuleCard(
                  title: '魅力值',
                  count: charm == null ? kHomeUnknownValue : '$charm',
                  caption: charm == null ? kHomeUnavailableHint : '累计收到礼物魅力值',
                ),
                second: _HomeSectionCard(
                  title: '称号',
                  count: _titleName == null ? kHomeUnknownValue : null,
                  child: _titleName == null
                      ? const _UnavailableNote('未佩戴称号')
                      : Wrap(
                          spacing: AppSpacing.sm,
                          runSpacing: AppSpacing.sm,
                          children: [_TitlePill(_titleName!)],
                        ),
                ),
              ),
              const SizedBox(height: AppSpacing.md),
              // 6. 发布作品 / 动态
              _ResponsivePair(
                first: _HomeSectionCard(
                  title: '发布作品',
                  count: workCount == null ? kHomeUnknownValue : '$workCount',
                  child: workCount == null
                      ? const _UnavailableNote(kHomeUnavailableHint)
                      : works.isEmpty
                      ? const _UnavailableNote('暂无已发布地图作品')
                      : Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            for (final w in works.take(4))
                              Padding(
                                padding: const EdgeInsets.only(
                                  bottom: AppSpacing.xs,
                                ),
                                child: Row(
                                  children: [
                                    Icon(
                                      Icons.map_outlined,
                                      size: 14,
                                      color: theme.colorScheme.outline,
                                    ),
                                    const SizedBox(width: AppSpacing.xs),
                                    Expanded(
                                      child: Text(
                                        w.name,
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis,
                                        style: theme.textTheme.bodySmall,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            if (works.length > 4)
                              Text(
                                '等 ${works.length} 张地图',
                                style: theme.textTheme.bodySmall?.copyWith(
                                  color: theme.colorScheme.outline,
                                ),
                              ),
                          ],
                        ),
                ),
                second: _HomeSectionCard(
                  title: '动态',
                  count: postingCount == null
                      ? kHomeUnknownValue
                      : '$postingCount',
                  // 置顶动态：官方对**单条**动态调用 `set_top_flag`
                  // （module_id = posting 3；`playercenterv2homepageservice.lua:309-325`，
                  // `op_type` 1=置顶 / 0=取消）。本卡不展示动态列表，故对服务端
                  // 下发的「已置顶（top_pid）/ 最新（last_pid）」那条操作；
                  // 两者皆无（无动态）时不显示按钮。
                  action: (!_isSelf || (_pinnedPid == 0 && _latestPid == 0))
                      ? null
                      : TextButton.icon(
                          onPressed: _postingTopBusy ? null : _togglePostingTop,
                          icon: const Icon(Icons.push_pin_outlined, size: 16),
                          label: Text(_pinnedPid > 0 ? '取消置顶' : '置顶'),
                        ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      _UnavailableNote(
                        postingCount == null
                            ? '外部客户端暂不展示动态正文'
                            : '已发布 $postingCount 条动态',
                      ),
                      const SizedBox(height: AppSpacing.sm),
                      OutlinedButton.icon(
                        onPressed: () => showAuthorDynamics(
                          context,
                          authorUin: uin,
                          authorName: name,
                        ),
                        icon: const Icon(Icons.public, size: 16),
                        label: const Text('查看我的动态'),
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: AppSpacing.md),
              // 7. 最佳拍档（与最佳拍档页同源同款徽标）
              _HomeSectionCard(
                title: '最佳拍档',
                count: '${partners.length}',
                child: partners.isEmpty
                    ? const _UnavailableNote('暂无最佳拍档')
                    : Column(
                        children: [
                          for (final p in partners)
                            HomePartnerTile(
                              partner: p,
                              profile: profiles[p.bestUin],
                              level: levels[p.bestUin] ?? 0,
                              isVip: directory.isVip(p.bestUin),
                              onTap: () => _openHomeland(p.bestUin),
                            ),
                        ],
                      ),
              ),
              const SizedBox(height: AppSpacing.md),
              // 8. 追光计划 / 勋章 / 我的收藏夹 / 迷你印迹（参考图 2×2 小卡）
              _CompactModuleGrid(
                children: [
                  _CompactModuleCard(
                    title: '追光计划',
                    count: chaseLightCount == null
                        ? kHomeUnknownValue
                        : '$chaseLightCount',
                    caption: chaseLightCount == null
                        ? kHomeUnavailableHint
                        : '已收集装扮',
                  ),
                  _CompactModuleCard(
                    title: '勋章',
                    count: medalCount > 0 ? '$medalCount' : kHomeUnknownValue,
                    caption: medalCount > 0 ? '已获得勋章' : kHomeUnavailableHint,
                  ),
                  // 我的收藏夹数量来自独立接口
                  // `miniw/favorite?act=get_collect_ids`
                  // （`contentfavsservice.lua:205-209`），不在
                  // get_user_homepage 模块数据内。
                  _CompactModuleCard(
                    title: '我的收藏夹',
                    count: _favoriteCount == null
                        ? kHomeUnknownValue
                        : '$_favoriteCount',
                    caption: _favoriteCount == null
                        ? kHomeUnavailableHint
                        : '已创建收藏夹',
                  ),
                  // 迷你印迹数量来自独立接口 MultimediaAlbum
                  // `miniw/camera?act=get_photo_homepage`
                  // （`multimediaalbumservice.lua:255-261`），不在
                  // get_user_homepage 模块数据内。
                  _CompactModuleCard(
                    title: '迷你印迹',
                    count: _multimediaCount == null
                        ? kHomeUnknownValue
                        : '$_multimediaCount',
                    caption: _multimediaCount == null
                        ? kHomeUnavailableHint
                        : '主页展示的照片',
                  ),
                ],
              ),
              const SizedBox(height: AppSpacing.md),
              // 10. 页脚：IP属地 + 迷你号
              _HomeFooter(uin: uin, ipAddr: _ipAddr),
            ],
          ),
        ),
      ),
    );
  }
}
