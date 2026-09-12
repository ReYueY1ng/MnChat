/// 消息设置页 —— 快捷短语管理。
///
/// 快捷短语（对齐游戏 SecretQuickMsg 本地 kv）：发送时的快捷 chip，
/// 可新增/删除。会话级"免打扰/置顶"在会话列表长按菜单中设置。
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../state/providers.dart';

class MessageSettingsPage extends ConsumerStatefulWidget {
  const MessageSettingsPage({super.key});

  @override
  ConsumerState<MessageSettingsPage> createState() => _MessageSettingsPageState();
}

class _MessageSettingsPageState extends ConsumerState<MessageSettingsPage> {
  List<String> _phrases = [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final settings = ref.read(settingsProvider);
    final list = await settings.quickPhrases();
    if (!mounted) return;
    setState(() {
      _phrases = list;
      _loading = false;
    });
  }

  Future<void> _add() async {
    final controller = TextEditingController();
    final text = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('新增快捷短语'),
        content: TextField(
          controller: controller,
          autofocus: true,
          maxLength: 20,
          decoration: const InputDecoration(hintText: '输入短语内容'),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, controller.text.trim()),
            child: const Text('添加'),
          ),
        ],
      ),
    );
    if (text == null || text.isEmpty) return;
    final settings = ref.read(settingsProvider);
    final ok = await settings.addQuickPhrase(text);
    if (!mounted) return;
    if (!ok) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('短语已存在或内容无效')),
      );
    }
    await _load();
  }

  Future<void> _remove(String text) async {
    final settings = ref.read(settingsProvider);
    await settings.removeQuickPhrase(text);
    await _load();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(
        title: const Text('消息设置'),
        actions: [
          IconButton(
            tooltip: '新增短语',
            icon: const Icon(Icons.add),
            onPressed: _add,
          ),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              padding: const EdgeInsets.all(16),
              children: [
                Text('快捷短语', style: theme.textTheme.titleMedium),
                const SizedBox(height: 4),
                Text(
                  '发送消息时快捷插入（对齐游戏内置 SecretQuickMsg）',
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.outline,
                  ),
                ),
                const SizedBox(height: 12),
                if (_phrases.isEmpty)
                  const Center(child: Text('暂无短语，点击右上角新增'))
                else
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      for (final p in _phrases)
                        InputChip(
                          label: Text(p),
                          onDeleted: () => _remove(p),
                        ),
                    ],
                  ),
                const Divider(height: 40),
                Text('会话管理', style: theme.textTheme.titleMedium),
                const SizedBox(height: 4),
                Text(
                  '在会话列表长按某条会话可设置「免打扰 / 置顶」',
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.outline,
                  ),
                ),
              ],
            ),
    );
  }
}
