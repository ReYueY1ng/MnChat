/// 头像编辑弹窗 —— 标题 `头像编辑`，左侧竖排 5 个页签：
/// `头像` / `头像框` / `昵称` / `称号` / `家族`（选中态为白色圆角胶囊），
/// 右上角白色圆形 ✕ 关闭。版式与文案逐字对齐游戏内参考图。
///
/// 各页签数据来源（全部复用既有服务，不重复实现）：
///   - `头像`：已拥有皮肤（`auth.ownedSkinIds` + [kSkinHeadIcon]）与已拥有
///     立绘（`ProfileClient.getOwnedPortraits`）；`自定义` 为真实上传入口
///     （`upload_pre_photo` → 上传 → `set_usr_header3`，见 [ProfileClient]），
///     并展示当前 DIY 头像的审核态（`diy_header`：`pass_url` 可用 /
///     `pre_url` 审核中 / `aduit_fail` 审核失败），可点选启用（`use_diy=1`）；
///   - `头像框`：`profile.ownedHeadFrameIds`（含默认框 1），点选即调用
///     `setProfile&head_frame_id=`；说明文案为 `<框名>: <获取途径>`
///     （本地目录 [kHeadFrameCatalog]，由 `itemdef.csv` 生成；默认框走
///     `GetS(5300)`）；`置顶` 读 `get_top_flag_list` 真实状态并调用
///     `set_top_flag` 切换（上限由服务端裁决，原样展示其 `msg`）；
///   - `昵称`：`ChatService.renameSelf` + `name_rules` 校验。`消耗 x1`
///     逐字对齐参考图，实际扣除由服务端裁决（见 `name_rules.dart`）；
///   - `称号`：`TitleClient.getOwnedTitles`（`/miniw/title?act=get_title_showdata`）
///     取已拥有 / 已过期称号与有效期（`StartTime`/`ExpireTime`），名称与分类来自
///     远程配置 `title_manager`；分类页签按 `title.sort` 过滤；点选佩戴
///     （`wear_title`）；
///   - `家族`：`FamilyClient.getFamilyList` 列出已加入家族；当前展示家族来自
///     `get_show_family`，切换调用 `set_show_family&family_id=`。
///
/// 已知缺口（均为外部客户端无法从 Lua 反编译确定，代码内以 TODO 标注）：
///   1. DIY 上传第 2 步（`MiniHttp.CustomUpload`）的请求体线格式。
library;

import 'dart:math' as math;

import 'package:file_picker/file_picker.dart' show FilePicker, FileType;
import 'package:material_ui/material_ui.dart';
import 'package:flutter/services.dart' show LengthLimitingTextInputFormatter;
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/models/head_frame_catalog.dart' show headFrameCaption;
import '../../core/models/skin_head_catalog.dart'
    show kSkinHeadIcon, roleIconAsset;
import '../../core/services/family.dart'
    show
        FamilyClient,
        FamilyInfo,
        FamilyShowInfo,
        parseFamilyList,
        parseShowFamily;
import '../../core/services/name_rules.dart'
    show kNicknameMaxLen, renameErrorText, validateNickname;
import '../../core/services/player_home.dart'
    show PlayerHomeClient, PlayerHomeModule, SetTopFlagResult;
import '../../core/services/profile.dart'
    show DiyAuditState, DiyHeadInfo, PortraitItem, ProfileClient;
import '../../core/services/title_config.dart'
    show
        OwnedTitle,
        TitleCatalog,
        TitleClient,
        TitleConfigClient,
        TitleShowData;
import '../../state/providers.dart' show authProvider, chatServiceProvider;
import '../theme/app_tokens.dart';
import 'avatar_view.dart';
import 'head_frame.dart' show HeadFrameOverlay, headFrameSlotSize;
import 'rich_text_view.dart';
import '../../core/services/image_disk_cache.dart';

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

/// 「自定义」上传入口 Key。
const Key avatarEditDiyUploadKey = Key('avatarEditDiyUpload');

/// 当前 DIY 自定义头像格子 Key。
const Key avatarEditDiyCellKey = Key('avatarEditDiyCell');

/// 称号卡片 Key（按称号 id）。
Key avatarEditTitleCellKey(int titleId) =>
    ValueKey<String>('avatarEditTitle-$titleId');

/// 「称号」页签的顶部分类（逐字对齐参考图）。
///
/// 有远程配置时用 `title_manager.title_typeList`（名称/排序均来自配置，
/// 顺序恰为 开发者/迷你季/其他/自定义）；配置不可用时回退此常量。
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

/// 当前展示家族加载器（测试注入用；为空时走 [FamilyClient.getShowFamily]）。
typedef FamilyShowLoader = Future<FamilyShowInfo?> Function();

/// 切换展示家族（测试注入用；为空时走 [FamilyClient.setShowFamily]）。
typedef FamilySwitcher = Future<bool> Function(int familyId);

/// DIY 自定义头像状态加载器（测试注入用；为空时走 [ProfileClient]）。
typedef DiyHeadLoader = Future<DiyHeadInfo?> Function();

/// DIY 头像「选图 + 上传」动作（测试注入用；为空时走真实 FilePicker + 上传）。
typedef DiyAvatarUploader = Future<bool> Function();

/// 已拥有称号加载器（测试注入用；为空时走 [TitleClient.getOwnedTitles]）。
typedef TitleLoader = Future<TitleShowData> Function();

/// 称号配置目录加载器（测试注入用；为空时走 [TitleConfigClient.catalog]）。
typedef TitleCatalogLoader = Future<TitleCatalog> Function();

/// 佩戴称号动作（测试注入用；为空时走 [TitleClient.wearTitle]）。
typedef TitleWearer = Future<bool> Function(int titleId);

/// 已置顶头像框加载器（测试注入用；为空时走
/// [PlayerHomeClient.getTopFlagList]）。
typedef FrameTopLoader = Future<Set<int>> Function();

/// 置顶 / 取消置顶动作（测试注入用；为空时走 [PlayerHomeClient.setTopFlag]）。
typedef FrameTopToggler = Future<SetTopFlagResult> Function(
  int frameId,
  bool pin,
);

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

  /// 当前 DIY 自定义头像状态（可选；为空时弹窗自行拉取）。
  final DiyHeadInfo? diyHead;

  /// 当前展示家族 id（可选；为空时弹窗自行拉取）。
  final int? showFamilyId;

  /// 已置顶的头像框 id（可选；为空且无注入 loader 时弹窗自行拉取）。
  final Set<int>? pinnedFrames;

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
    this.diyHead,
    this.showFamilyId,
    this.pinnedFrames,
  });
}

/// 打开「头像编辑」弹窗；返回是否发生过实际修改（头像 / 头像框 / 昵称）。
Future<bool> showAvatarEditDialog(
  BuildContext context, {
  required AvatarEditInitialData initial,
  FamilyListLoader? familyLoader,
  FamilyShowLoader? showFamilyLoader,
  FamilySwitcher? familySwitcher,
  DiyHeadLoader? diyLoader,
  DiyAvatarUploader? diyUploader,
  TitleLoader? titleLoader,
  TitleCatalogLoader? titleCatalogLoader,
  TitleWearer? titleWearer,
  FrameTopLoader? frameTopLoader,
  FrameTopToggler? frameTopToggler,
}) async {
  final changed = await showDialog<bool>(
    context: context,
    builder: (_) => AvatarEditDialog(
      initial: initial,
      familyLoader: familyLoader,
      showFamilyLoader: showFamilyLoader,
      familySwitcher: familySwitcher,
      diyLoader: diyLoader,
      diyUploader: diyUploader,
      titleLoader: titleLoader,
      titleCatalogLoader: titleCatalogLoader,
      titleWearer: titleWearer,
      frameTopLoader: frameTopLoader,
      frameTopToggler: frameTopToggler,
    ),
  );
  return changed == true;
}

/// 头像编辑弹窗。
class AvatarEditDialog extends ConsumerStatefulWidget {
  /// 打开弹窗时的资料快照。
  final AvatarEditInitialData initial;

  /// 家族列表加载器（测试注入；为空时走 [FamilyClient]）。
  final FamilyListLoader? familyLoader;

  /// 当前展示家族加载器（测试注入；为空时走 [FamilyClient]）。
  final FamilyShowLoader? showFamilyLoader;

  /// 切换展示家族（测试注入；为空时走 [FamilyClient]）。
  final FamilySwitcher? familySwitcher;

  /// DIY 头像状态加载器（测试注入；为空时走 [ProfileClient]）。
  final DiyHeadLoader? diyLoader;

  /// DIY 头像「选图 + 上传」动作（测试注入；为空时走真实 FilePicker + 上传）。
  final DiyAvatarUploader? diyUploader;

  /// 已拥有称号加载器（测试注入；为空时走 [TitleClient]）。
  final TitleLoader? titleLoader;

  /// 称号配置目录加载器（测试注入；为空时走 [TitleConfigClient]）。
  final TitleCatalogLoader? titleCatalogLoader;

  /// 佩戴称号动作（测试注入；为空时走 [TitleClient]）。
  final TitleWearer? titleWearer;

  /// 已置顶头像框加载器（测试注入；为空时走 [PlayerHomeClient]）。
  final FrameTopLoader? frameTopLoader;

  /// 置顶 / 取消置顶动作（测试注入；为空时走 [PlayerHomeClient]）。
  final FrameTopToggler? frameTopToggler;

  const AvatarEditDialog({
    super.key,
    required this.initial,
    this.familyLoader,
    this.showFamilyLoader,
    this.familySwitcher,
    this.diyLoader,
    this.diyUploader,
    this.titleLoader,
    this.titleCatalogLoader,
    this.titleWearer,
    this.frameTopLoader,
    this.frameTopToggler,
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

  // ── DIY 自定义头像 ────────────────────────────────────────────────────
  /// 当前 DIY 头像状态（`diy_header` + `use_diy`）；null = 未取到 / 无 DIY。
  DiyHeadInfo? _diyHead;

  /// DIY 状态是否加载中。
  bool _diyLoading = false;

  /// DIY 上传进行中（防连点）。
  bool _diyUploading = false;

  /// 当前是否正在使用 DIY 头像（点选 DIY / 皮肤 / 立绘后更新）。
  late bool _useDiy = widget.initial.diyHead?.useDiy ?? false;

  // ── 称号 ──────────────────────────────────────────────────────────────
  /// 称号是否已请求过（懒加载，仅在切到 `称号` 页签时触发）。
  bool _titlesLoaded = false;
  bool _titlesLoading = false;

  /// 已拥有 / 已过期称号（`get_title_showdata`）。
  List<OwnedTitle> _titles = const [];

  /// 称号配置目录（名称 + 分类）。
  TitleCatalog _titleCatalog = TitleCatalog.empty;

  /// 当前佩戴称号 ID（来自 `use_title`）。
  int? _wornTitleId;

  /// 称号加载失败文案；null = 无错误。
  String? _titlesError;

  // ── 家族 ──────────────────────────────────────────────────────────────
  /// 家族列表是否已请求过（懒加载，仅在切到 `家族` 页签时触发）。
  bool _familyLoaded = false;
  bool _familyLoading = false;
  List<FamilyInfo> _families = const [];

  /// 家族列表加载失败文案；null = 无错误。
  String? _familyError;

  /// 当前展示家族 id（`get_show_family`）。
  int? _showFamilyId;

  /// 当前选中的家族卡片 id。
  int? _selectedFamilyId;

  // ── 头像框置顶 ────────────────────────────────────────────────────────
  /// 已置顶的头像框 id（`get_top_flag_list`）。
  Set<int> _topFrameIds = const {};

  /// 置顶列表是否已请求过（懒加载，仅在切到 `头像框` 页签时触发）。
  bool _topLoaded = false;
  bool _topLoading = false;

  /// 置顶请求进行中（防连点）。
  bool _topBusy = false;

  @override
  void initState() {
    super.initState();
    // 已拥有的头像框（并入默认框 1，对齐 func_has_opened_head_frames）。
    _ownedFrames = {1, ...widget.initial.ownedFrames}.toList()..sort();
    _nicknameController.addListener(_onNicknameChanged);
    _showFamilyId = widget.initial.showFamilyId;
    _topFrameIds = widget.initial.pinnedFrames ?? const {};
    _loadDiy();
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
    if (tab == AvatarEditTab.title && !_titlesLoaded) {
      _titlesLoaded = true;
      _loadTitles();
    }
    if (tab == AvatarEditTab.frame && !_topLoaded) {
      _topLoaded = true;
      _loadFrameTop();
    }
  }

  /// 懒加载家族列表 + 当前展示家族：测试可注入 loader，否则走 [FamilyClient]。
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
      // 当前展示家族：注入优先，其次快照，最后走服务端。
      if (widget.showFamilyLoader != null) {
        _showFamilyId = (await widget.showFamilyLoader!())?.familyId;
      } else if (_showFamilyId == null) {
        _showFamilyId = (await _loadShowFamilyFromServer())?.familyId;
      }
      if (!mounted) return;
      setState(() {
        _families = list;
        _familyLoading = false;
        _selectedFamilyId =
            _showFamilyId ?? (list.isEmpty ? null : list.first.familyId);
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

  Future<FamilyShowInfo?> _loadShowFamilyFromServer() async {
    final auth = ref.read(authProvider).auth;
    if (auth == null) return null;
    final client = FamilyClient(uin: auth.uin, s2: auth.s2, s2t: auth.s2t);
    return parseShowFamily(await client.getShowFamily());
  }

  /// 切换展示家族（`set_show_family&family_id=`，对齐 `Btn_family_setClick`）。
  Future<bool> _switchFamilyFromServer(int familyId) async {
    final auth = ref.read(authProvider).auth;
    if (auth == null) return false;
    final client = FamilyClient(uin: auth.uin, s2: auth.s2, s2t: auth.s2t);
    return FamilyClient.isSuccess(await client.setShowFamily(familyId));
  }

  // ── 头像框置顶 ────────────────────────────────────────────────────────

  /// 懒加载已置顶头像框：注入 loader / 快照优先，否则走 [PlayerHomeClient]。
  Future<void> _loadFrameTop() async {
    if (widget.frameTopLoader == null && widget.initial.pinnedFrames != null) {
      // 已有快照且无注入 loader 时无需再拉取。
      if (mounted) setState(() => _topFrameIds = widget.initial.pinnedFrames!);
      return;
    }
    if (mounted) setState(() => _topLoading = true);
    try {
      final ids = widget.frameTopLoader != null
          ? await widget.frameTopLoader!()
          : await _loadFrameTopFromServer();
      if (!mounted) return;
      setState(() {
        _topFrameIds = ids;
        _topLoading = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() => _topLoading = false);
    }
  }

  Future<Set<int>> _loadFrameTopFromServer() async {
    final auth = ref.read(authProvider).auth;
    if (auth == null) return <int>{};
    final client = PlayerHomeClient(uin: auth.uin, s2: auth.s2, s2t: auth.s2t);
    return client.getTopFlagList(moduleId: PlayerHomeModule.headFrame);
  }

  /// 切换头像框置顶状态（`set_top_flag`，1=置顶 / 0=取消）。
  ///
  /// 上限由服务端裁决：失败时原样展示服务端 `msg`（不硬编码上限数字）。
  Future<void> _toggleTop(int frameId) async {
    if (_topBusy) return;
    final pin = !_topFrameIds.contains(frameId);
    setState(() => _topBusy = true);
    try {
      final result = widget.frameTopToggler != null
          ? await widget.frameTopToggler!(frameId, pin)
          : await _toggleTopFromServer(frameId, pin);
      if (!mounted) return;
      if (result.ok) {
        setState(() {
          _topFrameIds = pin
              ? {..._topFrameIds, frameId}
              : ({..._topFrameIds}..remove(frameId));
          _changed = true;
        });
        _toast(pin ? '已置顶' : '已取消置顶');
      } else {
        _toast(result.message ?? (pin ? '置顶失败，请稍后重试' : '取消置顶失败，请稍后重试'));
      }
    } catch (e) {
      if (!mounted) return;
      _toast('操作失败：$e');
    } finally {
      if (mounted) setState(() => _topBusy = false);
    }
  }

  Future<SetTopFlagResult> _toggleTopFromServer(int frameId, bool pin) async {
    final auth = ref.read(authProvider).auth;
    if (auth == null) return const SetTopFlagResult(ok: false);
    final client = PlayerHomeClient(uin: auth.uin, s2: auth.s2, s2t: auth.s2t);
    return client.setTopFlag(
      frameId,
      pin: pin,
      moduleId: PlayerHomeModule.headFrame,
    );
  }

  // ── DIY 自定义头像 ────────────────────────────────────────────────────

  /// 加载当前账号的 DIY 头像状态（`diy_header`）。
  Future<void> _loadDiy() async {
    final loader = widget.diyLoader;
    // 已有快照且无注入 loader 时无需再拉取。
    if (loader == null && widget.initial.diyHead != null) return;
    _diyLoading = true;
    try {
      final info = loader != null ? await loader() : await _loadDiyFromServer();
      if (!mounted) return;
      setState(() {
        _diyHead = info;
        _useDiy = info?.useDiy ?? false;
        _diyLoading = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() => _diyLoading = false);
    }
  }

  Future<DiyHeadInfo?> _loadDiyFromServer() async {
    final auth = ref.read(authProvider).auth;
    if (auth == null) return null;
    final client = ProfileClient(uin: auth.uin, s2: auth.s2, s2t: auth.s2t);
    return client.getMyDiyHeadInfo();
  }

  /// 「自定义」上传入口：注入上传器优先，否则走 FilePicker + [ProfileClient]。
  ///
  /// 真实流程对齐 `playercenterv2headeditorctrl.lua:815-935` `doUploadNewHead`：
  /// 选图 → `upload_pre_photo` → 上传字节 → `set_usr_header3` 确认。
  Future<void> _pickAndUploadDiy() async {
    if (_diyUploading) return;
    final injected = widget.diyUploader;
    setState(() => _diyUploading = true);
    try {
      bool ok;
      if (injected != null) {
        ok = await injected();
      } else {
        final picked = await FilePicker.pickFile(
          dialogTitle: '选择自定义头像',
          type: FileType.custom,
          allowedExtensions: const ['png', 'jpg', 'jpeg'],
        );
        if (picked == null) {
          if (mounted) setState(() => _diyUploading = false);
          return;
        }
        final bytes = await picked.readAsBytes();
        if (!mounted) return;
        final auth = ref.read(authProvider).auth;
        if (auth == null) {
          setState(() => _diyUploading = false);
          return;
        }
        final client = ProfileClient(uin: auth.uin, s2: auth.s2, s2t: auth.s2t);
        ok = await client.uploadDiyAvatar(bytes, fileName: picked.name);
      }
      if (!mounted) return;
      if (ok) {
        _toast('上传成功，等待审核');
        await _loadDiy();
      } else {
        _toast('上传失败，请稍后重试');
      }
    } catch (e) {
      if (mounted) _toast('上传失败：$e');
    } finally {
      if (mounted) setState(() => _diyUploading = false);
    }
  }

  /// 选中当前 DIY 头像（`setPersonCenterHeadInfo&use_diy=1`）。
  Future<void> _applyDiy() async {
    final head = _diyHead;
    if (head == null) return;
    if (head.auditState == DiyAuditState.failed) {
      _toast('当前图片违规无法使用');
      return;
    }
    if (_useDiy) return;
    final auth = ref.read(authProvider).auth;
    if (auth == null) return;
    final type = head.type ?? _headType ?? 1;
    final id = head.id ?? _headId ?? 0;
    if (id <= 0) {
      _toast('头像信息缺失，请稍后重试');
      return;
    }
    try {
      final client = ProfileClient(uin: auth.uin, s2: auth.s2, s2t: auth.s2t);
      final ok = await client.setHeadInfo(type: type, id: id, useDiy: true);
      if (!mounted) return;
      if (ok) {
        setState(() {
          _useDiy = true;
          _changed = true;
        });
        _toast(
          head.auditState == DiyAuditState.pending
              ? '已使用，审核通过后自动替换'
              : '头像已更新',
        );
      } else {
        _toast('设置失败，请稍后重试');
      }
    } catch (e) {
      if (!mounted) return;
      _toast('设置失败：$e');
    }
  }

  // ── 称号 ──────────────────────────────────────────────────────────────

  /// 懒加载已拥有称号 + 配置目录（名称/分类）。
  Future<void> _loadTitles() async {
    setState(() {
      _titlesLoading = true;
      _titlesError = null;
    });
    try {
      final catalog = widget.titleCatalogLoader != null
          ? await widget.titleCatalogLoader!()
          : await TitleConfigClient().catalog();
      final data = widget.titleLoader != null
          ? await widget.titleLoader!()
          : await _loadTitlesFromServer();
      if (!mounted) return;
      setState(() {
        _titleCatalog = catalog;
        _titles = data.all;
        _wornTitleId = data.useTitleId;
        _titlesLoading = false;
        if (_titleTab >= _titleLabels(catalog).length) _titleTab = 0;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _titlesLoading = false;
        _titlesError = '称号列表加载失败';
      });
    }
  }

  Future<TitleShowData> _loadTitlesFromServer() async {
    final auth = ref.read(authProvider).auth;
    if (auth == null) return const TitleShowData();
    final client = TitleClient(uin: auth.uin, s2: auth.s2, s2t: auth.s2t);
    return client.getOwnedTitles();
  }

  /// 佩戴称号（`wear_title&title_id=`）。
  Future<void> _wearTitle(int titleId) async {
    if (titleId == _wornTitleId) return;
    try {
      final ok = widget.titleWearer != null
          ? await widget.titleWearer!(titleId)
          : await _wearTitleFromServer(titleId);
      if (!mounted) return;
      if (ok) {
        setState(() {
          _wornTitleId = titleId;
          _changed = true;
        });
        _toast('称号已佩戴');
      } else {
        _toast('佩戴失败，请稍后重试');
      }
    } catch (e) {
      if (!mounted) return;
      _toast('佩戴失败：$e');
    }
  }

  Future<bool> _wearTitleFromServer(int titleId) async {
    final auth = ref.read(authProvider).auth;
    if (auth == null) return false;
    final client = TitleClient(uin: auth.uin, s2: auth.s2, s2t: auth.s2t);
    return client.wearTitle(titleId);
  }

  /// 称号分类页签文案：有配置时用配置分类，否则回退 [kTitleCategoryTabs]。
  List<String> _titleLabels(TitleCatalog catalog) {
    final types = catalog.sortedTypes;
    return types.isEmpty
        ? kTitleCategoryTabs
        : ['全部', ...types.map((t) => t.name)];
  }

  /// 按当前分类过滤称号（`title.sort == title_typeList[].id`）。
  List<OwnedTitle> _filteredTitles(TitleCatalog catalog) {
    if (_titleTab <= 0) return _titles;
    final types = catalog.sortedTypes;
    final idx = _titleTab - 1;
    if (idx < 0 || idx >= types.length) return _titles;
    final groupType = types[idx].id;
    return _titles
        .where((t) => catalog.entries[t.id]?.sort == groupType)
        .toList();
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
          _useDiy = false;
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
          _useDiy = false;
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

  /// 家族卡片点选：调用 `set_show_family&family_id=` 切换展示家族。
  Future<void> _onFamilyTap(FamilyInfo family) async {
    if (family.familyId == _selectedFamilyId) return;
    try {
      final ok = widget.familySwitcher != null
          ? await widget.familySwitcher!(family.familyId)
          : await _switchFamilyFromServer(family.familyId);
      if (!mounted) return;
      if (ok) {
        setState(() {
          _selectedFamilyId = family.familyId;
          _showFamilyId = family.familyId;
          _changed = true;
        });
        _toast('展示家族已更新');
      } else {
        _toast('切换失败，请稍后重试');
      }
    } catch (e) {
      if (!mounted) return;
      _toast('切换失败：$e');
    }
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
          key: avatarEditDiyUploadKey,
          selected: false,
          // 真实上传入口：`upload_pre_photo` → 上传字节 → `set_usr_header3`。
          onTap: _pickAndUploadDiy,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (_diyUploading || _diyLoading)
                const SizedBox(
                  width: 20,
                  height: 20,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              else
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
      // 当前 DIY 头像（`diy_header` 单个对象）：展示审核态，可点选启用。
      final diyUrl = _diyHead?.displayUrl;
      if (diyUrl != null) {
        cells.add(_diyCell(theme, diyUrl));
      }
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

  /// DIY 自定义头像格子：网络图 + 审核态角标 + 选中态。
  Widget _diyCell(ThemeData theme, String url) {
    final state = _diyHead!.auditState;
    return _SelectableCell(
      key: avatarEditDiyCellKey,
      selected: _useDiy,
      onTap: _applyDiy,
      child: Stack(
        fit: StackFit.expand,
        children: [
          Padding(
            padding: const EdgeInsets.all(AppSpacing.xs),
            child: ClipRRect(
              borderRadius: AppRadius.inputR,
              child: Image(image: CachedNetworkImageProvider(url),
                fit: BoxFit.cover,
                errorBuilder: (_, _, _) => Icon(
                  Icons.image_not_supported_outlined,
                  size: 20,
                  color: theme.colorScheme.outline,
                ),
              ),
            ),
          ),
          if (state == DiyAuditState.pending)
            const Positioned(
              left: 2,
              bottom: 2,
              child: _AuditTag(text: '审核中', warning: true),
            ),
          if (state == DiyAuditState.failed)
            const Positioned(
              left: 2,
              bottom: 2,
              child: _AuditTag(text: '审核失败'),
            ),
        ],
      ),
    );
  }

  /// 头像右栏：预览 + 上传提示 + `会员免费` + `使用中`。
  Widget _avatarPanel(ThemeData theme, {required bool narrow}) {
    final scheme = theme.colorScheme;
    // 使用 DIY 时展示 DIY 图（此时不传本体 type/id，避免本地图标覆盖网络图）。
    final diyUrl = _diyHead?.displayUrl ?? widget.initial.avatarUrl;
    final showDiy = _useDiy && diyUrl != null;
    final preview = AvatarView(
      avatarUrl: showDiy ? diyUrl : null,
      name: _name.isEmpty ? '${widget.initial.uin}' : _name,
      radius: narrow ? 24 : 36,
      headType: showDiy ? null : _headType,
      headId: showDiy ? null : _headId,
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
    // 参考图格式为 `<框名>: <获取途径>`（对齐 playercenterv2headeditorview.lua
    // :281-291）；名称 / 获取途径取自本地目录 [kHeadFrameCatalog]，未收录时回退占位。
    final captionText = id == null ? '—' : headFrameCaption(id);
    final caption = Tooltip(
      message: captionText,
      child: Text(
        captionText,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: theme.textTheme.labelMedium?.copyWith(
          color: scheme.onSurfaceVariant,
        ),
      ),
    );
    final pinned = id != null && _topFrameIds.contains(id);
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
          // 置顶状态读自 `get_top_flag_list`；点按经 `set_top_flag` 切换
          // （1=置顶 / 0=取消，见 playercenterv2headeditorctrl.lua:1515）。
          onPressed: (id == null || _topBusy || _topLoading)
              ? null
              : () => _toggleTop(id),
          icon: Icon(
            pinned ? Icons.arrow_downward : Icons.arrow_upward,
            size: 16,
          ),
          label: Text(pinned ? '取消置顶' : '置顶'),
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
    if (_titlesLoading) {
      return const Center(child: CircularProgressIndicator());
    }
    final error = _titlesError;
    if (error != null) {
      return Center(child: _EmptyHint(error, center: true));
    }
    final catalog = _titleCatalog;
    final types = catalog.sortedTypes;
    final labels = _titleLabels(catalog);
    final tabs = _TopTabs(
      tabsKey: avatarEditTitleTabsKey,
      labels: labels,
      index: _titleTab,
      onChanged: (i) => setState(() => _titleTab = i),
    );
    // 分类配置缺失时无法按分类筛选（仅「全部」可用）。
    if (_titleTab > 0 && types.isEmpty) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          tabs,
          const SizedBox(height: AppSpacing.md),
          const Expanded(
            child: Center(
              child: _EmptyHint('称号分类配置未获取，暂无法按分类筛选', center: true),
            ),
          ),
        ],
      );
    }
    final titles = _filteredTitles(catalog);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        tabs,
        const SizedBox(height: AppSpacing.md),
        Expanded(
          child: titles.isEmpty
              ? const Center(child: _EmptyHint('该分类下暂无称号', center: true))
              : GridView.count(
                  padding: EdgeInsets.zero,
                  crossAxisCount: 3,
                  mainAxisSpacing: AppSpacing.sm,
                  crossAxisSpacing: AppSpacing.sm,
                  childAspectRatio: 1.7,
                  children: [
                    for (final t in titles)
                      _TitleCard(
                        key: avatarEditTitleCellKey(t.id),
                        name: catalog.names[t.id] ?? '称号 #${t.id}',
                        dateRange: t.validRange,
                        selected: t.id == _wornTitleId,
                        expired: t.expired,
                        onTap: () => _wearTitle(t.id),
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
      // 页签含文字，高度随系统字号缩放以免裁切。
      height: MediaQuery.textScalerOf(context).scale(32),
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

/// DIY 审核态角标（`审核中` / `审核失败`）。
class _AuditTag extends StatelessWidget {
  final String text;

  /// `true` = 审核中（警示色）；`false` = 审核失败（错误色）。
  final bool warning;

  const _AuditTag({required this.text, this.warning = false});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final color = warning ? AppSemanticColors.of(context).warning : scheme.error;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 1),
      decoration: BoxDecoration(
        color: scheme.surface.withValues(alpha: 0.85),
        borderRadius: AppRadius.chipR,
        border: Border.all(color: color, width: 0.8),
      ),
      child: Text(
        text,
        style: theme.textTheme.labelSmall?.copyWith(
          color: color,
          fontWeight: FontWeight.w700,
          height: 1.0,
        ),
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

/// 称号卡片：称号名 + `有效期` + 日期区间；可点选佩戴。
class _TitleCard extends StatelessWidget {
  final String name;

  /// 日期区间（`2026.07.31--永久`）；数据缺失时为 `—`。
  final String dateRange;

  /// 是否为当前佩戴称号（选中态描边 + 勾选角标）。
  final bool selected;

  /// 是否已过期（文字淡化）。
  final bool expired;

  /// 点选佩戴回调。
  final VoidCallback onTap;

  const _TitleCard({
    super.key,
    required this.name,
    required this.dateRange,
    this.selected = false,
    this.expired = false,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final warning = AppSemanticColors.of(context).warning;
    final baseColor = expired
        ? scheme.onSecondaryContainer.withValues(alpha: 0.55)
        : scheme.onSecondaryContainer;
    return InkWell(
      onTap: onTap,
      borderRadius: AppRadius.cardR,
      child: Container(
        padding: const EdgeInsets.all(AppSpacing.sm),
        decoration: BoxDecoration(
          color: scheme.secondaryContainer,
          borderRadius: AppRadius.cardR,
          border: Border.all(
            color: selected ? warning : Colors.transparent,
            width: selected ? 2 : 1,
          ),
        ),
        child: Stack(
          children: [
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                RichTextView(
                  name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.titleSmall?.copyWith(
                    color: baseColor,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      '有效期',
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: baseColor.withValues(alpha: 0.7),
                      ),
                    ),
                    Text(
                      dateRange,
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: baseColor,
                      ),
                    ),
                  ],
                ),
              ],
            ),
            if (selected)
              const Positioned(top: 0, right: 0, child: _CheckBadge()),
          ],
        ),
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
