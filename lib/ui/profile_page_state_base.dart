part of 'profile_page.dart';

mixin _ProfilePageStateBase on ConsumerState<ProfilePage> {
  /// 是否在看自己的主页（决定要不要露出编辑入口）。
  bool get _isSelf => widget.targetUin == null;

  /// 主页主人的昵称。
  ///
  /// 自己 → 账号昵称；别人 → `get_user_homepage` 的
  /// `role_info.data.profile.RoleInfo.NickName`，其次批量资料，最后回退迷你号。
  /// **绝不能拿 `auth.name`**（那是登录账号 = 我自己）。
  String get _displayName {
    if (_isSelf) return ref.watch(authProvider).auth?.name ?? '';
    final roleInfo = _home?['role_info'];
    if (roleInfo is Map) {
      final rd = roleInfo['data'];
      if (rd is Map) {
        final profile = rd['profile'];
        if (profile is Map) {
          final ri = (profile.cast<String, Object?>())['RoleInfo'];
          if (ri is Map) {
            final n = (ri.cast<String, Object?>())['NickName']?.toString();
            if (n != null && n.isNotEmpty) return n;
          }
        }
      }
    }
    final cached = _nickname;
    if (cached != null && cached.isNotEmpty) return cached;
    return '$_target';
  }

  /// 纯文本昵称：给 AppBar / 名牌这类**不走富文本**的地方用。
  ///
  /// 服务端 `NickName` 会带 `[i][color][b]…` 这类标记（资料头卡里的
  /// `RichTextView` 会把它渲染出来），不走富文本的地方必须先过
  /// [plainNickname]，否则标记会原样显示 —— 主页标题与交友宣言的名牌就
  /// 踩过这个坑，同一屏里头卡显示「顾念」、标题却是 `[i][color][b]顾念`。
  /// 清洗后为空（昵称只由标记组成）时回退迷你号。
  String get _plainName {
    final plain = plainNickname(_displayName);
    return plain.isEmpty ? '$_target' : plain;
  }

  /// 主页主人。自己的话就是登录账号。
  int get _target =>
      widget.targetUin ?? (ref.read(authProvider).auth?.uin ?? 0);

  /// 关注 / 拉黑状态（仅他人主页有意义）。
  bool _following = false;
  bool _blacklisted = false;
  bool _relationBusy = false;

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

  /// 我的收藏夹数量（`miniw/favorite?act=get_collect_ids`）；null = 未取到。
  int? _favoriteCount;

  /// 迷你印迹数量（`miniw/camera?act=get_photo_homepage`）；null = 未取到。
  int? _multimediaCount;

  /// IP 属地（`miniw/user_ext?act=get_user_addr`）；null = 尚未取到。
  String? _ipAddr;

  /// 批量资料里拿到的昵称（他人主页的兜底显示名）。
  String? _nickname;

  /// 动态卡：已置顶 / 最新动态的 pid（`posting.data.top_pid` / `last_pid`）；
  /// 0 = 无（依据 `playercenterv2dynamicctrl.lua:13-27` 的排序键）。
  int _pinnedPid = 0;
  int _latestPid = 0;

  /// 置顶动态请求进行中（防连点）。
  bool _postingTopBusy = false;

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
    _loadExtraCounts();
    if (!_isSelf) {
      _syncRelation();
      // 看别人主页时记一次访问（受「留下踪迹」开关与 24h 去重约束，失败忽略）。
      unawaited(_recordVisitIfNeeded());
    }
  }

  /// 从 `role_info.data.profile.relation` 读关注 / 拉黑状态。
  void _syncRelation() {
    final roleInfo = _home?['role_info'];
    if (roleInfo is! Map) return;
    final rd = roleInfo['data'];
    if (rd is! Map) return;
    final profile = rd['profile'];
    if (profile is! Map) return;
    final p = profile.cast<String, Object?>();
    final rel = p['relation'];
    if (rel is! Map) return;
    final r = rel.cast<String, Object?>();
    int bit(String k) {
      final v = r[k];
      if (v is num) return v.toInt();
      return int.tryParse('$v') ?? 0;
    }

    if (!mounted) return;
    setState(() {
      _following = bit('friend_attention') == 1;
      _blacklisted = bit('friend_black') == 1;
    });
  }

  /// 记一次访问记录（对齐官方 `add_visit_record`）。
  ///
  /// 必须直接读**持久化**的开关值：`leaveVisitTraceProvider` 的 build() 会先
  /// 同步返回默认 true，冷启动后先去别人主页时会把「已关闭」当成开启。
  Future<void> _recordVisitIfNeeded() async {
    try {
      final store = ref.read(settingsProvider);
      final leaveTrace = await PlayerHomeClient.leaveTraceEnabled(store);
      if (!leaveTrace) return;
      final target = _target;
      final lastSentAt = await store.visitSentAt(target);
      final now = DateTime.now().millisecondsSinceEpoch ~/ 1000;
      if (!PlayerHomeClient.shouldRecordVisit(
        leaveTrace: leaveTrace,
        lastSentAt: lastSentAt,
        now: now,
      )) {
        return;
      }
      final auth = ref.read(authProvider).auth;
      if (auth == null) return;
      final ok = await PlayerHomeClient(
        uin: auth.uin,
        s2: auth.s2,
        s2t: auth.s2t,
      ).addVisitRecord(target);
      if (ok) await store.setVisitSentAt(target, now);
    } catch (_) {
      // 失败忽略
    }
  }

  Future<void> _toggleFollow() async {
    if (_relationBusy) return;
    setState(() => _relationBusy = true);
    try {
      await ref
          .read(chatServiceProvider)
          .followPlayer(_target, follow: !_following);
      if (!mounted) return;
      setState(() => _following = !_following);
      _toast(_following ? '已关注' : '已取消关注');
    } catch (e) {
      _toast('操作失败: $e');
    } finally {
      if (mounted) setState(() => _relationBusy = false);
    }
  }

  Future<void> _toggleBlacklist() async {
    if (_relationBusy) return;
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(_blacklisted ? '移出黑名单' : '加入黑名单'),
        content: Text(
          _blacklisted ? '确定将 TA 移出黑名单吗？' : '拉黑后将无法看到 TA 的动态与消息，确定？',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            child: const Text('确定'),
          ),
        ],
      ),
    );
    if (ok != true || !mounted) return;
    setState(() => _relationBusy = true);
    try {
      final service = ref.read(chatServiceProvider);
      if (_blacklisted) {
        await service.removeBlacklist(_target);
      } else {
        await service.addBlacklist(_target);
      }
      if (!mounted) return;
      setState(() => _blacklisted = !_blacklisted);
      _toast(_blacklisted ? '已加入黑名单' : '已移出黑名单');
    } catch (e) {
      _toast('操作失败: $e');
    } finally {
      if (mounted) setState(() => _relationBusy = false);
    }
  }

  void _toast(String message) {
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(message)));
  }

  /// 拉取当前账号的头像、头像框与头像本体（皮肤 / 立绘）。
  /// 各接口独立 try/catch：任一失败只回退占位，不影响页面展示。
  Future<void> _loadProfile() async {
    final auth = ref.read(authProvider).auth;
    if (auth == null) return;
    final target = _target;
    final client = ProfileClient(uin: auth.uin, s2: auth.s2, s2t: auth.s2t);

    String? avatarUrl;
    int? frameId;

    try {
      // DIY 自定义头像优先（游戏主界面同源）
      final diy = await client.getPersonCenterHeadInfo([target]);
      avatarUrl = diy[target];
    } catch (_) {
      // 忽略：DIY 头像拉取失败时回退到批量资料头像
    }

    Set<int> ownedFrames = {};
    int? headType;
    int? headId;

    if (_isSelf) {
      // 本人：走"我的"资料接口，能拿到已拥有的头像框 / 立绘（要用于选择器）
      try {
        final profile = await client.getMyProfile();
        if (profile != null) {
          avatarUrl ??= profile.avatarUrl;
          frameId = profile.headFrameId;
          ownedFrames = {...profile.ownedHeadFrameIds};
        }
      } catch (e) {
        // 忽略：资料拉取失败时展示首字占位头像
        log.warn('getMyProfile 失败: $e', tag: _logTag);
      }

      // 兜底：单个资料接口有时不下发 head_frames（表现：选择器只剩默认框 1）。
      // 再用批量资料接口取一次并集，并打印数量便于定位问题。
      if (ownedFrames.length <= 1) {
        try {
          final list = await client.getProfileBatch3([target]);
          if (list.isNotEmpty) {
            frameId ??= list.first.headFrameId;
            ownedFrames.addAll(list.first.ownedHeadFrameIds);
          }
        } catch (e) {
          log.warn('getProfileBatch3 补头像框失败: $e', tag: _logTag);
        }
      }
      log.debug('已拥有头像框 ${ownedFrames.length} 个', tag: _logTag);

      try {
        final head = await client.getMyHeadInfo();
        if (head != null) {
          headType = head.type;
          headId = head.id;
        }
      } catch (_) {
        // 忽略：头像本体拉取失败时仅展示昵称首字占位
      }
    } else {
      // 他人：批量资料 + 头像槽位（都是按 uin 查的公开接口）
      try {
        final list = await client.getProfileBatch3([target]);
        if (list.isNotEmpty) {
          avatarUrl ??= list.first.avatarUrl;
          frameId = list.first.headFrameId;
          _nickname = list.first.nickname;
        }
      } catch (e) {
        log.warn('getProfileBatch3 拉他人资料失败: $e', tag: _logTag);
      }
      try {
        final heads = await client.getPersonCenterHeadInfos([target]);
        final slot = heads[target];
        if (slot != null) {
          headType = slot.type;
          headId = slot.id;
        }
      } catch (_) {
        // 忽略：拿不到就用首字占位
      }
    }

    List<PortraitItem> portraits = [];
    if (_isSelf) {
      try {
        portraits = await client.getOwnedPortraits();
      } catch (_) {
        // 忽略：立绘拉取失败不展示立绘瓦片
      }
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

    final target = _target;
    Map<String, Object?>? home;
    String? titleName;
    var level = 0;
    try {
      final svc = ref.read(chatServiceProvider);
      home = await svc.userHomepage(target);
      level = await svc.platformLevel(target);
      final titleId = homepageTitleId(home);
      titleName = titleId > 0 ? await svc.titleName(titleId) : null;
    } catch (e) {
      log.warn('主页模块拉取失败: $e', tag: _logTag);
    }

    // 大会员只有「我的」接口，看别人主页时不展示。
    var isVip = false;
    if (_isSelf) {
      try {
        final expiry = await ref.read(partnerClientProvider)?.getMyVipExpiry();
        final now = DateTime.now().millisecondsSinceEpoch ~/ 1000;
        isVip = expiry != null && expiry > now;
      } catch (e) {
        log.warn('大会员状态拉取失败: $e', tag: _logTag);
      }
    }

    if (!mounted) return;
    setState(() {
      _home = home;
      _titleName = titleName;
      _declaration = homepageDeclaration(home);
      _level = level;
      _isVip = isVip;
      _pinnedPid = homepagePostingTopPid(home);
      _latestPid = homepagePostingLastPid(home);
    });
    if (!_isSelf) _syncRelation();
  }

  /// 拉取「我的收藏夹」「迷你印迹」与 IP 属地三个独立接口。
  ///
  /// 它们都不在 `get_user_homepage` 模块数据内：收藏夹走
  /// `miniw/favorite?act=get_collect_ids`（`contentfavsservice.lua:205-209`），
  /// 印迹走 `miniw/camera?act=get_photo_homepage`
  /// （`multimediaalbumservice.lua:255-261`），IP 属地走
  /// `miniw/user_ext?act=get_user_addr`（`playercenteripadressctrl.lua:77-105`）。
  /// 三组请求各自独立降级：失败只回退为占位/「未知」，互不影响。
  Future<void> _loadExtraCounts() async {
    final auth = ref.read(authProvider).auth;
    if (auth == null) return;
    final target = _target;
    final client = PlayerHomeClient(uin: auth.uin, s2: auth.s2, s2t: auth.s2t);

    int? favoriteCount;
    try {
      favoriteCount = await client.getFavoriteFolderCount(target);
    } catch (e) {
      log.warn('我的收藏夹数量拉取失败: $e', tag: _logTag);
    }

    int? multimediaCount;
    try {
      multimediaCount = await client.getMultimediaImprintCount(target);
    } catch (e) {
      log.warn('迷你印迹数量拉取失败: $e', tag: _logTag);
    }

    String? ipAddr;
    try {
      ipAddr = await client.getUserAddr(target);
    } catch (e) {
      log.warn('IP 属地拉取失败: $e', tag: _logTag);
    }

    if (!mounted) return;
    setState(() {
      _favoriteCount = favoriteCount;
      _multimediaCount = multimediaCount;
      _ipAddr = ipAddr;
    });
  }

  /// 家族名（`family` 模块）；没加入家族则为空。
  String get _familyName {
    final fam = _home?['family'];
    if (fam is! Map) return '';
    final f = fam['data'];
    if (f is! Map) return '';
    final fm = f.cast<String, Object?>();
    return fm['family_name']?.toString() ?? fm['name']?.toString() ?? '';
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

  /// 置顶 / 取消置顶动态（`set_top_flag`，module_id = [PlayerHomeModule.posting]）。
  ///
  /// 已有置顶 → 取消（op_id = `top_pid`，op_type 0）；否则置顶最新动态
  /// （op_id = `last_pid`，op_type 1）。置顶上限由**服务端**裁决
  /// （`CheckMaxTop` → `MaxTopNum`），失败时原样透出服务端文案，客户端不硬编码。
  Future<void> _togglePostingTop() async {
    final auth = ref.read(authProvider).auth;
    if (auth == null) return;
    final pin = _pinnedPid == 0;
    final opId = pin ? _latestPid : _pinnedPid;
    if (opId == 0) return;

    setState(() => _postingTopBusy = true);
    SetTopFlagResult result;
    try {
      final client = PlayerHomeClient(
        uin: auth.uin,
        s2: auth.s2,
        s2t: auth.s2t,
      );
      result = await client.setTopFlag(
        opId,
        pin: pin,
        moduleId: PlayerHomeModule.posting,
      );
    } catch (e) {
      result = SetTopFlagResult(ok: false, message: '$e');
    }
    if (!mounted) return;
    setState(() => _postingTopBusy = false);
    if (!result.ok) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(result.message ?? '置顶失败')),
      );
      return;
    }
    await _loadHomeModules();
  }

  /// 打开「编辑布局」：拉取服务端布局 → 拖拽排序 → 保存。
  ///
  /// 协议 `get_homepage_layout` / `change_homepage_layout`
  /// （`playercenterv2homepageservice.lua:26-66`）。布局条目由服务端以 JSON 串
  /// 下发（同文件 `:87`），本流程**只改顺序、原样回传**，不臆造布局 schema。
  Future<void> _openLayoutEditor() async {
    final auth = ref.read(authProvider).auth;
    if (auth == null) return;
    final client = PlayerHomeClient(uin: auth.uin, s2: auth.s2, s2t: auth.s2t);

    List<Map<String, Object?>> layout;
    try {
      layout = await client.getHomepageLayout(_target);
    } catch (e) {
      log.warn('主页布局拉取失败: $e', tag: _logTag);
      layout = const <Map<String, Object?>>[];
    }
    if (!mounted) return;
    if (layout.isEmpty) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('未取到主页布局')));
      return;
    }

    final saved = await showHomeLayoutDialog(
      context,
      layout: layout,
      save: (next) async {
        try {
          return await client.changeHomepageLayout(next);
        } catch (e) {
          log.warn('主页布局保存失败: $e', tag: _logTag);
          return false;
        }
      },
    );
    if (!mounted || !saved) return;
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(const SnackBar(content: Text('布局已保存')));
    await _loadHomeModules();
  }
}
