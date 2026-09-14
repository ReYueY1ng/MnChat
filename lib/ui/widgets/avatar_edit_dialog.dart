/// 头像编辑弹窗 —— 标题 `头像编辑`，左侧竖排 5 个页签：
/// `头像` / `头像框` / `昵称` / `称号` / `家族`（选中态为白色圆角胶囊），
/// 右上角白色圆形 ✕ 关闭。版式与文案逐字对齐游戏内参考图。
///
/// 各页签数据来源（全部复用既有服务，不重复实现）：
///   - `头像`：已拥有皮肤（`auth.ownedSkinIds` + [kSkinHeadIcon]）与已拥有
///     立绘（`ProfileClient.getOwnedPortraits`）；点选即调用
///     `setPersonCenterHeadInfo`（type 1/4）更换头像本体，与个人主页一致；
///     `坐骑` 分类没有「已拥有坐骑」协议 → 空态降级；
///   - `头像框`：`profile.ownedHeadFrameIds`（含默认框 1），点选即调用
///     `setProfile&head_frame_id=`；`置顶` 无协议 → 仅提示；框名称 /
///     获取途径需服务端配置，暂未获取（右栏只展示原始 id）；
///   - `昵称`：`ChatService.renameSelf` + `name_rules` 校验。`消耗 x1`
///     逐字对齐参考图，实际扣除由服务端裁决（见 `name_rules.dart`）；
///   - `称号`：只能取到当前佩戴称号（`get_user_homepage` 的 title 模块）；
///     完整称号列表 / 有效期无对应协议 → 空态降级；
///   - `家族`：`FamilyClient.getFamilyList` + [parseFamilyList] 列出已加入
///     家族；切换展示家族名无协议 → 仅提示。
///
/// 已知缺口（均为外部客户端无协议可实现，代码内以 TODO 标注）：
///   1. 自定义头像（DIY）上传链路；
///   2. 头像框 `置顶` 排序；
///   3. 展示家族名切换；
///   4. 称号完整列表与有效期。
library;

import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show LengthLimitingTextInputFormatter;
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/models/skin_head_catalog.dart'
    show kSkinHeadIcon, roleIconAsset;
import '../../core/services/family.dart'
    show FamilyClient, FamilyInfo, parseFamilyList;
import '../../core/services/name_rules.dart'
    show kNicknameMaxLen, renameErrorText, validateNickname;
import '../../core/services/profile.dart' show PortraitItem, ProfileClient;
import '../../state/providers.dart' show authProvider, chatServiceProvider;
import '../theme/app_tokens.dart';
import 'avatar_view.dart';
import 'head_frame.dart' show HeadFrameOverlay, headFrameSlotSize;
import 'rich_text_view.dart';

/// 左侧页签栏的测试定位 Key。
const Key avatarEditNavKey = Key('avatarEditNav');

/// 昵称输入框的测试定位 Key。
const Key avatarEditNicknameFieldKey = Key('avatarEditNicknameField');

/// 「头像」页签顶部来源分类（`全部`/`装扮`/`坐骑`/`个性`）的测试定位 Key。
const Key avatarEditSourceTabsKey = Key('avatarEditSourceTabs');

/// 「称号」页签顶部分类的测试定位 Key。
const Key avatarEditTitleTabsKey = Key('avatarEditTitleTabs');

/// 头像格子 Key（本地图标按 type/id 定位）。
Key avatarEditHeadCellKey(int type, int id) =>
    ValueKey<String>('avatarEditHead-$type-$id');

/// 头像框格子 Key。
Key avatarEditFrameCellKey(int id) => ValueKey<String>('avatarEditFrame-$id');

/// 家族卡片 Key。
Key avatarEditFamilyCellKey(int familyId) =>
    ValueKey<String>('avatarEditFamily-$familyId');

/// 「称号」页签的顶部分类（逐字对齐参考图；数据源见文件头「已知缺口」）。
const List<String> kTitleCategoryTabs = ['全部', '开发者', '迷你季', '其他', '自定义'];

/// 头像编辑弹窗的左侧页签。
enum AvatarEditTab {
  avatar('头像'),
  frame('头像框'),
  nickname('昵称'),
  title('称号'),
  family('家族');

  const AvatarEditTab(this.label);

  /// 页签文案（逐字对齐参考图）。
  final String label;
}

/// 「头像」页签的顶部来源分类。
enum AvatarSourceTab {
  all('全部'),
  skin('装扮'),
  ride('坐骑'),
  portrait('个性');

  const AvatarSourceTab(this.label);

  /// 分类文案（逐字对齐参考图）。
  final String label;
}

/// 家族列表加载器（测试注入用；为空时走 [FamilyClient.getFamilyList]）。
typedef FamilyListLoader = Future<List<FamilyInfo>> Function();

/// 打开弹窗时的资料快照 —— 由个人主页传入，弹窗不重复拉取。
class AvatarEditInitialData {
  /// 当前账号迷你号（头像 / 昵称降级展示用）。
  final int uin;

  /// 当前昵称。
  final String name;

  /// DIY 或资料头像 URL。
  final String? avatarUrl;

  /// 头像本体 type/id（1=皮肤 3=坐骑 4=立绘）。
  final int? headType;
  final int? headId;

  /// 当前头像框 id。
  final int? frameId;

  /// 已拥有的头像框 id（调用方已并入默认框 1）。
  final Set<int> ownedFrames;

  /// 已拥有的立绘。
  final List<PortraitItem> portraits;

  /// 当前佩戴称号名（null = 未佩戴或未取到）。
  final String? titleName;

  const AvatarEditInitialData({
    required this.uin,
    required this.name,
    this.avatarUrl,
    this.headType,
    this.headId,
    this.frameId,
    this.ownedFrames = const {},
    this.portraits = const [],
    this.titleName,
  });
}

/// 打开「头像编辑」弹窗；返回是否发生过实际修改（头像 / 头像框 / 昵称）。
Future<bool> showAvatarEditDialog(
  BuildContext context, {
  required AvatarEditInitialData initial,
  FamilyListLoader? familyLoader,
}) async {
  final changed = await showDialog<bool>(
    context: context,
    builder: (_) =>
        AvatarEditDialog(initial: initial, familyLoader: familyLoader),
  );
  return changed == true;
}

/// 头像编辑弹窗。
class AvatarEditDialog extends ConsumerStatefulWidget {
  /// 打开弹窗时的资料快照。
  final AvatarEditInitialData initial;

  /// 家族列表加载器（测试注入；为空时走 [FamilyClient]）。
  final FamilyListLoader? familyLoader;

  const AvatarEditDialog({
    super.key,
    required this.initial,
    this.familyLoader,
  });

  @override
  ConsumerState<AvatarEditDialog> createState() => _AvatarEditDialogState();
}

class _AvatarEditDialogState extends ConsumerState<AvatarEditDialog> {
  /// 当前页签。
  AvatarEditTab _tab = AvatarEditTab.avatar;

  /// 「头像」页签的来源分类。
  AvatarSourceTab _source = AvatarSourceTab.all;

  /// 「称号」页签的分类下标。
  int _titleTab = 0;

  /// 弹窗内的头像本体（点选后即时更新，与个人主页同源语义）。
  late int? _headType = widget.initial.headType;
  late int? _headId = widget.initial.headId;

  /// 弹窗内的头像框（点选后即时更新）。
  late int? _frameId = widget.initial.frameId;

  /// 当前昵称（改名成功后本地更新）。
  late String _name = widget.initial.name;

  /// 昵称输入框；输入即重算 `确认修改` 的可用态。
  late final TextEditingController _nicknameController =
      TextEditingController();

  /// 昵称提交中（防连点）。
  bool _nicknameBusy = false;

  /// 是否发生过实际修改（关闭时回传，供个人主页刷新）。
  bool _changed = false;

  /// 家族列表是否已请求过（懒加载，仅在切到 `家族` 页签时触发）。
  bool _familyLoaded = false;
  bool _familyLoading = false;
  List<FamilyInfo> _families = const [];

  /// 家族列表加载失败文案；null = 无错误。
  String? _familyError;

  /// 当前展示的家族（首个；切换展示无协议 → 见 `_onFamilyTap`）。
  int? _selectedFamilyId;

  @override
  void initState() {
    super.initState();
    // 已拥有的头像框（并入默认框 1，对齐 func_has_opened_head_frames）。
    _ownedFrames = {1, ...widget.initial.ownedFrames}.toList()..sort();
    _nicknameController.addListener(_onNicknameChanged);
  }

  @override
  void dispose() {
    _nicknameController.removeListener(_onNicknameChanged);
    _nicknameController.dispose();
    super.dispose();
  }

  /// 已排序的已拥有头像框 id（含默认框 1）。
  late final List<int> _ownedFrames;

  void _onNicknameChanged() {
    if (mounted) setState(() {});
  }

  /// 已拥有且有本地图标的皮肤（skinId → 图标 headId），与个人主页同源。
  Map<int, int> get _skins {
    final owned = ref.watch(authProvider).auth?.ownedSkinIds ?? const <int>{};
    final out = <int, int>{};
    for (final id in owned) {
      final head = kSkinHeadIcon[id];
      if (head != null) out[id] = head;
    }
    return out;
  }

  void _toast(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(message)));
  }

  void _switchTab(AvatarEditTab tab) {
    setState(() => _tab = tab);
    if (tab == AvatarEditTab.family && !_familyLoaded) {
      _familyLoaded = true;
      _loadFamilies();
    }
  }

  /// 懒加载家族列表：测试可注入 [FamilyListLoader]，否则走 [FamilyClient]。
  Future<void> _loadFamilies() async {
    setState(() {
      _familyLoading = true;
      _familyError = null;
    });
    try {
      final loader = widget.familyLoader;
      final list = loader != null
          ? await loader()
          : await _loadFamiliesFromServer();
      if (!mounted) return;
      setState(() {
        _families = list;
        _familyLoading = false;
        _selectedFamilyId = list.isEmpty ? null : list.first.familyId;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _familyLoading = false;
        _familyError = '家族列表加载失败';
      });
    }
  }

  Future<List<FamilyInfo>> _loadFamiliesFromServer() async {
    final auth = ref.read(authProvider).auth;
    if (auth == null) return const [];
    final client = FamilyClient(uin: auth.uin, s2: auth.s2, s2t: auth.s2t);
    return parseFamilyList(await client.getFamilyList());
  }

  // ── 修改动作 ──────────────────────────────────────────────────────────

  /// 更换头像本体（type=1 皮肤）：设置后即时更新选中态。
  Future<void> _applyHeadSkin(int skinId) async {
    if (_headType == 1 && _headId == skinId) return;
    final auth = ref.read(authProvider).auth;
    if (auth == null) return;
    try {
      final client = ProfileClient(uin: auth.uin, s2: auth.s2, s2t: auth.s2t);
      final ok = await client.setHeadInfo(type: 1, id: skinId);
      if (!mounted) return;
      if (ok) {
        setState(() {
          _headType = 1;
          _headId = skinId;
          _changed = true;
        });
        _toast('头像已更新');
      } else {
        _toast('设置失败，请稍后重试');
      }
    } catch (e) {
      if (!mounted) return;
      _toast('设置失败：$e');
    }
  }

  /// 更换头像本体（type=4 立绘）：`time` 随请求带给服务端。
  Future<void> _applyPortrait(PortraitItem portrait) async {
    if (_headType == 4 && _headId == portrait.id) return;
    final auth = ref.read(authProvider).auth;
    if (auth == null) return;
    try {
      final client = ProfileClient(uin: auth.uin, s2: auth.s2, s2t: auth.s2t);
      final ok = await client.setHeadInfo(
        type: 4,
        id: portrait.id,
        endTime: portrait.time,
      );
      if (!mounted) return;
      if (ok) {
        setState(() {
          _headType = 4;
          _headId = portrait.id;
          _changed = true;
        });
        _toast('头像已更新');
      } else {
        _toast('设置失败，请稍后重试');
      }
    } catch (e) {
      if (!mounted) return;
      _toast('设置失败：$e');
    }
  }

  /// 更换头像框：点选即调用 `setProfile&head_frame_id=`。
  Future<void> _applyFrame(int id) async {
    if (id == _frameId) return;
    final auth = ref.read(authProvider).auth;
    if (auth == null) return;
    try {
      final client = ProfileClient(uin: auth.uin, s2: auth.s2, s2t: auth.s2t);
      final ok = await client.setHeadFrame(id);
      if (!mounted) return;
      if (ok) {
        setState(() {
          _frameId = id;
          _changed = true;
        });
        _toast('头像框已更新');
      } else {
        _toast('设置失败，请稍后重试');
      }
    } catch (e) {
      if (!mounted) return;
      _toast('设置失败：$e');
    }
  }

  /// 提交改名：本地校验 → `baseinfo.rename` → 展示业务码文案。
  Future<void> _submitNickname() async {
    final name = _nicknameController.text.trim();
    final error = validateNickname(name, current: _name);
    if (error != null) {
      _toast(error);
      return;
    }
    setState(() => _nicknameBusy = true);
    try {
      final code = await ref.read(chatServiceProvider).renameSelf(name);
      if (!mounted) return;
      if (code == 0) {
        setState(() {
          _name = name;
          _changed = true;
        });
        _nicknameController.clear();
        _toast('改名成功');
      } else {
        _toast(renameErrorText(code));
      }
    } catch (e) {
      if (!mounted) return;
      _toast('改名失败：$e');
    } finally {
      if (mounted) setState(() => _nicknameBusy = false);
    }
  }

  /// 家族卡片点选：切换展示家族名无协议，只提示（见文件头「已知缺口」）。
  void _onFamilyTap(FamilyInfo family) {
    if (family.familyId == _selectedFamilyId) return;
    _toast('外部客户端暂不支持设置展示家族');
  }

  // ── 布局 ──────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final media = MediaQuery.of(context);
    final width = math.max(
      280.0,
      math.min(media.size.width - AppSpacing.xxl, 760.0),
    );
    final height = math.max(
      320.0,
      math.min(media.size.height * 0.88, 560.0),
    );
    return Dialog(
      insetPadding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.lg,
        vertical: AppSpacing.xl,
      ),
      child: SizedBox(
        width: width,
        height: height,
        child: Column(
          children: [
            _buildTitleBar(theme),
            const Divider(height: 1),
            Expanded(
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  _buildNav(theme),
                  const VerticalDivider(width: 1),
                  Expanded(
                    child: Padding(
                      padding: const EdgeInsets.all(AppSpacing.md),
                      child: _buildContent(theme),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// 顶栏：标题 `头像编辑` + 右侧白色圆形 ✕。
  Widget _buildTitleBar(ThemeData theme) {
    final scheme = theme.colorScheme;
    return Padding(
      padding: const EdgeInsets.fromLTRB(
        AppSpacing.lg,
        AppSpacing.sm,
        AppSpacing.sm,
        AppSpacing.sm,
      ),
      child: Row(
        children: [
          Text(
            '头像编辑',
            style: theme.textTheme.titleMedium?.copyWith(
              fontWeight: FontWeight.w700,
            ),
          ),
          const Spacer(),
          IconButton(
            tooltip: '关闭',
            onPressed: () => Navigator.of(context).pop(_changed),
            style: IconButton.styleFrom(
              backgroundColor: scheme.surface,
              foregroundColor: scheme.onSurface,
            ),
            icon: const Icon(Icons.close, size: 20),
          ),
        ],
      ),
    );
  }

  /// 左侧竖排页签：选中项为白色圆角胶囊。
  Widget _buildNav(ThemeData theme) {
    final scheme = theme.colorScheme;
    return Padding(
      padding: const EdgeInsets.all(AppSpacing.md),
      child: Container(
        width: 84,
        decoration: BoxDecoration(
          color: scheme.surfaceContainerHigh,
          borderRadius: AppRadius.cardR,
        ),
        padding: const EdgeInsets.all(AppSpacing.xs),
        child: SingleChildScrollView(
          key: avatarEditNavKey,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              for (final tab in AvatarEditTab.values)
                _NavItem(
                  label: tab.label,
                  active: tab == _tab,
                  onTap: () => _switchTab(tab),
                ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildContent(ThemeData theme) {
    switch (_tab) {
      case AvatarEditTab.avatar:
        return _buildAvatarTab(theme);
      case AvatarEditTab.frame:
        return _buildFrameTab(theme);
      case AvatarEditTab.nickname:
        return _buildNicknameTab(theme);
      case AvatarEditTab.title:
        return _buildTitleTab(theme);
      case AvatarEditTab.family:
        return _buildFamilyTab(theme);
    }
  }

  // ── 页签 1：头像 ──────────────────────────────────────────────────────

  Widget _buildAvatarTab(ThemeData theme) {
    final scheme = theme.colorScheme;
    final skins = _skins;
    final cells = <Widget>[];

    // 自定义（上传）只在 `全部` 首格出现（参考图即如此）。
    if (_source == AvatarSourceTab.all) {
      cells.add(
        _SelectableCell(
          selected: false,
          // TODO(头像编辑): 自定义头像（DIY）上传无协议链路，暂以提示降级；
          // 若后续接入 DIY 上传接口，则替换为真实上传入口。
          onTap: () => _toast('外部客户端暂不支持自定义头像上传'),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.add, size: 20, color: scheme.onSurfaceVariant),
              const SizedBox(height: AppSpacing.xs),
              Text(
                '自定义',
                style: theme.textTheme.labelSmall?.copyWith(
                  color: scheme.onSurfaceVariant,
                ),
              ),
            ],
          ),
        ),
      );
    }

    if (_source == AvatarSourceTab.all ||
        _source == AvatarSourceTab.skin) {
      for (final e in skins.entries) {
        cells.add(
          _headCell(
            theme,
            key: avatarEditHeadCellKey(1, e.key),
            selected: _headType == 1 && _headId == e.key,
            asset: roleIconAsset(e.value),
            onTap: () => _applyHeadSkin(e.key),
          ),
        );
      }
    }

    if (_source == AvatarSourceTab.all ||
        _source == AvatarSourceTab.portrait) {
      for (final p in widget.initial.portraits) {
        cells.add(
          _headCell(
            theme,
            key: avatarEditHeadCellKey(4, p.id),
            selected: _headType == 4 && _headId == p.id,
            asset: roleIconAsset(p.id),
            onTap: () => _applyPortrait(p),
          ),
        );
      }
    }

    // 坐骑：外部客户端没有「已拥有坐骑」列表协议 → 不臆造 id，空态降级。
    final empty = cells.isEmpty;
    final grid = empty
        ? _EmptyHint(
            _source == AvatarSourceTab.ride
                ? '外部客户端暂未获取坐骑头像列表'
                : '暂未获取到已拥有的皮肤或立绘',
          )
        : GridView.count(
            padding: EdgeInsets.zero,
            crossAxisCount: 4,
            mainAxisSpacing: AppSpacing.sm,
            crossAxisSpacing: AppSpacing.sm,
            children: cells,
          );

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _TopTabs(
          tabsKey: avatarEditSourceTabsKey,
          labels: [for (final s in AvatarSourceTab.values) s.label],
          index: _source.index,
          onChanged: (i) =>
              setState(() => _source = AvatarSourceTab.values[i]),
        ),
        const SizedBox(height: AppSpacing.md),
        Expanded(
          child: _buildGridWithPanel(
            theme,
            grid: grid,
            panel: (narrow) => _avatarPanel(theme, narrow: narrow),
          ),
        ),
      ],
    );
  }

  /// 头像缩略图格子（本地 [roleIconAsset] 图标 + 选中态）。
  Widget _headCell(
    ThemeData theme, {
    required Key key,
    required bool selected,
    required String asset,
    required VoidCallback onTap,
  }) {
    return _SelectableCell(
      key: key,
      selected: selected,
      onTap: onTap,
      child: SizedBox.expand(
        child: Padding(
          padding: const EdgeInsets.all(AppSpacing.sm),
          child: FittedBox(
            child: Image.asset(
              asset,
              fit: BoxFit.contain,
              errorBuilder: (_, _, _) => Icon(
                Icons.image_not_supported_outlined,
                size: 20,
                color: theme.colorScheme.outline,
              ),
            ),
          ),
        ),
      ),
    );
  }

  /// 头像右栏：预览 + 上传提示 + `会员免费` + `使用中`。
  Widget _avatarPanel(ThemeData theme, {required bool narrow}) {
    final scheme = theme.colorScheme;
    final preview = AvatarView(
      avatarUrl: widget.initial.avatarUrl,
      name: _name.isEmpty ? '${widget.initial.uin}' : _name,
      radius: narrow ? 24 : 36,
      headType: _headType,
      headId: _headId,
      frameId: _frameId,
    );
    final texts = Column(
      crossAxisAlignment: narrow
          ? CrossAxisAlignment.start
          : CrossAxisAlignment.center,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          '请勿上传包含恐怖、反动等不良元素的图片哦',
          textAlign: narrow ? TextAlign.start : TextAlign.center,
          style: theme.textTheme.bodySmall?.copyWith(color: scheme.outline),
        ),
        const SizedBox(height: AppSpacing.sm),
        Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.card_giftcard,
              size: 16,
              color: AppSemanticColors.of(context).warning,
            ),
            const SizedBox(width: AppSpacing.xs),
            const Text('会员免费'),
          ],
        ),
        const SizedBox(height: AppSpacing.sm),
        Text(
          '使用中',
          style: theme.textTheme.labelMedium?.copyWith(
            color: scheme.onSurfaceVariant,
            fontWeight: FontWeight.w600,
          ),
        ),
      ],
    );
    return Container(
      padding: AppSpacing.cardPadding,
      decoration: BoxDecoration(
        color: scheme.surfaceContainerLowest,
        borderRadius: AppRadius.cardR,
        border: Border.all(color: scheme.outlineVariant),
      ),
      child: narrow
          ? Row(
              children: [
                preview,
                const SizedBox(width: AppSpacing.md),
                Expanded(child: texts),
              ],
            )
          : Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                preview,
                const SizedBox(height: AppSpacing.md),
                texts,
              ],
            ),
    );
  }

  // ── 页签 2：头像框 ────────────────────────────────────────────────────

  Widget _buildFrameTab(ThemeData theme) {
    // 网格与右栏共用同一个选中框：点选即应用（与个人主页一致）。
    final grid = GridView.count(
      padding: EdgeInsets.zero,
      crossAxisCount: 4,
      mainAxisSpacing: AppSpacing.sm,
      crossAxisSpacing: AppSpacing.sm,
      children: [
        for (final id in _ownedFrames)
          _SelectableCell(
            key: avatarEditFrameCellKey(id),
            selected: id == _frameId,
            onTap: () => _applyFrame(id),
            child: _FramePreview(id: id),
          ),
      ],
    );
    return _buildGridWithPanel(
      theme,
      grid: grid,
      panel: (narrow) => _framePanel(theme, narrow: narrow),
    );
  }

  /// 头像框右栏：预览 + 名称说明 + `使用中` / `置顶`。
  Widget _framePanel(ThemeData theme, {required bool narrow}) {
    final scheme = theme.colorScheme;
    final semantic = AppSemanticColors.of(context);
    final id = _frameId;
    final preview = AvatarView(
      avatarUrl: widget.initial.avatarUrl,
      name: _name.isEmpty ? '${widget.initial.uin}' : _name,
      radius: narrow ? 24 : 36,
      headType: _headType,
      headId: _headId,
      frameId: id,
    );
    // 参考图格式为 `<框名>：<获取途径>`；两者均需服务端配置，暂只展示原始 id。
    // TODO(头像编辑): 接入头像框名称 / 获取途径配置后替换为 `框名：获取途径`。
    final caption = Tooltip(
      message: '头像框名称与获取途径需服务端配置，暂未获取',
      child: Text(
        id == null ? '—' : '头像框 #$id',
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: theme.textTheme.labelMedium?.copyWith(
          color: scheme.onSurfaceVariant,
        ),
      ),
    );
    final buttons = Column(
      crossAxisAlignment: narrow
          ? CrossAxisAlignment.start
          : CrossAxisAlignment.end,
      mainAxisSize: MainAxisSize.min,
      children: [
        FilledButton(onPressed: null, child: const Text('使用中')),
        const SizedBox(height: AppSpacing.sm),
        FilledButton.icon(
          style: FilledButton.styleFrom(
            backgroundColor: semantic.success,
            foregroundColor: semantic.onSuccess,
          ),
          // TODO(头像编辑): 头像框置顶排序无客户端协议，暂以提示降级。
          onPressed: () => _toast('外部客户端暂不支持置顶头像框'),
          icon: const Icon(Icons.arrow_upward, size: 16),
          label: const Text('置顶'),
        ),
      ],
    );
    return Container(
      padding: AppSpacing.cardPadding,
      decoration: BoxDecoration(
        color: scheme.surfaceContainerLowest,
        borderRadius: AppRadius.cardR,
        border: Border.all(color: scheme.outlineVariant),
      ),
      child: narrow
          ? Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                preview,
                const SizedBox(width: AppSpacing.md),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      caption,
                      const SizedBox(height: AppSpacing.md),
                      buttons,
                    ],
                  ),
                ),
              ],
            )
          : Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                preview,
                const SizedBox(height: AppSpacing.md),
                caption,
                const SizedBox(height: AppSpacing.lg),
                buttons,
              ],
            ),
    );
  }

  // ── 页签 3：昵称 ──────────────────────────────────────────────────────

  Widget _buildNicknameTab(ThemeData theme) {
    final scheme = theme.colorScheme;
    final input = _nicknameController.text;
    final valid = validateNickname(input, current: _name) == null;
    return Center(
      child: SingleChildScrollView(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 420),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              RichTextView(
                _name,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                textAlign: TextAlign.center,
                style: theme.textTheme.headlineSmall?.copyWith(
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(height: AppSpacing.xl),
              TextField(
                key: avatarEditNicknameFieldKey,
                controller: _nicknameController,
                textAlign: TextAlign.center,
                // 参考图无字数计数器：用 formatter 截断而不显示 counter。
                inputFormatters: [
                  LengthLimitingTextInputFormatter(kNicknameMaxLen),
                ],
                decoration: const InputDecoration(
                  hintText: '输入修改的名字',
                  isDense: true,
                ),
              ),
              const SizedBox(height: AppSpacing.md),
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text('消耗', style: theme.textTheme.bodyMedium),
                  const SizedBox(width: AppSpacing.xs),
                  Icon(
                    Icons.monetization_on_outlined,
                    size: 16,
                    color: AppSemanticColors.of(context).warning,
                  ),
                  const SizedBox(width: AppSpacing.xs),
                  const Text('x1'),
                ],
              ),
              const SizedBox(height: AppSpacing.md),
              FilledButton(
                onPressed: valid && !_nicknameBusy ? _submitNickname : null,
                child: const Text('确认修改'),
              ),
              const SizedBox(height: AppSpacing.sm),
              Text(
                '改名消耗与审核由服务端裁决',
                style: theme.textTheme.bodySmall?.copyWith(
                  color: scheme.outline,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  // ── 页签 4：称号 ──────────────────────────────────────────────────────

  Widget _buildTitleTab(ThemeData theme) {
    final titleName = widget.initial.titleName;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _TopTabs(
          tabsKey: avatarEditTitleTabsKey,
          labels: kTitleCategoryTabs,
          index: _titleTab,
          onChanged: (i) => setState(() => _titleTab = i),
        ),
        const SizedBox(height: AppSpacing.md),
        Expanded(
          child: ListView(
            padding: EdgeInsets.zero,
            children: [
              if (titleName != null) ...[
                GridView.count(
                  padding: EdgeInsets.zero,
                  crossAxisCount: 3,
                  mainAxisSpacing: AppSpacing.sm,
                  crossAxisSpacing: AppSpacing.sm,
                  childAspectRatio: 1.7,
                  shrinkWrap: true,
                  physics: const NeverScrollableScrollPhysics(),
                  children: [
                    Tooltip(
                      message: '称号列表与有效期需服务端接口，暂未获取',
                      child: _TitleCard(name: titleName, dateRange: '—'),
                    ),
                  ],
                ),
                const SizedBox(height: AppSpacing.md),
              ],
              // TODO(头像编辑): 称号列表 / 有效期无对应协议；当前仅能展示
              // `get_user_homepage` 的佩戴称号，其余分类为诚实空态。
              const _EmptyHint(
                '当前佩戴称号来自个人主页；完整列表与有效期外部客户端暂未获取',
                center: true,
              ),
            ],
          ),
        ),
      ],
    );
  }

  // ── 页签 5：家族 ──────────────────────────────────────────────────────

  Widget _buildFamilyTab(ThemeData theme) {
    if (_familyLoading) {
      return const Center(child: CircularProgressIndicator());
    }
    final error = _familyError;
    if (error != null) {
      return Center(child: _EmptyHint(error, center: true));
    }
    if (_families.isEmpty) {
      return const Center(child: _EmptyHint('你尚未加入任何家族', center: true));
    }
    return GridView.count(
      padding: EdgeInsets.zero,
      crossAxisCount: 3,
      mainAxisSpacing: AppSpacing.sm,
      crossAxisSpacing: AppSpacing.sm,
      childAspectRatio: 1.7,
      children: [
        for (final family in _families)
          _FamilyCard(
            key: avatarEditFamilyCellKey(family.familyId),
            family: family,
            selected: family.familyId == _selectedFamilyId,
            onTap: () => _onFamilyTap(family),
          ),
      ],
    );
  }

  /// 网格 + 右栏：宽屏并排，窄屏（< 520）上下堆叠。
  Widget _buildGridWithPanel(
    ThemeData theme, {
    required Widget grid,
    required Widget Function(bool narrow) panel,
  }) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final narrow = constraints.maxWidth < 520;
        if (narrow) {
          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Expanded(child: grid),
              const SizedBox(height: AppSpacing.sm),
              panel(true),
            ],
          );
        }
        return Row(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Expanded(child: grid),
            const SizedBox(width: AppSpacing.md),
            SizedBox(
              width: 196,
              child: SingleChildScrollView(child: panel(false)),
            ),
          ],
        );
      },
    );
  }
}

/// 左侧页签项：选中态为白色圆角胶囊。
class _NavItem extends StatelessWidget {
  final String label;
  final bool active;
  final VoidCallback onTap;

  const _NavItem({
    required this.label,
    required this.active,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    return Padding(
      key: ValueKey<String>('avatarEditNav-$label'),
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Material(
        color: active ? scheme.surface : Colors.transparent,
        borderRadius: AppRadius.pillR,
        child: InkWell(
          onTap: onTap,
          borderRadius: AppRadius.pillR,
          child: Container(
            width: double.infinity,
            alignment: Alignment.center,
            padding: const EdgeInsets.symmetric(
              horizontal: AppSpacing.sm,
              vertical: AppSpacing.sm,
            ),
            child: Text(
              label,
              style: theme.textTheme.labelLarge?.copyWith(
                color: active ? scheme.onSurface : scheme.onSurfaceVariant,
                fontWeight: active ? FontWeight.w700 : null,
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// 顶部横向页签（`全部` / `装扮` / …），选中项加粗加深。
class _TopTabs extends StatelessWidget {
  final List<String> labels;
  final int index;
  final ValueChanged<int> onChanged;
  final Key? tabsKey;

  const _TopTabs({
    required this.labels,
    required this.index,
    required this.onChanged,
    this.tabsKey,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    return SizedBox(
      height: 32,
      child: ListView.separated(
        key: tabsKey,
        scrollDirection: Axis.horizontal,
        itemCount: labels.length,
        separatorBuilder: (_, _) => const SizedBox(width: AppSpacing.xs),
        itemBuilder: (context, i) {
          final active = i == index;
          return InkWell(
            onTap: () => onChanged(i),
            borderRadius: AppRadius.chipR,
            child: Container(
              alignment: Alignment.center,
              padding: const EdgeInsets.symmetric(horizontal: AppSpacing.sm),
              child: Text(
                labels[i],
                style: theme.textTheme.labelLarge?.copyWith(
                  color: active ? scheme.onSurface : scheme.onSurfaceVariant,
                  fontWeight: active ? FontWeight.w700 : FontWeight.w400,
                ),
              ),
            ),
          );
        },
      ),
    );
  }
}

/// 可点选格子：选中态为橙金描边 + 绿色勾选角标。
class _SelectableCell extends StatelessWidget {
  final bool selected;
  final VoidCallback onTap;
  final Widget child;

  const _SelectableCell({
    super.key,
    required this.selected,
    required this.onTap,
    required this.child,
  });

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final warning = AppSemanticColors.of(context).warning;
    return InkWell(
      onTap: onTap,
      borderRadius: AppRadius.inputR,
      child: Container(
        decoration: BoxDecoration(
          color: scheme.surfaceContainerHigh,
          borderRadius: AppRadius.inputR,
          border: Border.all(
            color: selected ? warning : scheme.outlineVariant,
            width: selected ? 2 : 1,
          ),
          boxShadow: selected
              ? [BoxShadow(color: warning.withValues(alpha: 0.45), blurRadius: 8)]
              : null,
        ),
        child: Stack(
          alignment: Alignment.center,
          children: [
            child,
            if (selected)
              const Positioned(top: 2, right: 2, child: _CheckBadge()),
          ],
        ),
      ),
    );
  }
}

/// 绿色圆形勾选角标（选中格子 / 选中家族共用）。
class _CheckBadge extends StatelessWidget {
  const _CheckBadge();

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(1),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surface,
        shape: BoxShape.circle,
      ),
      child: Icon(
        Icons.check_circle,
        size: 16,
        color: AppSemanticColors.of(context).success,
      ),
    );
  }
}

/// 头像框格子的占位预览：灰色圆角底 + 框图片（尺寸按 [headFrameSlotSize]）。
class _FramePreview extends StatelessWidget {
  final int id;

  const _FramePreview({required this.id});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return LayoutBuilder(
      builder: (context, constraints) {
        final cell = math.min(constraints.maxWidth, constraints.maxHeight);
        // 半径随格子自适应；框槽位必须用 headFrameSlotSize，保证不裁切外圈。
        final radius = math.max(10.0, cell * 0.28);
        final avatarSize = radius * 2;
        return Stack(
          alignment: Alignment.center,
          children: [
            Container(
              width: avatarSize,
              height: avatarSize,
              decoration: BoxDecoration(
                color: scheme.surfaceContainerLowest,
                borderRadius: BorderRadius.circular(avatarSize * 0.25),
              ),
            ),
            HeadFrameOverlay(frameId: id, size: headFrameSlotSize(radius)),
          ],
        );
      },
    );
  }
}

/// 称号卡片：称号名 + `有效期` + 日期区间。
class _TitleCard extends StatelessWidget {
  final String name;

  /// 日期区间（`2026.07.31--永久`）；数据缺失时为 `—`。
  final String dateRange;

  const _TitleCard({required this.name, required this.dateRange});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    return Container(
      padding: const EdgeInsets.all(AppSpacing.sm),
      decoration: BoxDecoration(
        color: scheme.secondaryContainer,
        borderRadius: AppRadius.cardR,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          RichTextView(
            name,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: theme.textTheme.titleSmall?.copyWith(
              color: scheme.onSecondaryContainer,
              fontWeight: FontWeight.w700,
            ),
          ),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                '有效期',
                style: theme.textTheme.bodySmall?.copyWith(
                  color: scheme.onSecondaryContainer.withValues(alpha: 0.7),
                ),
              ),
              Text(
                dateRange,
                style: theme.textTheme.bodySmall?.copyWith(
                  color: scheme.onSecondaryContainer,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

/// 家族名牌卡片：选中态为橙色文字 + 橙色发光描边 + 绿色勾选角标。
class _FamilyCard extends StatelessWidget {
  final FamilyInfo family;
  final bool selected;
  final VoidCallback onTap;

  const _FamilyCard({
    super.key,
    required this.family,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final warning = AppSemanticColors.of(context).warning;
    return InkWell(
      onTap: onTap,
      borderRadius: AppRadius.cardR,
      child: Container(
        padding: const EdgeInsets.all(AppSpacing.sm),
        decoration: BoxDecoration(
          color: scheme.surfaceContainerHigh,
          borderRadius: AppRadius.cardR,
          border: Border.all(
            color: selected ? warning : scheme.outlineVariant,
            width: selected ? 2 : 1,
          ),
          boxShadow: selected
              ? [BoxShadow(color: warning.withValues(alpha: 0.45), blurRadius: 8)]
              : null,
        ),
        child: Stack(
          alignment: Alignment.center,
          children: [
            RichTextView(
              family.name,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              textAlign: TextAlign.center,
              style: theme.textTheme.titleSmall?.copyWith(
                color: selected ? warning : scheme.onSurface,
                fontWeight: FontWeight.w700,
              ),
            ),
            if (selected)
              const Positioned(top: 0, right: 0, child: _CheckBadge()),
          ],
        ),
      ),
    );
  }
}

/// 降级 / 空态说明（浅色文字，绝不臆造数据）。
class _EmptyHint extends StatelessWidget {
  final String text;
  final bool center;

  const _EmptyHint(this.text, {this.center = false});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Text(
      text,
      textAlign: center ? TextAlign.center : TextAlign.start,
      style: theme.textTheme.bodySmall?.copyWith(
        color: theme.colorScheme.outline,
      ),
    );
  }
}
