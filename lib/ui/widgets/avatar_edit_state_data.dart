part of 'avatar_edit_dialog.dart';

mixin _AvatarEditStateData
    on ConsumerState<AvatarEditDialog>, _AvatarEditStateBase {
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

}
