part of 'avatar_edit_dialog.dart';

mixin _AvatarEditStateViews
    on
        ConsumerState<AvatarEditDialog>,
        _AvatarEditStateBase,
        _AvatarEditStateData,
        _AvatarEditStateViewsExt {
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
}
