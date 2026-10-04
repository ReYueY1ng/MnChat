/// 设置 · 隐私与数据子页。
///
/// 内容：访问踪迹、加好友限制（服务端）、拉群两个开关、聊天记录导出/导入，
/// 以及存储占用与清理（图片磁盘缓存）。
///
/// 「拒绝陌生人加好友」原本挂在设置页的「社交」分组下，语义上属于隐私，
/// 挪到这里；「允许他人拉我入群 / 自动加入被邀请的群」同理。
library;

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';

import '../core/services/image_disk_cache.dart' show ImageDiskCache;
import '../state/providers.dart';
import 'data_page.dart';
import 'theme/app_tokens.dart';
import 'widgets/settings_tiles.dart';

class SettingsPrivacyPage extends ConsumerStatefulWidget {
  const SettingsPrivacyPage({super.key});

  @override
  ConsumerState<SettingsPrivacyPage> createState() =>
      _SettingsPrivacyPageState();
}

class _SettingsPrivacyPageState extends ConsumerState<SettingsPrivacyPage> {
  /// 「拒绝陌生人加好友」开关（服务端 cmd=get/set_closeapply_flag）。
  bool _closeapply = false;
  bool _closeapplyLoaded = false;

  /// 图片磁盘缓存占用（字节）；null = 还在统计。
  int? _cacheBytes;
  bool _clearing = false;

  @override
  void initState() {
    super.initState();
    _loadCloseapply();
    _loadCacheSize();
  }

  Future<void> _loadCacheSize() async {
    final bytes = await ImageDiskCache.instance.diskSize();
    if (!mounted) return;
    setState(() => _cacheBytes = bytes);
  }

  Future<void> _clearCache() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('清除图片缓存'),
        content: const Text('将删除已缓存的头像与动态图片，下次显示时重新下载。聊天记录不受影响。'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('清除'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    setState(() => _clearing = true);
    await ImageDiskCache.instance.clear();
    await _loadCacheSize();
    if (!mounted) return;
    setState(() => _clearing = false);
    showSettingsToast(context, '图片缓存已清除');
  }

  /// 读取「拒绝陌生人加好友」开关（服务端）。
  Future<void> _loadCloseapply() async {
    try {
      final v = await ref.read(chatServiceProvider).closeapplyEnabled();
      if (!mounted) return;
      setState(() {
        _closeapply = v;
        _closeapplyLoaded = true;
      });
    } catch (_) {
      // 拉取失败：开关不可交互，避免误导
      if (mounted) setState(() => _closeapplyLoaded = true);
    }
  }

  Future<void> _toggleCloseapply(bool value) async {
    setState(() => _closeapply = value);
    try {
      await ref.read(chatServiceProvider).setCloseapplyEnabled(on: value);
      if (mounted) {
        showSettingsToast(
          context,
          value ? '已开启：拒绝陌生人加好友' : '已关闭：允许陌生人加好友',
        );
      }
    } catch (e) {
      if (mounted) setState(() => _closeapply = !value);
      if (mounted) showSettingsToast(context, '设置失败: $e');
    }
  }

  /// 字节数转人类可读（缓存占用那行用）。
  static String _humanBytes(int bytes) {
    if (bytes < 1024) return '$bytes B';
    if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(1)} KB';
    return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
  }

  @override
  Widget build(BuildContext context) {
    final cacheLabel = _cacheBytes == null
        ? '正在统计…'
        : '当前占用 ${_humanBytes(_cacheBytes!)}（头像与动态图片）';

    return Scaffold(
      appBar: AppBar(title: const Text('隐私与数据')),
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: AppSizes.narrowContent),
          child: ListView(
            padding: const EdgeInsets.all(AppSpacing.md),
            children: [
              const SettingsSectionHeader('隐私'),
              SettingsSwitchTile(
                icon: Icons.remove_red_eye_outlined,
                title: '访问主页留下踪迹',
                subtitle: '关闭后，查看他人主页不会出现在对方的访客记录中',
                value: ref.watch(leaveVisitTraceProvider),
                onChanged: (v) =>
                    ref.read(leaveVisitTraceProvider.notifier).set(v),
              ),
              SettingsSwitchTile(
                icon: Icons.person_off_outlined,
                title: '拒绝陌生人加好友',
                subtitle: _closeapplyLoaded
                    ? '开启后陌生人无法添加我为好友'
                    : '读取中…',
                value: _closeapply,
                onChanged: _closeapplyLoaded ? _toggleCloseapply : null,
              ),

              const SettingsSectionHeader('群邀请'),
              SettingsSwitchTile(
                icon: Icons.group_add_outlined,
                title: '允许他人拉我入群',
                subtitle: '关闭后他人邀请将被拒绝',
                value: ref.watch(allowInvitedToGroupProvider),
                onChanged: (v) =>
                    ref.read(allowInvitedToGroupProvider.notifier).set(v),
              ),
              SettingsSwitchTile(
                icon: Icons.group_add_outlined,
                title: '自动加入被邀请的群',
                subtitle: '开启后收到邀请将自动进群',
                value: ref.watch(allowAutoJoinGroupProvider),
                onChanged: (v) =>
                    ref.read(allowAutoJoinGroupProvider.notifier).set(v),
              ),

              const SettingsSectionHeader('数据'),
              SettingsNavTile(
                icon: Icons.save_alt_outlined,
                title: '聊天记录',
                subtitle: '导出 / 导入聊天数据备份',
                page: const DataPage(),
              ),
              SettingsNavTile(
                icon: Icons.cleaning_services_outlined,
                title: '清除图片缓存',
                subtitle: _clearing ? '正在清除…' : cacheLabel,
                onTap: _clearing ? null : _clearCache,
              ),
              const SizedBox(height: AppSpacing.xl),
            ],
          ),
        ),
      ),
    );
  }
}
