import 'package:material_ui/material_ui.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/storage/settings_store.dart';
import '../state/providers.dart';
import 'widgets/avatar_view.dart';
import 'widgets/rich_text_view.dart';

/// 登录/切换账号页：选择已保存账号一键登录；也可添加新账号。
///
/// - 有已保存账号 → 默认展示账号列表，点选即登录（不再手动输入）；
/// - "添加账号" → 展开 uin+密码 表单登录，成功后自动加入列表；
/// - 无已保存账号 → 直接显示添加表单。
class LoginPage extends ConsumerStatefulWidget {
  const LoginPage({super.key});

  @override
  ConsumerState<LoginPage> createState() => _LoginPageState();
}

class _LoginPageState extends ConsumerState<LoginPage> {
  List<SavedAccount> _accounts = [];
  bool _loaded = false;
  bool _showForm = false;
  bool _busy = false;

  final _uinCtrl = TextEditingController();
  final _pwdCtrl = TextEditingController();
  final _formKey = GlobalKey<FormState>();
  bool _showPwd = false;
  bool _autoLogin = false;
  bool _autoLoginLoaded = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final settings = ref.read(settingsProvider);
    final v = await settings.getBool(SettingsKeys.autoLogin);
    final accounts = await settings.listAccounts();
    if (!mounted) return;
    setState(() {
      _autoLogin = v;
      _autoLoginLoaded = true;
      _accounts = accounts;
      _loaded = true;
      // 无已存账号 → 直接进添加表单
      _showForm = accounts.isEmpty;
    });
  }

  @override
  void dispose() {
    _uinCtrl.dispose();
    _pwdCtrl.dispose();
    super.dispose();
  }

  Future<void> _login(int uin, String password, {String? name}) async {
    if (_busy) return;
    setState(() => _busy = true);
    final ok = await ref
        .read(authProvider.notifier)
        .login(uin: uin, password: password, name: name);
    if (!mounted) return;
    setState(() => _busy = false);
    if (!ok) {
      final error = ref.read(authProvider).error;
      final scheme = Theme.of(context).colorScheme;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            error ?? '登录失败',
            style: TextStyle(color: scheme.onError),
          ),
          backgroundColor: scheme.error,
        ),
      );
    }
    // 登录成功：home 由 auth.isLoggedIn 驱动切到主界面，本页自动销毁
  }

  Future<void> _submitForm() async {
    if (!_formKey.currentState!.validate()) return;
    final uin = int.tryParse(_uinCtrl.text.trim());
    if (uin == null) return;
    await _login(uin, _pwdCtrl.text);
  }

  Future<void> _removeAccount(SavedAccount acc) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('移除账号'),
        content: Text('移除 ${acc.name ?? '${acc.uin}'}？\n（不影响游戏端账号）'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('移除'),
          ),
        ],
      ),
    );
    if (ok != true) return;
    await ref.read(settingsProvider).removeAccount(acc.uin);
    final accounts = await ref.read(settingsProvider).listAccounts();
    if (mounted) {
      setState(() => _accounts = accounts);
    }
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
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(20),
              ),
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Icon(
                      Icons.chat_bubble,
                      size: 48,
                      color: theme.colorScheme.primary,
                    ),
                    const SizedBox(height: 8),
                    Text(
                      'MnChat',
                      textAlign: TextAlign.center,
                      style: theme.textTheme.headlineSmall,
                    ),
                    Text(
                      '迷你世界外部聊天 · 选择账号登录',
                      textAlign: TextAlign.center,
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: theme.colorScheme.outline,
                      ),
                    ),
                    const SizedBox(height: 20),
                    if (!_loaded)
                      const Padding(
                        padding: EdgeInsets.all(24),
                        child: Center(child: CircularProgressIndicator()),
                      )
                    else if (_showForm)
                      _buildForm(auth, theme)
                    else
                      _buildAccountList(theme),
                    const SizedBox(height: 8),
                    if (_loaded && !_showForm)
                      TextButton.icon(
                        onPressed: auth.isBusy
                            ? null
                            : () => setState(() => _showForm = true),
                        icon: const Icon(Icons.person_add_alt_1),
                        label: const Text('添加账号'),
                      ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  /// 账号列表：点选即登录。
  Widget _buildAccountList(ThemeData theme) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (_accounts.isEmpty) ...[
          const SizedBox(height: 8),
          Text(
            '还没有保存的账号',
            textAlign: TextAlign.center,
            style: theme.textTheme.bodyMedium,
          ),
          const SizedBox(height: 4),
        ] else ...[
          const Text('选择账号', style: TextStyle(fontWeight: FontWeight.w600)),
          const SizedBox(height: 8),
          ..._accounts.map((acc) {
            final name = acc.name != null && acc.name!.isNotEmpty
                ? acc.name!
                : '${acc.uin}';
            return Card(
              margin: const EdgeInsets.only(bottom: 8),
              elevation: 0,
              color: theme.colorScheme.surfaceContainerHighest,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ),
              child: ListTile(
                contentPadding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 2,
                ),
                leading: AvatarView(name: name, radius: 20),
                title: RichTextView(
                  name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                subtitle: Text('迷你号 ${acc.uin}'),
                trailing: IconButton(
                  tooltip: '移除',
                  icon: Icon(
                    Icons.delete_outline,
                    size: 20,
                    color: theme.colorScheme.outline,
                  ),
                  onPressed: () => _removeAccount(acc),
                ),
                onTap: (_busy)
                    ? null
                    : () => _login(acc.uin, acc.password, name: acc.name),
              ),
            );
          }),
        ],
      ],
    );
  }

  /// 添加账号表单。
  Widget _buildForm(AuthState authState, ThemeData theme) {
    return Form(
      key: _formKey,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          TextFormField(
            controller: _uinCtrl,
            keyboardType: TextInputType.number,
            decoration: const InputDecoration(
              labelText: 'Uin / 迷你号',
              prefixIcon: Icon(Icons.tag),
            ),
            validator: (v) =>
                (v == null ||
                    v.trim().isEmpty ||
                    int.tryParse(v.trim()) == null)
                ? '请输入有效的迷你号'
                : null,
          ),
          const SizedBox(height: 12),
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
            onFieldSubmitted: (_) => _submitForm(),
          ),
          const SizedBox(height: 4),
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
          const SizedBox(height: 8),
          FilledButton.icon(
            onPressed: (authState.isBusy || _busy) ? null : _submitForm,
            icon: _busy
                ? const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.login),
            label: Text(_busy ? '登录中…' : '登录并添加'),
          ),
          if (_accounts.isNotEmpty) ...[
            const SizedBox(height: 8),
            TextButton(
              onPressed: () => setState(() => _showForm = false),
              child: const Text('返回账号列表'),
            ),
          ],
        ],
      ),
    );
  }
}
