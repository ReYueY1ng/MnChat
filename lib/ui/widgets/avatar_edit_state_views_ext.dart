part of 'avatar_edit_dialog.dart';

mixin _AvatarEditStateViewsExt
    on ConsumerState<AvatarEditDialog>, _AvatarEditStateBase, _AvatarEditStateData {

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
