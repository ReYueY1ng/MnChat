import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/models/skin_head_catalog.dart';
import '../core/services/name_rules.dart'
    show renameErrorText, validateNickname;
import '../core/services/profile.dart' show ProfileClient, PortraitItem;
import '../state/providers.dart';
import 'social_sign_page.dart';
import 'theme/app_tokens.dart';
import 'visitor_list_page.dart';
import 'widgets/avatar_view.dart';
import 'widgets/head_frame.dart';
import 'widgets/rich_text_view.dart';

/// 个人资料页：展示头像 / 昵称 / uin，提供修改昵称与交友标签入口。
class ProfilePage extends ConsumerStatefulWidget {
  const ProfilePage({super.key});

  @override
  ConsumerState<ProfilePage> createState() => _ProfilePageState();
}

class _ProfilePageState extends ConsumerState<ProfilePage> {
  /// DIY 自定义头像（优先）或批量资料头像；为空时回退首字占位。
  String? _avatarUrl;

  /// 头像框 id（RoleInfo.head_frame_id）。
  int? _frameId;

  /// 当前"头像本体"类型/ID（type 1=皮肤）。null 表示未取到。
  int? _headType;
  int? _headId;

  /// 已拥有的头像框 id（含默认框 1）；用于头像框选择。
  Set<int> _ownedFrames = {};

  /// 已拥有的立绘列表；为空时不展示"立绘头像"区块。
  List<PortraitItem> _portraits = [];

  @override
  void initState() {
    super.initState();
    _loadProfile();
  }

  /// 拉取当前账号的头像、头像框与头像本体（皮肤）。
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
        ownedFrames = profile.ownedHeadFrameIds;
      }
    } catch (_) {
      // 忽略：资料拉取失败时展示首字占位头像
    }

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
      // 忽略：立绘拉取失败不展示该区块
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
      borderRadius: BorderRadius.circular(12),
      child: Container(
        width: 64,
        height: 64,
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(12),
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
    return InkWell(
      onTap: () => _applyHeadSkin(skinId),
      borderRadius: BorderRadius.circular(12),
      child: Container(
        width: 64,
        height: 64,
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: selected
                ? theme.colorScheme.primary
                : theme.colorScheme.outlineVariant,
            width: selected ? 2 : 1,
          ),
        ),
        child: Center(
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
        ),
      ),
    );
  }

  /// 立绘头像选择瓦片（当前选中的高亮描边）。
  Widget _portraitTile(ThemeData theme, PortraitItem p) {
    final selected = _headType == 4 && _headId == p.id;
    return InkWell(
      onTap: () => _applyPortrait(p),
      borderRadius: BorderRadius.circular(12),
      child: Container(
        width: 64,
        height: 64,
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: selected
                ? theme.colorScheme.primary
                : theme.colorScheme.outlineVariant,
            width: selected ? 2 : 1,
          ),
        ),
        child: Center(
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
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final auth = ref.watch(authProvider).auth;
    final skins = _ownedSkins;

    // 头像本体（皮肤/坐骑/立绘）有本地图标时，优先展示并叠加头像框。
    final localHead = (_headType != null && _headId != null && _headId! > 0)
        ? headIconAsset(_headType!, _headId!)
        : null;
    final fallbackAvatar = AvatarView(
      avatarUrl: _avatarUrl,
      name: auth?.name ?? '',
      frameId: _frameId,
      radius: 40,
    );

    return Scaffold(
      appBar: AppBar(title: const Text('个人资料')),
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: AppSizes.narrowContent),
          child: ListView(
            padding: const EdgeInsets.all(12),
            children: [
              // 头像 / 昵称 / uin
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Row(
                    children: [
                      if (localHead != null)
                        SizedBox(
                          width: 80,
                          height: 80,
                          child: Stack(
                            fit: StackFit.expand,
                            children: [
                              Image.asset(
                                localHead,
                                width: 80,
                                height: 80,
                                fit: BoxFit.contain,
                                errorBuilder: (_, _, _) => fallbackAvatar,
                              ),
                              HeadFrameOverlay(frameId: _frameId, size: 80),
                            ],
                          ),
                        )
                      else
                        fallbackAvatar,
                      const SizedBox(width: 16),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            RichTextView(
                              auth?.name ?? '',
                              style: theme.textTheme.titleLarge,
                            ),
                            const SizedBox(height: 4),
                            Text(
                              'Uin: ${auth?.uin ?? '-'}',
                              style: theme.textTheme.bodySmall?.copyWith(
                                color: theme.colorScheme.outline,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 12),
              // 头像框
              if (_ownedFrames.isNotEmpty) ...[
                Card(
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Icon(
                              Icons.filter_frames_outlined,
                              color: theme.colorScheme.primary,
                            ),
                            const SizedBox(width: 12),
                            Text('头像框', style: theme.textTheme.titleSmall),
                          ],
                        ),
                        const SizedBox(height: 12),
                        Wrap(
                          spacing: 8,
                          runSpacing: 8,
                          children: [
                            for (final id in (_ownedFrames.toList()..sort()))
                              _frameTile(theme, id),
                          ],
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 12),
              ],
              // 头像（皮肤本体）
              if (skins.isNotEmpty) ...[
                Card(
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Icon(
                              Icons.face_retouching_natural,
                              color: theme.colorScheme.primary,
                            ),
                            const SizedBox(width: 12),
                            Text('头像', style: theme.textTheme.titleSmall),
                          ],
                        ),
                        const SizedBox(height: 12),
                        Wrap(
                          spacing: 8,
                          runSpacing: 8,
                          children: [
                            for (final e in skins.entries)
                              _skinTile(theme, e.key, e.value),
                          ],
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 12),
              ],
              // 立绘头像
              if (_portraits.isNotEmpty) ...[
                Card(
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Icon(
                              Icons.person_pin,
                              color: theme.colorScheme.primary,
                            ),
                            const SizedBox(width: 12),
                            Text('立绘头像', style: theme.textTheme.titleSmall),
                          ],
                        ),
                        const SizedBox(height: 12),
                        Wrap(
                          spacing: 8,
                          runSpacing: 8,
                          children: [
                            for (final p in _portraits) _portraitTile(theme, p),
                          ],
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 12),
              ],
              // 修改昵称
              Card(
                child: ListTile(
                  leading: const Icon(Icons.drive_file_rename_outline),
                  title: const Text('修改昵称'),
                  subtitle: const Text('消耗迷你币/改名卡，昵称将进入审核'),
                  trailing: const Icon(Icons.chevron_right),
                  onTap: _editNickname,
                ),
              ),
              const SizedBox(height: 12),
              // 交友标签（个性签名）
              Card(
                child: ListTile(
                  leading: const Icon(Icons.auto_awesome),
                  title: const Text('交友标签'),
                  subtitle: const Text('设置我的个性签名（想要/喜欢）'),
                  trailing: const Icon(Icons.chevron_right),
                  onTap: () => Navigator.of(context).push(
                    MaterialPageRoute(builder: (_) => const SocialSignPage()),
                  ),
                ),
              ),
              const SizedBox(height: 12),
              // 访客记录（谁来看过我）
              Card(
                child: ListTile(
                  leading: const Icon(Icons.visibility_outlined),
                  title: const Text('访客记录'),
                  subtitle: const Text('看看最近谁访问了我的主页'),
                  trailing: const Icon(Icons.chevron_right),
                  onTap: () {
                    final auth = ref.read(authProvider).auth;
                    if (auth == null) return;
                    Navigator.of(context).push(
                      MaterialPageRoute(
                        builder: (_) => VisitorListPage(ownerUin: auth.uin),
                      ),
                    );
                  },
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
