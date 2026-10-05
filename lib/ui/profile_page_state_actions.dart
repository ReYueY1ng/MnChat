part of 'profile_page.dart';

mixin _ProfilePageStateActions
    on ConsumerState<ProfilePage>, _ProfilePageStateBase {
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

  /// 打开某个玩家的个人主页（最佳拍档条目用）。
  /// 外部客户端无 3D 家园，统一降级为玩家主页。
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

  /// 打开「头像编辑」弹窗（头像 / 头像框 / 昵称 / 称号 / 家族）。
  ///
  /// 弹窗使用当前快照（[AvatarEditInitialData]），关闭后若确实改过任何一项
  /// 则刷新资料与主页模块，保证个人主页与弹窗内即时生效的设置一致。
  Future<void> _openAvatarEdit() async {
    final auth = ref.read(authProvider).auth;
    final changed = await showAvatarEditDialog(
      context,
      initial: AvatarEditInitialData(
        uin: auth?.uin ?? 0,
        name: auth?.name ?? '',
        avatarUrl: _avatarUrl,
        headType: _headType,
        headId: _headId,
        frameId: _frameId,
        ownedFrames: _ownedFrames,
        portraits: _portraits,
        titleName: _titleName,
      ),
    );
    if (!mounted || !changed) return;
    await _loadProfile();
    await _loadHomeModules();
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
}
