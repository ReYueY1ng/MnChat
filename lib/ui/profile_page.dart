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
///   - 主页模块（`称号` / `勋章` / `交友宣言`）：`ChatService.userHomepage`
///     + [homepageTitleId] / [homepageMedals] / [homepageDeclaration]；
///   - 等级 / 大会员：`ChatService.platformLevel`、
///     `PartnerClient.getMyVipExpiry`；
///   - `最佳拍档`：`myPartnerListProvider` / `partnerLevelsProvider` /
///     `partnerProfilesProvider`（与最佳拍档页同源同款徽标）。
///
/// 已知缺口（外部客户端无对应协议，**只保留版块外壳与「—」占位，不臆造数据**）：
///   - `关注` / `粉丝` / `人气值` / `信用分` 计数（`get_user_fans_list` 已实现
///     但响应结构未解析，故不展示具体数值）；
///   - `魅力值` / `追光计划` / `我的收藏夹` / `迷你印迹` 计数；
///   - `发布作品` 列表；`动态` 正文与 `置顶`；`编辑布局`；页脚 `IP属地`。
library;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show Clipboard, ClipboardData;
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/models/homepage_modules.dart';
import '../core/models/skin_head_catalog.dart';
import '../core/services/name_rules.dart'
    show renameErrorText, validateNickname;
import '../core/services/partner.dart' show PartnerDirectory, PartnerInfo;
import '../core/services/profile.dart'
    show PlayerProfile, PortraitItem, ProfileClient;
import '../core/services/social_sign.dart' show SocialDeclaration;
import '../state/providers.dart';
import 'dynamics_page.dart';
import 'player_home_page.dart';
import 'social_sign_page.dart';
import 'theme/app_tokens.dart';
import 'visitor_list_page.dart';
import 'widgets/avatar_view.dart';
import 'widgets/head_frame.dart';
import 'widgets/partner_badges.dart';
import 'widgets/rich_text_view.dart';

/// 无协议数据版块的统一降级提示（见本文件「已知缺口」）。
const String kHomeUnavailableHint = '外部客户端暂未获取该项数据';

/// 统计项的降级占位（数值未知时展示，避免与真实的 0 混淆）。
const String kHomeUnknownValue = '—';

/// 个人主页：展示头像 / 昵称 / 迷你号，以及头像框、皮肤、称号、勋章、
/// 最佳拍档等版块，并提供修改昵称与交友标签入口。
class ProfilePage extends ConsumerStatefulWidget {
  const ProfilePage({super.key});

  @override
  ConsumerState<ProfilePage> createState() => _ProfilePageState();
}

class _ProfilePageState extends ConsumerState<ProfilePage> {
  /// DIY 自定义头像（优先）或批量资料头像；为空时回退首字占位。
  String? _avatarUrl;

  /// 头像框 id（`profile.head_frame_id`）。
  int? _frameId;

  /// 当前"头像本体"类型/ID（type 1=皮肤）。null 表示未取到。
  int? _headType;
  int? _headId;

  /// 已拥有的头像框 id（含默认框 1）；用于头像框选择。
  Set<int> _ownedFrames = {};

  /// 已拥有的立绘列表；为空时不展示立绘瓦片。
  List<PortraitItem> _portraits = [];

  /// 主页模块数据（`get_user_homepage`）：称号 / 勋章 / 交友宣言的来源。
  Map<String, Object?>? _home;

  /// 当前佩戴称号名（`titleName`）；null = 未佩戴或查询失败。
  String? _titleName;

  /// 交友宣言（`social_sign` 模块）；null = 未设置。
  SocialDeclaration? _declaration;

  /// 平台等级（`get_level_info_batch`）；0 = 未知。
  int _level = 0;

  /// 是否大会员（`vip_get_data` 到期时间晚于当前时间）。
  bool _isVip = false;

  @override
  void initState() {
    super.initState();
    _loadProfile();
    _loadHomeModules();
  }

  /// 拉取当前账号的头像、头像框与头像本体（皮肤 / 立绘）。
  /// 各接口独立 try/catch：任一失败只回退占位，不影响页面展示。
  Future<void> _loadProfile() async {
    final auth = ref.read(authProvider).auth;
    if (auth == null) return;
    final client = ProfileClient(uin: auth.uin, s2: auth.s2, s2t: auth.s2t);

    String? avatarUrl;
    int? frameId;

    try {
      // DIY 自定义头像优先（游戏主界面同源）
      final diy = await client.getPersonCenterHeadInfo([auth.uin]);
      avatarUrl = diy[auth.uin];
    } catch (_) {
      // 忽略：DIY 头像拉取失败时回退到批量资料头像
    }

    Set<int> ownedFrames = {};
    try {
      final profile = await client.getMyProfile();
      if (profile != null) {
        avatarUrl ??= profile.avatarUrl;
        frameId = profile.headFrameId;
        ownedFrames = {...profile.ownedHeadFrameIds};
      }
    } catch (e) {
      // 忽略：资料拉取失败时展示首字占位头像
      debugPrint('ProfilePage: getMyProfile 失败: $e');
    }

    // 兜底：单个资料接口有时不下发 head_frames（表现：选择器只剩默认框 1）。
    // 再用批量资料接口取一次并集，并打印数量便于定位问题。
    if (ownedFrames.length <= 1) {
      try {
        final list = await client.getProfileBatch3([auth.uin]);
        if (list.isNotEmpty) {
          frameId ??= list.first.headFrameId;
          ownedFrames.addAll(list.first.ownedHeadFrameIds);
        }
      } catch (e) {
        debugPrint('ProfilePage: getProfileBatch3 补头像框失败: $e');
      }
    }
    debugPrint('ProfilePage: 已拥有头像框 ${ownedFrames.length} 个');

    int? headType;
    int? headId;
    try {
      final head = await client.getMyHeadInfo();
      if (head != null) {
        headType = head.type;
        headId = head.id;
      }
    } catch (_) {
      // 忽略：头像本体拉取失败时仅展示昵称首字占位
    }

    List<PortraitItem> portraits = [];
    try {
      portraits = await client.getOwnedPortraits();
    } catch (_) {
      // 忽略：立绘拉取失败不展示立绘瓦片
    }

    if (!mounted) return;
    setState(() {
      _avatarUrl = avatarUrl;
      _frameId = frameId;
      _headType = headType;
      _headId = headId;
      _portraits = portraits;
      // 默认框 1 始终可用（对齐 func_has_opened_head_frames）
      _ownedFrames = {1, ...ownedFrames};
    });
  }

  /// 拉取主页模块（称号 / 勋章 / 交友宣言）与等级 / 大会员。
  /// 两组接口各自独立降级，互不影响；失败只打印诊断。
  Future<void> _loadHomeModules() async {
    final auth = ref.read(authProvider).auth;
    if (auth == null) return;

    Map<String, Object?>? home;
    String? titleName;
    var level = 0;
    try {
      final svc = ref.read(chatServiceProvider);
      home = await svc.userHomepage(auth.uin);
      level = await svc.platformLevel(auth.uin);
      final titleId = homepageTitleId(home);
      titleName = titleId > 0 ? await svc.titleName(titleId) : null;
    } catch (e) {
      debugPrint('ProfilePage: 主页模块拉取失败: $e');
    }

    var isVip = false;
    try {
      final expiry = await ref.read(partnerClientProvider)?.getMyVipExpiry();
      final now = DateTime.now().millisecondsSinceEpoch ~/ 1000;
      isVip = expiry != null && expiry > now;
    } catch (e) {
      debugPrint('ProfilePage: 大会员状态拉取失败: $e');
    }

    if (!mounted) return;
    setState(() {
      _home = home;
      _titleName = titleName;
      _declaration = homepageDeclaration(home);
      _level = level;
      _isVip = isVip;
    });
  }

  /// 已拥有且有本地图标的皮肤（skinId → 图标 headId），按图标 id 排序。
  Map<int, int> get _ownedSkins {
    final owned = ref.watch(authProvider).auth?.ownedSkinIds ?? const <int>{};
    final list = <int, int>{};
    for (final id in owned) {
      final head = kSkinHeadIcon[id];
      if (head != null) list[id] = head;
    }
    return list;
  }

  /// 无协议支持的操作（参考图存在但外部客户端无对应接口）：提示暂不支持。
  void _notSupported(String feature) {
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text('外部客户端暂不支持$feature')));
  }

  /// 复制迷你号到剪贴板。
  Future<void> _copyUin(int uin) async {
    await Clipboard.setData(ClipboardData(text: '$uin'));
    if (!mounted) return;
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(const SnackBar(content: Text('迷你号已复制')));
  }

  /// 打开交友标签页，返回后刷新交友宣言（横幅 / 版块同步更新）。
  Future<void> _openSocialSign() async {
    await Navigator.of(
      context,
    ).push(MaterialPageRoute<void>(builder: (_) => const SocialSignPage()));
    if (!mounted) return;
    await _loadHomeModules();
  }

  /// 打开家园（个人主页）：外部客户端无 3D 家园，降级为本人玩家主页。
  void _openHomeland(int uin) {
    Navigator.of(context).push(
      MaterialPageRoute<void>(builder: (_) => PlayerHomePage(targetUin: uin)),
    );
  }

  /// 打开访客记录（`get_visitor_list`）。
  void _openVisitors(int uin) {
    Navigator.of(context).push(
      MaterialPageRoute<void>(builder: (_) => VisitorListPage(ownerUin: uin)),
    );
  }

  /// 修改昵称：输入 → 本地校验 → 二次确认 → 调用服务。
  Future<void> _editNickname() async {
    final auth = ref.read(authProvider).auth;
    if (auth == null) return;

    final controller = TextEditingController(text: auth.name);
    final input = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('修改昵称'),
        content: TextField(
          controller: controller,
          autofocus: true,
          maxLength: 21, // 对齐 nickModifyCtrl 上限
          decoration: const InputDecoration(hintText: '请输入新昵称'),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, controller.text),
            child: const Text('确定'),
          ),
        ],
      ),
    );
    controller.dispose();
    if (input == null || !mounted) return;

    final error = validateNickname(input, current: auth.name);
    if (error != null) {
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(error)));
      return;
    }

    // 二次确认：改名消耗道具且进入审核，避免误触
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('确认修改昵称'),
        content: const Text('改名会消耗迷你币/改名卡，且昵称将进入审核，请谨慎操作。'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('确认修改'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;

    try {
      final code = await ref.read(chatServiceProvider).renameSelf(input.trim());
      if (!mounted) return;
      final message = code == 0 ? '改名成功' : renameErrorText(code);
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(message)));
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text('改名失败：$e')));
    }
  }

  /// 使用指定头像框：二次确认后调用 setProfile。
  Future<void> _applyFrame(int id) async {
    if (id == _frameId) return;
    final auth = ref.read(authProvider).auth;
    if (auth == null) return;

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('使用该头像框'),
        content: Text('确定使用头像框 #$id 吗？'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('使用'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;

    try {
      final client = ProfileClient(uin: auth.uin, s2: auth.s2, s2t: auth.s2t);
      final ok = await client.setHeadFrame(id);
      if (!mounted) return;
      if (ok) {
        setState(() => _frameId = id);
        ScaffoldMessenger.of(context)
            .showSnackBar(const SnackBar(content: Text('头像框已更新')));
      } else {
        ScaffoldMessenger.of(context)
            .showSnackBar(const SnackBar(content: Text('设置失败，请稍后重试')));
      }
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text('设置失败：$e')));
    }
  }

  /// 使用指定皮肤作为头像本体（type=1）：二次确认后调用 setHeadInfo。
  Future<void> _applyHeadSkin(int skinId) async {
    if (_headType == 1 && _headId == skinId) return;
    final auth = ref.read(authProvider).auth;
    if (auth == null) return;

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('使用该头像'),
        content: const Text('确定使用该皮肤作为头像吗？'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('使用'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;

    try {
      final client = ProfileClient(uin: auth.uin, s2: auth.s2, s2t: auth.s2t);
      final ok = await client.setHeadInfo(type: 1, id: skinId);
      if (!mounted) return;
      if (ok) {
        setState(() {
          _headType = 1;
          _headId = skinId;
        });
        ScaffoldMessenger.of(context)
            .showSnackBar(const SnackBar(content: Text('头像已更新')));
      } else {
        ScaffoldMessenger.of(context)
            .showSnackBar(const SnackBar(content: Text('设置失败，请稍后重试')));
      }
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text('设置失败：$e')));
    }
  }

  /// 使用指定立绘作为头像本体（type=4）：二次确认后调用 setHeadInfo。
  Future<void> _applyPortrait(PortraitItem p) async {
    if (_headType == 4 && _headId == p.id) return;
    final auth = ref.read(authProvider).auth;
    if (auth == null) return;

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('使用该立绘'),
        content: const Text('确定使用该立绘作为头像吗？'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('使用'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;

    try {
      final client = ProfileClient(uin: auth.uin, s2: auth.s2, s2t: auth.s2t);
      final ok = await client.setHeadInfo(type: 4, id: p.id, endTime: p.time);
      if (!mounted) return;
      if (ok) {
        setState(() {
          _headType = 4;
          _headId = p.id;
        });
        ScaffoldMessenger.of(context)
            .showSnackBar(const SnackBar(content: Text('头像已更新')));
      } else {
        ScaffoldMessenger.of(context)
            .showSnackBar(const SnackBar(content: Text('设置失败，请稍后重试')));
      }
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text('设置失败：$e')));
    }
  }

  /// 头像框选择瓦片（当前选中的高亮描边）。
  Widget _frameTile(ThemeData theme, int id) {
    final selected = id == _frameId;
    // 关闭「头像框动画」时预览也用静态图，避免为省流却仍在解码动图。
    final animated =
        headFrameIsAnimated(id) && ref.watch(animatedFramesProvider);
    return InkWell(
      onTap: () => _applyFrame(id),
      borderRadius: AppRadius.inputR,
      child: Container(
        width: 64,
        height: 64,
        decoration: BoxDecoration(
          borderRadius: AppRadius.inputR,
          border: Border.all(
            color: selected
                ? theme.colorScheme.primary
                : theme.colorScheme.outlineVariant,
            width: selected ? 2 : 1,
          ),
        ),
        child: Center(
          child: Image.asset(
            animated ? headFrameAsset(id) : headFrameStaticAsset(id),
            width: 56,
            height: 56,
            fit: BoxFit.contain,
            errorBuilder: (_, _, _) => Icon(
              Icons.image_not_supported_outlined,
              size: 20,
              color: theme.colorScheme.outline,
            ),
          ),
        ),
      ),
    );
  }

  /// 皮肤头像选择瓦片（当前选中的高亮描边）。
  Widget _skinTile(ThemeData theme, int skinId, int headId) {
    final selected = _headType == 1 && _headId == skinId;
    return _SelectableTile(
      selected: selected,
      onTap: () => _applyHeadSkin(skinId),
      child: Image.asset(
        roleIconAsset(headId),
        width: 56,
        height: 56,
        fit: BoxFit.contain,
        errorBuilder: (_, _, _) => Icon(
          Icons.image_not_supported_outlined,
          size: 20,
          color: theme.colorScheme.outline,
        ),
      ),
    );
  }

  /// 立绘头像选择瓦片（当前选中的高亮描边）。
  Widget _portraitTile(ThemeData theme, PortraitItem p) {
    final selected = _headType == 4 && _headId == p.id;
    return _SelectableTile(
      selected: selected,
      onTap: () => _applyPortrait(p),
      child: Image.asset(
        roleIconAsset(p.id),
        width: 56,
        height: 56,
        fit: BoxFit.contain,
        errorBuilder: (_, _, _) => Icon(
          Icons.image_not_supported_outlined,
          size: 20,
          color: theme.colorScheme.outline,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final auth = ref.watch(authProvider).auth;
    final uin = auth?.uin ?? 0;
    final skins = _ownedSkins;
    final partners =
        ref.watch(myPartnerListProvider).asData?.value ??
        const <PartnerInfo>[];
    final levels =
        ref.watch(partnerLevelsProvider).asData?.value ?? const <int, int>{};
    final profiles =
        ref.watch(partnerProfilesProvider).asData?.value ??
        const <int, PlayerProfile>{};
    final directory =
        ref.watch(partnerDirectoryProvider).asData?.value ??
        PartnerDirectory.empty;
    final declaration = _declaration?.text ?? '';
    final medalCount = homepageMedals(_home).length;
    final decorCount = skins.length + _portraits.length;

    return Scaffold(
      appBar: AppBar(
        title: const Text('个人主页'),
        actions: [
          IconButton(
            tooltip: '刷新',
            icon: const Icon(Icons.refresh),
            onPressed: () {
              _loadProfile();
              _loadHomeModules();
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
                name: auth?.name ?? '',
                uin: uin,
                avatarUrl: _avatarUrl,
                headType: _headType,
                headId: _headId,
                frameId: _frameId,
                level: _level,
                isVip: _isVip,
                onCopyUin: () => _copyUin(uin),
                onVisitors: () => _openVisitors(uin),
                onEditLayout: () => _notSupported('编辑主页布局'),
                onRename: _editNickname,
                onHomeland: () => _openHomeland(uin),
              ),
              const SizedBox(height: AppSpacing.md),
              // 2. 横幅：交友宣言 + 编辑
              _HomeBannerCard(
                name: auth?.name ?? '',
                declaration: declaration,
                onEdit: _openSocialSign,
              ),
              const SizedBox(height: AppSpacing.md),
              // 3. 个性装扮（皮肤 / 立绘，点选即换头像本体）
              _HomeSectionCard(
                title: '个性装扮',
                count: '$decorCount',
                child: decorCount == 0
                    ? const _UnavailableNote('暂未获取到已拥有的皮肤或立绘')
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
              // 4. 头像框（已拥有，点选即更换）
              _HomeSectionCard(
                title: '头像框',
                count: '${_ownedFrames.length}',
                child: _ownedFrames.isEmpty
                    ? const _UnavailableNote(kHomeUnavailableHint)
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
                first: const _CompactModuleCard(
                  title: '魅力值',
                  count: kHomeUnknownValue,
                  caption: kHomeUnavailableHint,
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
                first: const _HomeSectionCard(
                  title: '发布作品',
                  count: kHomeUnknownValue,
                  child: _UnavailableNote(kHomeUnavailableHint),
                ),
                second: _HomeSectionCard(
                  title: '动态',
                  action: TextButton.icon(
                    onPressed: () => _notSupported('置顶动态'),
                    icon: const Icon(Icons.push_pin_outlined, size: 16),
                    label: const Text('置顶'),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const _UnavailableNote('外部客户端暂不展示动态正文'),
                      const SizedBox(height: AppSpacing.sm),
                      OutlinedButton.icon(
                        onPressed: () => Navigator.of(context).push(
                          MaterialPageRoute<void>(
                            builder: (_) => const DynamicsPage(),
                          ),
                        ),
                        icon: const Icon(Icons.public, size: 16),
                        label: const Text('前往动态页'),
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
                  const _CompactModuleCard(
                    title: '追光计划',
                    count: kHomeUnknownValue,
                    caption: kHomeUnavailableHint,
                  ),
                  _CompactModuleCard(
                    title: '勋章',
                    count: medalCount > 0 ? '$medalCount' : kHomeUnknownValue,
                    caption: medalCount > 0 ? '已获得勋章' : kHomeUnavailableHint,
                  ),
                  const _CompactModuleCard(
                    title: '我的收藏夹',
                    count: kHomeUnknownValue,
                    caption: kHomeUnavailableHint,
                  ),
                  const _CompactModuleCard(
                    title: '迷你印迹',
                    count: kHomeUnknownValue,
                    caption: kHomeUnavailableHint,
                  ),
                ],
              ),
              const SizedBox(height: AppSpacing.md),
              // 9. 交友宣言
              _HomeSectionCard(
                title: '交友宣言',
                action: TextButton.icon(
                  onPressed: _openSocialSign,
                  icon: const Icon(Icons.edit, size: 16),
                  label: const Text('编辑'),
                ),
                child: declaration.isEmpty
                    ? const _UnavailableNote('还没有设置交友宣言')
                    : Text(declaration, style: theme.textTheme.bodyMedium),
              ),
              const SizedBox(height: AppSpacing.md),
              // 10. 页脚：IP属地 + 迷你号
              _HomeFooter(uin: uin),
            ],
          ),
        ),
      ),
    );
  }
}

/// 个人主页顶部资料卡（对齐参考图顶栏）：
/// 头像（含头像框）+ 昵称 + 等级 / 大会员徽标 + `迷你号`（可复制）
/// + `关注`·`粉丝`·`人气值`·`信用分` 统计行 + 入口按钮行。
class _ProfileHeaderCard extends StatelessWidget {
  final String name;
  final int uin;
  final String? avatarUrl;
  final int? headType;
  final int? headId;
  final int? frameId;

  /// 平台等级（0 = 未知，不展示徽标）。
  final int level;

  /// 是否大会员。
  final bool isVip;

  final VoidCallback onCopyUin;
  final VoidCallback onVisitors;
  final VoidCallback onEditLayout;
  final VoidCallback onRename;
  final VoidCallback onHomeland;

  const _ProfileHeaderCard({
    required this.name,
    required this.uin,
    required this.avatarUrl,
    required this.headType,
    required this.headId,
    required this.frameId,
    required this.level,
    required this.isVip,
    required this.onCopyUin,
    required this.onVisitors,
    required this.onEditLayout,
    required this.onRename,
    required this.onHomeland,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return _HomeSectionCard(
      title: '个人资料',
      padding: AppSpacing.cardPadding,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              // 头像本体 + 头像框统一由 AvatarView 渲染（槽位按 headFrameSlotSize
              // 放大，框不会被裁切）。
              AvatarView(
                avatarUrl: avatarUrl,
                name: name,
                radius: 36,
                headType: headType,
                headId: headId,
                frameId: frameId,
              ),
              const SizedBox(width: AppSpacing.md),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Flexible(
                          child: RichTextView(
                            name,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: theme.textTheme.titleLarge?.copyWith(
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ),
                        if (level > 0) ...[
                          const SizedBox(width: AppSpacing.xs),
                          LevelBadge(level: level),
                        ],
                        if (isVip) ...[
                          const SizedBox(width: AppSpacing.xs),
                          const VipBadge(),
                        ],
                      ],
                    ),
                    const SizedBox(height: AppSpacing.xs),
                    Row(
                      children: [
                        Flexible(
                          child: Text(
                            '迷你号 $uin',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: theme.textTheme.bodySmall?.copyWith(
                              color: theme.colorScheme.outline,
                            ),
                          ),
                        ),
                        IconButton(
                          tooltip: '复制迷你号',
                          iconSize: 16,
                          visualDensity: VisualDensity.compact,
                          icon: const Icon(Icons.copy_outlined),
                          onPressed: onCopyUin,
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.md),
          const Divider(height: 1),
          const SizedBox(height: AppSpacing.md),
          // 统计行：4 项计数 + 分隔线（计数均无协议来源 → 「—」占位）。
          SizedBox(
            height: 44,
            child: Row(
              children: [
                const Expanded(
                  child: _HomeStatTile(
                    label: '关注',
                    value: kHomeUnknownValue,
                    hint: kHomeUnavailableHint,
                  ),
                ),
                const _StatDivider(),
                const Expanded(
                  child: _HomeStatTile(
                    label: '粉丝',
                    value: kHomeUnknownValue,
                    hint: kHomeUnavailableHint,
                  ),
                ),
                const _StatDivider(),
                const Expanded(
                  child: _HomeStatTile(
                    label: '人气值',
                    value: kHomeUnknownValue,
                    hint: kHomeUnavailableHint,
                  ),
                ),
                const _StatDivider(),
                const Expanded(
                  child: _HomeStatTile(
                    label: '信用分',
                    value: kHomeUnknownValue,
                    hint: kHomeUnavailableHint,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: AppSpacing.md),
          Wrap(
            spacing: AppSpacing.sm,
            runSpacing: AppSpacing.sm,
            children: [
              OutlinedButton.icon(
                onPressed: onVisitors,
                icon: const Icon(Icons.visibility_outlined, size: 16),
                label: const Text('最近访客'),
              ),
              FilledButton.icon(
                // 参考图存在「编辑布局」；外部客户端无主页布局协议 → 仅外壳。
                onPressed: onEditLayout,
                icon: const Icon(Icons.dashboard_customize_outlined, size: 16),
                label: const Text('编辑布局'),
              ),
              OutlinedButton.icon(
                onPressed: onRename,
                icon: const Icon(Icons.drive_file_rename_outline, size: 16),
                label: const Text('修改昵称'),
              ),
              OutlinedButton.icon(
                onPressed: onHomeland,
                icon: const Icon(Icons.home_outlined, size: 16),
                label: const Text('家园'),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

/// 个人主页横幅（对齐参考图中央大卡）：交友宣言气泡 + `编辑` + 昵称名牌。
///
/// 参考图的 3D 角色 / 场景底图无 2D 资源可用，这里以主题渐变近似，
/// 不引入新配色。
class _HomeBannerCard extends StatelessWidget {
  final String name;

  /// 已格式化的交友宣言；空串表示未设置。
  final String declaration;
  final VoidCallback onEdit;

  const _HomeBannerCard({
    required this.name,
    required this.declaration,
    required this.onEdit,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    return Card(
      margin: EdgeInsets.zero,
      clipBehavior: Clip.antiAlias,
      child: Container(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [scheme.primaryContainer, scheme.tertiaryContainer],
          ),
        ),
        padding: AppSpacing.cardPadding,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(
                  Icons.format_quote,
                  size: 20,
                  color: scheme.onPrimaryContainer,
                ),
                const SizedBox(width: AppSpacing.sm),
                Text(
                  '交友宣言',
                  style: theme.textTheme.labelLarge?.copyWith(
                    color: scheme.onPrimaryContainer,
                  ),
                ),
                const Spacer(),
                TextButton.icon(
                  onPressed: onEdit,
                  icon: const Icon(Icons.edit, size: 16),
                  label: const Text('编辑'),
                ),
              ],
            ),
            const SizedBox(height: AppSpacing.sm),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(
                horizontal: AppSpacing.md,
                vertical: AppSpacing.sm,
              ),
              decoration: BoxDecoration(
                color: scheme.surfaceContainerLowest,
                borderRadius: AppRadius.inputR,
              ),
              child: Text(
                declaration.isEmpty ? '还没有设置交友宣言' : declaration,
                style: theme.textTheme.titleMedium?.copyWith(
                  color: scheme.onSurface,
                ),
              ),
            ),
            const SizedBox(height: AppSpacing.md),
            Align(alignment: Alignment.centerRight, child: _NameTag(name)),
          ],
        ),
      ),
    );
  }
}

/// 昵称名牌（参考图角色脚下的蓝色渐变名牌）：主题色胶囊 + 前景色文字。
class _NameTag extends StatelessWidget {
  final String name;

  const _NameTag(this.name);

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.md,
        vertical: AppSpacing.xs,
      ),
      decoration: BoxDecoration(
        color: scheme.primary,
        borderRadius: AppRadius.pillR,
      ),
      child: Text(
        name.isEmpty ? '未命名' : name,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: theme.textTheme.labelMedium?.copyWith(
          color: scheme.onPrimary,
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }
}

/// 称号胶囊（参考图紫 / 橙红渐变称号）：浅色容器底 + 图标 + 称号名。
class _TitlePill extends StatelessWidget {
  final String title;

  const _TitlePill(this.title);

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.sm,
        vertical: 2,
      ),
      decoration: BoxDecoration(
        color: scheme.tertiaryContainer,
        borderRadius: AppRadius.chipR,
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            Icons.local_police_outlined,
            size: 14,
            color: scheme.onTertiaryContainer,
          ),
          const SizedBox(width: AppSpacing.xs),
          Text(
            title,
            style: theme.textTheme.labelMedium?.copyWith(
              color: scheme.onTertiaryContainer,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }
}

/// 个人主页版块卡：标题 +（可选）计数 + 右上角操作 + 内容。
///
/// 圆角 / 描边完全沿用 [ThemeData.cardTheme]（不自定义卡片样式）。
class _HomeSectionCard extends StatelessWidget {
  final String title;

  /// 右上角计数（null 不展示）。
  final String? count;

  /// 右上角操作（如 `置顶` / `编辑`）。
  final Widget? action;

  final Widget child;
  final EdgeInsetsGeometry padding;

  const _HomeSectionCard({
    required this.title,
    this.count,
    this.action,
    required this.child,
    this.padding = const EdgeInsets.fromLTRB(
      AppSpacing.lg,
      AppSpacing.md,
      AppSpacing.lg,
      AppSpacing.lg,
    ),
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Card(
      margin: EdgeInsets.zero,
      clipBehavior: Clip.antiAlias,
      child: Padding(
        padding: padding,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Flexible(
                  child: Text(
                    title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.titleSmall,
                  ),
                ),
                if (count != null) ...[
                  const SizedBox(width: AppSpacing.sm),
                  Text(
                    count!,
                    style: theme.textTheme.labelMedium?.copyWith(
                      fontWeight: FontWeight.w700,
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                ],
                const Spacer(),
                ?action,
              ],
            ),
            const SizedBox(height: AppSpacing.md),
            child,
          ],
        ),
      ),
    );
  }
}

/// 紧凑版块卡（参考图 `追光计划` / `勋章` 等小卡）：标题 + 计数 + 说明。
class _CompactModuleCard extends StatelessWidget {
  final String title;
  final String count;
  final String caption;

  const _CompactModuleCard({
    required this.title,
    required this.count,
    required this.caption,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Card(
      margin: EdgeInsets.zero,
      clipBehavior: Clip.antiAlias,
      child: Padding(
        padding: AppSpacing.cardPadding,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Flexible(
                  child: Text(
                    title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.titleSmall,
                  ),
                ),
                const Spacer(),
                Text(
                  count,
                  style: theme.textTheme.labelMedium?.copyWith(
                    fontWeight: FontWeight.w700,
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
              ],
            ),
            const SizedBox(height: AppSpacing.xs),
            Text(
              caption,
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.outline,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// 统计项：数值在上、标签在下；[hint] 非空时挂 Tooltip 说明数据来源缺口。
class _HomeStatTile extends StatelessWidget {
  final String label;
  final String value;
  final String? hint;

  const _HomeStatTile({required this.label, required this.value, this.hint});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final tile = Column(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        Text(
          value,
          style: theme.textTheme.titleMedium?.copyWith(
            fontWeight: FontWeight.w700,
          ),
        ),
        const SizedBox(height: 2),
        Text(
          label,
          style: theme.textTheme.bodySmall?.copyWith(
            color: theme.colorScheme.outline,
          ),
        ),
      ],
    );
    final h = hint;
    return h == null ? tile : Tooltip(message: h, child: tile);
  }
}

/// 统计行内的竖直分隔线。
class _StatDivider extends StatelessWidget {
  const _StatDivider();

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 28,
      child: VerticalDivider(width: 1, color: Theme.of(context).dividerColor),
    );
  }
}

/// 无协议数据版块的降级说明：一行浅色文字（绝不臆造数据）。
class _UnavailableNote extends StatelessWidget {
  final String text;

  const _UnavailableNote(this.text);

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Text(
      text,
      style: theme.textTheme.bodySmall?.copyWith(
        color: theme.colorScheme.outline,
      ),
    );
  }
}

/// 参考图中并排的两个版块：宽度足够时并排，窄屏降级为上下堆叠。
class _ResponsivePair extends StatelessWidget {
  final Widget first;
  final Widget second;

  const _ResponsivePair({required this.first, required this.second});

  /// 并排所需的最小宽度；低于该值则堆叠（避免卡片内文字被挤成竖排）。
  static const double _sideBySideMinWidth = 520;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        if (constraints.maxWidth < _sideBySideMinWidth) {
          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              first,
              const SizedBox(height: AppSpacing.md),
              second,
            ],
          );
        }
        return Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(child: first),
            const SizedBox(width: AppSpacing.md),
            Expanded(child: second),
          ],
        );
      },
    );
  }
}

/// 紧凑版块网格（参考图右列 2×2 小卡）：宽屏两列、窄屏单列。
class _CompactModuleGrid extends StatelessWidget {
  final List<Widget> children;

  const _CompactModuleGrid({required this.children});

  /// 两列所需的最小宽度；低于该值单列堆叠。
  static const double _twoColumnMinWidth = 520;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final twoCol = constraints.maxWidth >= _twoColumnMinWidth;
        final width = twoCol
            ? (constraints.maxWidth - AppSpacing.md) / 2
            : constraints.maxWidth;
        return Wrap(
          spacing: AppSpacing.md,
          runSpacing: AppSpacing.md,
          children: [
            for (final child in children)
              SizedBox(width: width, child: child),
          ],
        );
      },
    );
  }
}

/// 可点选瓦片（皮肤 / 立绘共用）：选中时主题色描边。
class _SelectableTile extends StatelessWidget {
  final bool selected;
  final VoidCallback onTap;
  final Widget child;

  const _SelectableTile({
    required this.selected,
    required this.onTap,
    required this.child,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return InkWell(
      onTap: onTap,
      borderRadius: AppRadius.inputR,
      child: Container(
        width: 64,
        height: 64,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          borderRadius: AppRadius.inputR,
          border: Border.all(
            color: selected
                ? theme.colorScheme.primary
                : theme.colorScheme.outlineVariant,
            width: selected ? 2 : 1,
          ),
        ),
        child: child,
      ),
    );
  }
}

/// 页脚：`IP属地` + 迷你号（对齐参考图底边）。
class _HomeFooter extends StatelessWidget {
  final int uin;

  const _HomeFooter({required this.uin});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final style = theme.textTheme.bodySmall?.copyWith(
      color: theme.colorScheme.outline,
    );
    return Row(
      children: [
        Icon(Icons.public, size: 14, color: theme.colorScheme.outline),
        const SizedBox(width: AppSpacing.xs),
        // IP 属地无协议来源（仅动态正文带该字段），此处只保留版块与占位。
        Tooltip(
          message: kHomeUnavailableHint,
          child: Text('IP属地：$kHomeUnknownValue', style: style),
        ),
        const Spacer(),
        Text('$uin', style: style),
      ],
    );
  }
}

/// 个人主页「最佳拍档」版块的单条拍档：头像（含头像框）+ 昵称 +
/// 等级 / 默契度 / 大会员徽标（与最佳拍档页同源控件）。
class HomePartnerTile extends StatelessWidget {
  final PartnerInfo partner;

  /// 拍档资料（昵称 / 头像 / 头像框）；为空时退回迷你号 + 首字头像。
  final PlayerProfile? profile;

  /// 拍档平台等级（0 = 未知，不展示 `Lv` 徽标）。
  final int level;

  /// 拍档是否大会员。
  final bool isVip;

  final VoidCallback? onTap;

  const HomePartnerTile({
    super.key,
    required this.partner,
    this.profile,
    this.level = 0,
    this.isVip = false,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final p = profile;
    final name = (p != null && p.nickname.isNotEmpty)
        ? p.nickname
        : '${partner.bestUin}';
    // 无人物中心头信息时用资料的 SkinID / Model 回退角色头像（与好友列表同源）。
    final fallback = p == null
        ? null
        : PlayerProfile.resolveRoleHeadFallback(
            skinId: p.headSkinId,
            model: p.headModel,
          );
    return InkWell(
      onTap: onTap,
      borderRadius: AppRadius.cardR,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: AppSpacing.sm),
        child: Row(
          children: [
            AvatarView(
              avatarUrl: p?.avatarUrl,
              name: name,
              radius: 24,
              headType: fallback?.type,
              headId: fallback?.id,
              frameId: p?.headFrameId,
            ),
            const SizedBox(width: AppSpacing.md),
            Expanded(
              child: Row(
                children: [
                  Flexible(
                    child: RichTextView(
                      name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.bodyMedium,
                    ),
                  ),
                  if (level > 0 || isVip) ...[
                    const SizedBox(width: AppSpacing.xs),
                    PartnerNameBadges(
                      level: level,
                      partner: partner,
                      isVip: isVip,
                    ),
                  ],
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
