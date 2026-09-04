import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/net/config.dart';
import '../core/storage/settings_store.dart';
import '../state/providers.dart';

/// 设置页：账号信息 / 自动登录 / 服务器地址 / 关于 / 退出登录。
class SettingsPage extends ConsumerStatefulWidget {
  const SettingsPage({super.key});

  @override
  ConsumerState<SettingsPage> createState() => _SettingsPageState();
}

class _SettingsPageState extends ConsumerState<SettingsPage> {
  bool _autoLogin = false;
  bool _autoLoginLoaded = false;

  @override
  void initState() {
    super.initState();
    _loadAutoLogin();
  }

  Future<void> _toggleNotify(bool value) async {
    // 写入共享 provider（即时生效，main.dart 监听同一 provider）
    await ref.read(notifyEnabledProvider.notifier).set(value);
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(value ? '已开启新消息通知' : '已关闭新消息通知'),
          duration: const Duration(seconds: 2),
        ),
      );
    }
  }

  Future<void> _loadAutoLogin() async {
    final settings = ref.read(settingsProvider);
    final v = await settings.getBool(SettingsKeys.autoLogin);
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
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(value ? '已开启自动登录（下次登录将保存凭据）' : '已关闭自动登录'),
          duration: const Duration(seconds: 2),
        ),
      );
    }
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

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final auth = ref.watch(authProvider);

    return Scaffold(
      appBar: AppBar(title: const Text('设置')),
      body: ListView(
        padding: const EdgeInsets.all(12),
        children: [
          // 账号信息
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Row(
                children: [
                  CircleAvatar(
                    radius: 28,
                    backgroundColor: theme.colorScheme.primaryContainer,
                    child: Text(
                      auth.auth?.name.isNotEmpty == true
                          ? auth.auth!.name.characters.first
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
                        Text(
                          auth.auth?.name ?? '',
                          style: theme.textTheme.titleMedium,
                        ),
                        const SizedBox(height: 2),
                        Text(
                          'Uin: ${auth.auth?.uin ?? '-'}',
                          style: theme.textTheme.bodySmall
                              ?.copyWith(color: theme.colorScheme.outline),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 12),
          // 自动登录
          Card(
            child: SwitchListTile(
              secondary: const Icon(Icons.auto_fix_high),
              title: const Text('自动登录'),
              subtitle: const Text('开启后下次启动自动登录（需先登录一次以保存凭据）'),
              value: _autoLogin,
              onChanged: _autoLoginLoaded ? _toggleAutoLogin : null,
            ),
          ),
          const SizedBox(height: 12),
          // 新消息通知
          Card(
            child: SwitchListTile(
              secondary: const Icon(Icons.notifications_active_outlined),
              title: const Text('新消息通知'),
              subtitle: const Text('应用在后台时收到新消息弹出系统通知'),
              value: ref.watch(notifyEnabledProvider),
              onChanged: _toggleNotify,
            ),
          ),
          const SizedBox(height: 12),
          // 服务器信息
          Card(
            child: ListTile(
              leading: const Icon(Icons.dns_outlined),
              title: const Text('服务器地址'),
              subtitle: const Text(kDefaultBase),
            ),
          ),
          const SizedBox(height: 12),
          // 关于
          Card(
            child: ListTile(
              leading: const Icon(Icons.info_outline),
              title: const Text('关于 MnChat'),
              subtitle: const Text('迷你世界外部聊天客户端 · v1.0.0'),
            ),
          ),
          const SizedBox(height: 24),
          // 退出登录
          OutlinedButton.icon(
            onPressed: _logout,
            icon: const Icon(Icons.logout),
            label: const Text('退出登录'),
            style: OutlinedButton.styleFrom(
              foregroundColor: theme.colorScheme.error,
              minimumSize: const Size.fromHeight(48),
            ),
          ),
        ],
      ),
    );
  }
}
