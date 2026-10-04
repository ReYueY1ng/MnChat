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

part 'avatar_edit_state_base.dart';
part 'avatar_edit_state_data.dart';
part 'avatar_edit_state_views.dart';
part 'avatar_edit_state_views_ext.dart';
part 'avatar_edit_widgets.dart';

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

class _AvatarEditDialogState extends ConsumerState<AvatarEditDialog>
    with
        _AvatarEditStateBase,
        _AvatarEditStateData,
        // ViewsExt 必须排在 Views 之前：Views.build 要调 Ext 的 _buildXxxTab，
        // 而 mixin 只看得到 `with` 里排在它前面的成员。
        _AvatarEditStateViewsExt,
        _AvatarEditStateViews {}
