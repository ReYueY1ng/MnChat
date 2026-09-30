/// 社交签名（交友标签）设置页。
///
/// 读取我的当前签名（get_social_sign），选择"想要…"（social_lab）与
/// "喜欢…"（game_lab）标签，保存走 set_social_lab。标签文本映射来自
/// 本地内置表（对齐游戏 FriendShipDeclaration 常见项）。
library;

import 'package:material_ui/material_ui.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/services/social_sign.dart';
import '../state/providers.dart';

class SocialSignPage extends ConsumerStatefulWidget {
  const SocialSignPage({super.key});

  @override
  ConsumerState<SocialSignPage> createState() => _SocialSignPageState();
}

class _SocialSignPageState extends ConsumerState<SocialSignPage> {
  SocialSignClient? _client;
  int _socialLab = 0;
  int _gameLab = 0;
  bool _loading = true;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    _init();
  }

  void _init() {
    final auth = ref.read(chatServiceProvider).auth;
    if (auth == null) return;
    _client = SocialSignClient(uin: auth.uin, s2: auth.s2, s2t: auth.s2t);
    _load();
  }

  Future<void> _load() async {
    final client = _client;
    if (client == null) return;
    try {
      final decl = await client.getSocialSign(ref.read(myUinProvider));
      if (!mounted) return;
      setState(() {
        _socialLab = decl?.socialLab ?? 0;
        _gameLab = decl?.gameLab ?? 0;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _loading = false;
      });
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('加载失败: $e')),
      );
    }
  }

  Future<void> _save() async {
    final client = _client;
    if (client == null || _saving) return;
    setState(() => _saving = true);
    try {
      final ok = await client.setSocialLab(
        socialLab: _socialLab,
        gameLab: _gameLab,
      );
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(ok ? '已保存' : '保存失败')),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('保存失败: $e')),
      );
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    // 「想要…/喜欢…」的选项由服务端 visual-cfg 下发；未加载完先用内置表兜底。
    final catalog =
        ref.watch(declarationCatalogProvider).asData?.value ??
        DeclarationCatalog.empty;
    return Scaffold(
      appBar: AppBar(
        title: const Text('交友标签'),
        actions: [
          TextButton(
            onPressed: _loading || _saving ? null : _save,
            child: const Text('保存'),
          ),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              padding: const EdgeInsets.all(16),
              children: [
                const Text('想要…', style: TextStyle(fontWeight: FontWeight.w600)),
                const SizedBox(height: 8),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    ChoiceChip(
                      label: const Text('不设置'),
                      selected: _socialLab == 0,
                      onSelected: (_) => setState(() => _socialLab = 0),
                    ),
                    for (final (id, tag) in catalog.socialOptions)
                      ChoiceChip(
                        label: Text(tag),
                        selected: _socialLab == id,
                        onSelected: (_) => setState(() => _socialLab = id),
                      ),
                  ],
                ),
                const SizedBox(height: 24),
                const Text('喜欢…', style: TextStyle(fontWeight: FontWeight.w600)),
                const SizedBox(height: 8),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    ChoiceChip(
                      label: const Text('不设置'),
                      selected: _gameLab == 0,
                      onSelected: (_) => setState(() => _gameLab = 0),
                    ),
                    for (final (id, tag) in catalog.gameOptions)
                      ChoiceChip(
                        label: Text(tag),
                        selected: _gameLab == id,
                        onSelected: (_) => setState(() => _gameLab = id),
                      ),
                  ],
                ),
                const SizedBox(height: 32),
                Card(
                  child: ListTile(
                    leading: const Icon(Icons.auto_awesome),
                    title: const Text('我的名片'),
                    subtitle: Text(
                      formatDeclaration(
                        _socialLab,
                        _gameLab,
                        catalog: catalog,
                      ).isEmpty
                          ? '未设置'
                          : formatDeclaration(
                              _socialLab,
                              _gameLab,
                              catalog: catalog,
                            ),
                    ),
                  ),
                ),
              ],
            ),
    );
  }
}
