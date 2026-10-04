/// 设置 · 账号与安全子页。
///
/// 内容：个人资料 / 交友标签两个入口，自动登录与应用锁两个开关。
/// 应用锁的 PIN 交互（设置 / 校验 / 关闭）也在这里，占原设置页约 90 行。
library;

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';

import '../core/services/app_lock.dart';
import '../core/storage/settings_store.dart' show SettingsKeys;
import '../state/providers.dart';
import 'profile_page.dart';
import 'social_sign_page.dart';
import 'theme/app_tokens.dart';
import 'widgets/settings_tiles.dart';

class SettingsAccountPage extends ConsumerStatefulWidget {
  const SettingsAccountPage({super.key});

  @override
  ConsumerState<SettingsAccountPage> createState() =>
      _SettingsAccountPageState();
}

class _SettingsAccountPageState extends ConsumerState<SettingsAccountPage> {
  bool _autoLogin = false;
  bool _autoLoginLoaded = false;

  @override
  void initState() {
    super.initState();
    _loadAutoLogin();
  }

  void _toast(String text) => showSettingsToast(context, text);

  // ── 自动登录 ───────────────────────────────────────────────────────────

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

  // ── 应用锁 ─────────────────────────────────────────────────────────────

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
          decoration: InputDecoration(hintText: hint, counterText: ''),
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

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('账号与安全')),
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: AppSizes.narrowContent),
          child: ListView(
            padding: const EdgeInsets.all(AppSpacing.md),
            children: [
              const SettingsSectionHeader('资料'),
              SettingsNavTile(
                icon: Icons.badge_outlined,
                title: '个人资料',
                subtitle: '查看头像 / 修改昵称 / 头像框',
                page: const ProfilePage(),
              ),
              SettingsNavTile(
                icon: Icons.auto_awesome,
                title: '交友标签',
                subtitle: '设置我的个性签名（想要/喜欢）',
                page: const SocialSignPage(),
              ),

              const SettingsSectionHeader('安全'),
              SettingsSwitchTile(
                icon: Icons.lock_outline,
                title: '应用锁',
                subtitle: '启动 / 回前台时需输入密码解锁',
                value: ref.watch(lockEnabledProvider),
                onChanged: _toggleLock,
              ),
              SettingsSwitchTile(
                icon: Icons.auto_fix_high,
                title: '自动登录',
                subtitle: '开启后下次启动自动登录（需先登录一次以保存凭据）',
                value: _autoLogin,
                onChanged: _autoLoginLoaded ? _toggleAutoLogin : null,
              ),
              const SizedBox(height: AppSpacing.xl),
            ],
          ),
        ),
      ),
    );
  }
}
