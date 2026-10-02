import 'package:flutter/foundation.dart'
    show TargetPlatform, defaultTargetPlatform;
import 'package:material_ui/material_ui.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/app_info.dart';
import '../core/models/nickname.dart' show plainNickname;
import '../core/net/config.dart';
import '../core/services/app_lock.dart';
import '../core/services/tray_service.dart';
import '../core/storage/settings_store.dart';
import '../state/providers.dart';
import 'data_page.dart';
import 'message_settings_page.dart';
import 'profile_page.dart';
import 'social_sign_page.dart';
import 'theme/app_tokens.dart';
import 'theme_settings_page.dart';
import 'widgets/rich_text_view.dart';

/// 设置页：按「账号 / 通用 / 消息与通知 / 隐私与数据 / 关于」分组。
class SettingsPage extends ConsumerStatefulWidget {
  const SettingsPage({super.key});

  @override
  ConsumerState<SettingsPage> createState() => _SettingsPageState();
}

class _SettingsPageState extends ConsumerState<SettingsPage> {
  bool _autoLogin = false;
  bool _autoLoginLoaded = false;

  /// 桌面端（linux/windows）才显示托盘相关项。
  bool get _isDesktop =>
      defaultTargetPlatform == TargetPlatform.linux ||
      defaultTargetPlatform == TargetPlatform.windows;

  @override
  void initState() {
    super.initState();
    _loadAutoLogin();
  }

  void _toast(String text) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(text), duration: const Duration(seconds: 2)),
    );
  }

  // ── 账号 ──────────────────────────────────────────────────────────────

  Future<void> _loadAutoLogin() async {
    final v = await ref.read(settingsProvider).getBool(SettingsKeys.autoLogin);
    if (!mounted) return;
    setState(() {
      _autoLogin = v;
      _autoLoginLoaded = true;
    });
  }

  Future<void> _toggleAutoLogin(bool value) async {
    setState(() => _autoLogin = value);
    final settings = ref.read(settingsProvider);
    await settings.setBool(SettingsKeys.autoLogin, value);
    if (!value) {
      // 关闭自动登录时清除已存凭据
      await settings.clearCredentials();
    }
    _toast(value ? '已开启自动登录（下次登录将保存凭据）' : '已关闭自动登录');
  }

  Future<void> _logout() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('退出登录'),
        content: const Text('确定要退出当前账号吗？'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('退出'),
          ),
        ],
      ),
    );
    if (confirmed == true && mounted) {
      ref.read(authProvider.notifier).logout();
      Navigator.of(context).popUntil((route) => route.isFirst);
    }
  }

  // ── 通用 ──────────────────────────────────────────────────────────────

  Future<void> _toggleNotify(bool value) async {
    await ref.read(notifyEnabledProvider.notifier).set(value);
    _toast(value ? '已开启新消息通知' : '已关闭新消息通知');
  }

  Future<void> _toggleKeepAlive(bool value) async {
    await ref.read(keepAliveProvider.notifier).set(value);
    _toast(value ? '已开启后台保持连接' : '已关闭后台保持连接');
  }

  Future<void> _pickSortMode() async {
    final current = ref.read(sessionSortModeProvider);
    final picked = await showDialog<SessionSortMode>(
      context: context,
      builder: (ctx) => SimpleDialog(
        title: const Text('会话排序'),
        children: [
          for (final m in SessionSortMode.values)
            SimpleDialogOption(
              onPressed: () => Navigator.pop(ctx, m),
              child: Row(
                children: [
                  Expanded(child: Text(m.label)),
                  if (m == current) const Icon(Icons.check),
                ],
              ),
            ),
        ],
      ),
    );
    if (picked != null) {
      await ref.read(sessionSortModeProvider.notifier).setMode(picked);
    }
  }

  /// 选择免打扰时段（起 / 止两次取时）。
  Future<void> _pickDndWindow() async {
    final cur = ref.read(dndWindowProvider);
    final start = await showTimePicker(
      context: context,
      initialTime: TimeOfDay(hour: cur.start ~/ 60, minute: cur.start % 60),
      helpText: '免打扰开始',
    );
    if (start == null || !mounted) return;
    final end = await showTimePicker(
      context: context,
      initialTime: TimeOfDay(hour: cur.end ~/ 60, minute: cur.end % 60),
      helpText: '免打扰结束',
    );
    if (end == null) return;
    await ref
        .read(dndWindowProvider.notifier)
        .set(DndWindow(start: start.hour * 60 + start.minute, end: end.hour * 60 + end.minute));
    _toast('免打扰时段已更新');
  }

  Future<void> _toggleCloseToTray(bool value) async {
    await ref.read(closeToTrayProvider.notifier).set(value);
    await TrayService.setCloseToTray(value);
    _toast(value ? '关闭窗口时将最小化到托盘' : '关闭窗口时将直接退出');
  }

  // ── 隐私 ──────────────────────────────────────────────────────────────

  /// 输入 PIN（返回 null 表示取消）。
  ///
  /// [hint] 默认按新 PIN 规则提示 6-8 位；校验旧 PIN 时可放宽为 4-8 位
  /// 以兼容历史数据（见 [AppLockService.legacyMinPinLength]）。
  Future<String?> _askPin(String title, {String hint = '6-8 位数字'}) async {
    final ctrl = TextEditingController();
    final result = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(title),
        content: TextField(
          controller: ctrl,
          autofocus: true,
          obscureText: true,
          keyboardType: TextInputType.number,
          maxLength: 8,
          decoration: InputDecoration(
            hintText: hint,
            counterText: '',
          ),
          onSubmitted: (v) => Navigator.pop(ctx, v),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, ctrl.text),
            child: const Text('确定'),
          ),
        ],
      ),
    );
    ctrl.dispose();
    final pin = result?.trim() ?? '';
    return pin.isEmpty ? null : pin;
  }

  /// 设置新 PIN（两次输入一致，且为 6-8 位数字）。
  Future<String?> _askNewPin() async {
    final a = await _askPin('设置应用锁密码');
    if (a == null) return null;
    if (!RegExp(r'^\d{6,8}$').hasMatch(a)) {
      _toast('密码需为 6-8 位数字');
      return null;
    }
    final b = await _askPin('再次输入密码');
    if (b == null) return null;
    if (a != b) {
      _toast('两次输入不一致');
      return null;
    }
    return a;
  }

  Future<bool> _verifyExistingPin(AppLockService service) async {
    final pin = await _askPin('输入应用锁密码', hint: '4-8 位数字');
    if (pin == null) return false;
    if (!await service.verifyPin(pin)) {
      _toast('密码错误');
      return false;
    }
    return true;
  }

  /// 应用锁开关：开启时设置/校验密码，关闭时校验后清除。
  Future<void> _toggleLock(bool value) async {
    final service = AppLockService(ref.read(settingsProvider));
    if (value) {
      if (await service.isPinSet()) {
        if (!mounted || !await _verifyExistingPin(service)) return;
      } else {
        final pin = await _askNewPin();
        if (pin == null) return;
        await service.setPin(pin);
      }
      await ref.read(lockEnabledProvider.notifier).set(true);
      _toast('已开启应用锁');
    } else {
      if (!mounted || !await _verifyExistingPin(service)) return;
      await service.clearPin();
      await ref.read(lockEnabledProvider.notifier).set(false);
      _toast('已关闭应用锁');
    }
  }

  // ── 构建 ──────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final auth = ref.watch(authProvider);

    return Scaffold(
      appBar: AppBar(title: const Text('设置')),
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: AppSizes.narrowContent),
          child: ListView(
            padding: const EdgeInsets.all(12),
            children: [
              // ── 账号 ────────────────────────────────────────────────
              _SectionHeader('账号'),
              _accountCard(theme, auth),
              _navCard(
                icon: Icons.badge_outlined,
                title: '个人资料',
                subtitle: '查看头像 / 修改昵称 / 头像框',
                page: const ProfilePage(),
              ),
              _navCard(
                icon: Icons.auto_awesome,
                title: '交友标签',
                subtitle: '设置我的个性签名（想要/喜欢）',
                page: const SocialSignPage(),
              ),
              _switchCard(
                icon: Icons.auto_fix_high,
                title: '自动登录',
                subtitle: '开启后下次启动自动登录（需先登录一次以保存凭据）',
                value: _autoLogin,
                onChanged: _autoLoginLoaded ? _toggleAutoLogin : null,
              ),

              // ── 通用 ────────────────────────────────────────────────
              _SectionHeader('通用'),
              _navCard(
                icon: Icons.palette_outlined,
                title: '主题显示设置',
                subtitle: '明暗模式 / 强调色 / 聊天字号',
                page: const ThemeSettingsPage(),
              ),
              Card(
                child: ListTile(
                  leading: const Icon(Icons.sort),
                  title: const Text('会话排序'),
                  subtitle: Text(ref.watch(sessionSortModeProvider).label),
                  trailing: const Icon(Icons.chevron_right),
                  onTap: _pickSortMode,
                ),
              ),
              _navCard(
                icon: Icons.quickreply_outlined,
                title: '快捷短语',
                subtitle: '发送消息时快捷插入',
                page: const MessageSettingsPage(),
              ),
              _switchCard(
                icon: Icons.animation,
                title: '头像框动画',
                subtitle: '关闭后仅显示静态头像框，省电省流',
                value: ref.watch(animatedFramesProvider),
                onChanged: (v) =>
                    ref.read(animatedFramesProvider.notifier).set(v),
              ),
              if (_isDesktop)
                _switchCard(
                  icon: Icons.close_fullscreen_outlined,
                  title: '关闭到托盘',
                  // 托盘注册失败时（Linux 上没跑 StatusNotifierWatcher）启动阶段已
                  // 自动关掉它；这里把原因写出来，否则用户会以为是设置没保存。
                  subtitle: TrayService.trayAvailable
                      ? '关闭窗口时最小化到系统托盘而非退出'
                      : '当前桌面没有可用的系统托盘，关闭窗口会直接退出（已自动关闭）',
                  value: ref.watch(closeToTrayProvider),
                  // 没有托盘就不允许打开：否则关窗后应用既不可见也召不回来。
                  onChanged: TrayService.trayAvailable
                      ? _toggleCloseToTray
                      : null,
                ),

              // ── 消息与通知 ──────────────────────────────────────────
              _SectionHeader('消息与通知'),
              _switchCard(
                icon: Icons.notifications_active_outlined,
                title: '新消息通知',
                subtitle: '应用在后台时收到新消息弹出系统通知',
                value: ref.watch(notifyEnabledProvider),
                onChanged: _toggleNotify,
              ),
              _switchCard(
                icon: Icons.visibility_off_outlined,
                title: '通知隐藏内容',
                subtitle: '锁屏 / 通知栏只提示有新消息，不显示正文',
                value: ref.watch(hideNotifyContentProvider),
                onChanged: (v) =>
                    ref.read(hideNotifyContentProvider.notifier).set(v),
              ),
              _switchCard(
                icon: Icons.nightlight_outlined,
                title: '免打扰时段',
                subtitle: ref.watch(dndWindowProvider).label,
                value: ref.watch(dndEnabledProvider),
                onChanged: (v) => ref.read(dndEnabledProvider.notifier).set(v),
                onTap: _pickDndWindow,
              ),
              _switchCard(
                icon: Icons.mark_chat_read_outlined,
                title: '进入会话自动已读',
                subtitle: '打开会话即清除未读标记',
                value: ref.watch(autoMarkReadProvider),
                onChanged: (v) => ref.read(autoMarkReadProvider.notifier).set(v),
              ),
              _switchCard(
                icon: Icons.keyboard_return_outlined,
                title: '回车发送',
                subtitle: '桌面端按 Enter 发送，Shift+Enter 换行',
                value: ref.watch(sendOnEnterProvider),
                onChanged: (v) => ref.read(sendOnEnterProvider.notifier).set(v),
              ),
              _switchCard(
                icon: Icons.sync_lock_outlined,
                title: '后台保持连接',
                subtitle: '由前台服务维持长连接，后台也能收到新消息',
                value: ref.watch(keepAliveProvider),
                onChanged: _toggleKeepAlive,
              ),

              // ── 隐私与数据 ──────────────────────────────────────────
              _SectionHeader('隐私与数据'),
              _switchCard(
                icon: Icons.lock_outline,
                title: '应用锁',
                subtitle: '启动 / 回前台时需输入密码解锁',
                value: ref.watch(lockEnabledProvider),
                onChanged: _toggleLock,
              ),
              _switchCard(
                icon: Icons.remove_red_eye_outlined,
                title: '访问主页留下踪迹',
                subtitle: '关闭后，查看他人主页不会出现在对方的访客记录中',
                value: ref.watch(leaveVisitTraceProvider),
                onChanged: (v) =>
                    ref.read(leaveVisitTraceProvider.notifier).set(v),
              ),
              _navCard(
                icon: Icons.save_alt_outlined,
                title: '聊天记录',
                subtitle: '导出 / 导入聊天数据备份',
                page: const DataPage(),
              ),

              // ── 关于 ────────────────────────────────────────────────
              _SectionHeader('关于'),
              Card(
                child: ListTile(
                  leading: const Icon(Icons.info_outline),
                  title: const Text('关于 MnChat'),
                  subtitle: Text(
                    '迷你世界外部聊天客户端 · v$kAppVersion · '
                    '客户端 $kClientVersionStr ($kCltVersion)',
                  ),
                ),
              ),
              Card(
                child: ListTile(
                  leading: const Icon(Icons.article_outlined),
                  title: const Text('开源许可'),
                  trailing: const Icon(Icons.chevron_right),
                  onTap: () => showLicensePage(
                    context: context,
                    applicationName: 'MnChat',
                    applicationVersion: kAppVersion,
                  ),
                ),
              ),
              const SizedBox(height: 16),
              OutlinedButton.icon(
                onPressed: _logout,
                icon: const Icon(Icons.logout),
                label: const Text('退出登录'),
                style: OutlinedButton.styleFrom(
                  foregroundColor: theme.colorScheme.error,
                  minimumSize: const Size.fromHeight(48),
                ),
              ),
              const SizedBox(height: 24),
            ],
          ),
        ),
      ),
    );
  }

  // ── 组件 ──────────────────────────────────────────────────────────────

  Widget _accountCard(ThemeData theme, AuthState auth) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Row(
          children: [
            CircleAvatar(
              radius: 28,
              backgroundColor: theme.colorScheme.primaryContainer,
              child: Text(
                plainNickname(auth.auth?.name).isNotEmpty
                    ? plainNickname(auth.auth?.name).characters.first
                    : '?',
                style: TextStyle(
                  fontSize: 22,
                  color: theme.colorScheme.onPrimaryContainer,
                ),
              ),
            ),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  RichTextView(
                    auth.auth?.name ?? '',
                    style: theme.textTheme.titleMedium,
                  ),
                  const SizedBox(height: 2),
                  Text(
                    'Uin: ${auth.auth?.uin ?? '-'}',
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
    );
  }

  Widget _switchCard({
    required IconData icon,
    required String title,
    required String subtitle,
    required bool value,
    required ValueChanged<bool>? onChanged,
    VoidCallback? onTap,
  }) {
    // 用 ListTile + 尾部 Switch（而非 SwitchListTile）以支持整行 onTap。
    return Card(
      child: ListTile(
        leading: Icon(icon),
        title: Text(title),
        subtitle: Text(subtitle),
        onTap: onTap,
        trailing: Switch(value: value, onChanged: onChanged),
      ),
    );
  }

  Widget _navCard({
    required IconData icon,
    required String title,
    required String subtitle,
    required Widget page,
  }) {
    return Card(
      child: ListTile(
        leading: Icon(icon),
        title: Text(title),
        subtitle: Text(subtitle),
        trailing: const Icon(Icons.chevron_right),
        onTap: () => Navigator.of(
          context,
        ).push(MaterialPageRoute(builder: (_) => page)),
      ),
    );
  }
}

/// 分组标题。
class _SectionHeader extends StatelessWidget {
  const _SectionHeader(this.title);

  final String title;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(8, 16, 8, 6),
      child: Text(
        title,
        style: Theme.of(context).textTheme.labelLarge?.copyWith(
          color: Theme.of(context).colorScheme.primary,
        ),
      ),
    );
  }
}
