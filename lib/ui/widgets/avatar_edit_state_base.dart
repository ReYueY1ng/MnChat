part of 'avatar_edit_dialog.dart';

mixin _AvatarEditStateBase on ConsumerState<AvatarEditDialog> {
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
      } else {
        _showFamilyId ??= (await _loadShowFamilyFromServer())?.familyId;
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
    // 解析已下沉到客户端（返回 List<FamilyInfo>），这里不再自己 parse 一遍。
    return client.getFamilyList();
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

  // ── 称号 ──────────────────────────────────────────────────────────────
  //
  // 这三个方法放 Base 而不是 `_AvatarEditStateData`：`_switchTab` 要调
  // `_loadTitles`，而 Data 是 `on ...Base` 的 —— 反过来让 Base 看到 Data 会
  // 形成 mixin 环。这些方法用到的字段全部就在这里，所以放这边是自然的。

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

  /// 称号分类页签文案：有配置时用配置分类，否则回退 [kTitleCategoryTabs]。
  List<String> _titleLabels(TitleCatalog catalog) {
    final types = catalog.sortedTypes;
    return types.isEmpty
        ? kTitleCategoryTabs
        : ['全部', ...types.map((t) => t.name)];
  }
}
