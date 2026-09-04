import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/storage/settings_store.dart';
import '../state/providers.dart';

/// 登录页：uin + 密码 → login_v3。支持"下次自动登录"。
class LoginPage extends ConsumerStatefulWidget {
  const LoginPage({super.key});

  @override
  ConsumerState<LoginPage> createState() => _LoginPageState();
}

class _LoginPageState extends ConsumerState<LoginPage> {
  final _uinCtrl = TextEditingController();
  final _pwdCtrl = TextEditingController();
  final _formKey = GlobalKey<FormState>();
  bool _showPwd = false;
  bool _autoLogin = false;
  bool _autoLoginLoaded = false;

  @override
  void initState() {
    super.initState();
    _loadAutoLoginPref();
  }

  Future<void> _loadAutoLoginPref() async {
    final settings = ref.read(settingsProvider);
    final v = await settings.getBool(SettingsKeys.autoLogin);
    if (!mounted) return;
    setState(() {
      _autoLogin = v;
      _autoLoginLoaded = true;
    });
  }

  @override
  void dispose() {
    _uinCtrl.dispose();
    _pwdCtrl.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;
    final uin = int.tryParse(_uinCtrl.text.trim());
    if (uin == null) return;
    final ok = await ref
        .read(authProvider.notifier)
        .login(uin: uin, password: _pwdCtrl.text);
    if (!ok && mounted) {
      final error = ref.read(authProvider).error;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(error ?? '登录失败'), backgroundColor: Colors.red.shade400),
      );
    }
    // 登录成功：authProvider 已按 _autoLogin 保存凭据（见 AuthNotifier.login）
  }

  @override
  Widget build(BuildContext context) {
    final auth = ref.watch(authProvider);
    final theme = Theme.of(context);

    return Scaffold(
      body: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 420),
            child: Card(
              elevation: 2,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
              child: Padding(
                padding: const EdgeInsets.all(28),
                child: Form(
                  key: _formKey,
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Icon(Icons.chat_bubble, size: 56, color: theme.colorScheme.primary),
                      const SizedBox(height: 12),
                      Text(
                        'MnChat',
                        textAlign: TextAlign.center,
                        style: theme.textTheme.headlineMedium,
                      ),
                      Text(
                        '迷你世界外部聊天 · 好友/群聊',
                        textAlign: TextAlign.center,
                        style: theme.textTheme.bodySmall
                            ?.copyWith(color: theme.colorScheme.outline),
                      ),
                      const SizedBox(height: 28),
                      TextFormField(
                        controller: _uinCtrl,
                        keyboardType: TextInputType.number,
                        decoration: const InputDecoration(
                          labelText: 'Uin / 迷你号',
                          prefixIcon: Icon(Icons.tag),
                        ),
                        validator: (v) =>
                            (v == null || v.trim().isEmpty || int.tryParse(v.trim()) == null)
                                ? '请输入有效的迷你号'
                                : null,
                      ),
                      const SizedBox(height: 16),
                      TextFormField(
                        controller: _pwdCtrl,
                        obscureText: !_showPwd,
                        decoration: InputDecoration(
                          labelText: '密码',
                          prefixIcon: const Icon(Icons.lock_outline),
                          suffixIcon: IconButton(
                            icon: Icon(_showPwd ? Icons.visibility_off : Icons.visibility),
                            onPressed: () => setState(() => _showPwd = !_showPwd),
                          ),
                        ),
                        validator: (v) => (v == null || v.isEmpty) ? '请输入密码' : null,
                        onFieldSubmitted: (_) => _submit(),
                      ),
                      const SizedBox(height: 8),
                      CheckboxListTile(
                        contentPadding: EdgeInsets.zero,
                        controlAffinity: ListTileControlAffinity.leading,
                        dense: true,
                        title: const Text('下次自动登录'),
                        value: _autoLogin,
                        onChanged: _autoLoginLoaded
                            ? (v) async {
                                setState(() => _autoLogin = v ?? false);
                                await ref
                                    .read(settingsProvider)
                                    .setBool(SettingsKeys.autoLogin, v ?? false);
                              }
                            : null,
                      ),
                      const SizedBox(height: 16),
                      FilledButton.icon(
                        onPressed: auth.isBusy ? null : _submit,
                        icon: auth.isBusy
                            ? const SizedBox(
                                width: 18,
                                height: 18,
                                child: CircularProgressIndicator(strokeWidth: 2),
                              )
                            : const Icon(Icons.login),
                        label: Text(auth.isBusy ? '登录中…' : '登录'),
                      ),
                      if (auth.error != null) ...[
                        const SizedBox(height: 12),
                        Text(
                          auth.error!,
                          style: TextStyle(color: theme.colorScheme.error, fontSize: 12),
                          textAlign: TextAlign.center,
                        ),
                      ],
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
