/// 黑名单管理页 —— handle_black(加入/移除) + clear_black(清空)。
///
/// 数据来源：好友会话中 relation&64 的条目（黑名单好友仍在会话缓存里，
/// 但好友页会过滤掉）。此处列出全部黑名单好友，支持移出/清空/添加。
library;

import 'package:material_ui/material_ui.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/models/messages.dart';
import '../core/services/chat_service.dart' show SessionSnapshot;
import '../state/providers.dart';
import 'widgets/avatar_view.dart';
import 'widgets/rich_text_view.dart';

class BlacklistPage extends ConsumerStatefulWidget {
  const BlacklistPage({super.key});

  @override
  ConsumerState<BlacklistPage> createState() => _BlacklistPageState();
}

class _BlacklistPageState extends ConsumerState<BlacklistPage> {
  bool _busy = false;

  /// 从会话快照中收集黑名单好友（relation & 64）。
  List<ChatSession> _black(SessionSnapshot? snap) {
    if (snap == null) return const [];
    return snap.sessions
        .where(
          (s) => s.type == ChatSessionType.friend && (s.relation & 64) != 0,
        )
        .toList()
      ..sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));
  }

  Future<void> _remove(ChatSession s) async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      await ref.read(chatServiceProvider).removeBlacklist(s.id);
      _toast('已移出黑名单');
    } catch (e) {
      _toast('操作失败: $e');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _clear() async {
    if (_busy) return;
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('清空黑名单'),
        content: const Text('确定移出黑名单中的全部好友吗？'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('确定'),
          ),
        ],
      ),
    );
    if (ok != true) return;
    setState(() => _busy = true);
    try {
      await ref.read(chatServiceProvider).clearBlacklist();
      _toast('已清空');
    } catch (e) {
      _toast('清空失败: $e');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _add() async {
    final controller = TextEditingController();
    final result = await showDialog<int>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('加入黑名单'),
        content: TextField(
          controller: controller,
          keyboardType: TextInputType.number,
          decoration: const InputDecoration(
            labelText: '迷你号 (Uin)',
            hintText: '输入要拉黑的迷你号',
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () =>
                Navigator.pop(ctx, int.tryParse(controller.text.trim()) ?? 0),
            child: const Text('确定'),
          ),
        ],
      ),
    );
    if (result == null || result <= 0) return;
    if (_busy) return;
    setState(() => _busy = true);
    try {
      await ref.read(chatServiceProvider).addBlacklist(result);
      _toast('已加入黑名单');
    } catch (e) {
      _toast('操作失败: $e');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  void _toast(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
  }

  @override
  Widget build(BuildContext context) {
    final snap = ref.watch(sessionListProvider).asData?.value;
    final list = _black(snap);
    return Scaffold(
      appBar: AppBar(
        title: const Text('黑名单'),
        actions: [
          IconButton(
            tooltip: '加入黑名单',
            icon: const Icon(Icons.person_add_disabled_outlined),
            onPressed: _busy ? null : _add,
          ),
          if (list.isNotEmpty)
            IconButton(
              tooltip: '清空',
              icon: const Icon(Icons.delete_sweep_outlined),
              onPressed: _busy ? null : _clear,
            ),
        ],
      ),
      body: list.isEmpty
          ? const Center(child: Text('暂无黑名单好友'))
          : RefreshIndicator(
              onRefresh: () async {},
              child: ListView.separated(
                itemCount: list.length,
                separatorBuilder: (_, _) => const Divider(height: 1),
                itemBuilder: (context, i) {
                  final s = list[i];
                  final name = s.name.isNotEmpty ? s.name : '${s.id}';
                  return ListTile(
                    leading: AvatarView(name: name, radius: 24),
                    title: RichTextView(name),
                    subtitle: Text('迷你号 ${s.id}'),
                    trailing: _busy
                        ? const SizedBox(
                            width: 28,
                            height: 28,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : IconButton(
                            tooltip: '移出黑名单',
                            icon: const Icon(Icons.person_remove_outlined),
                            onPressed: () => _remove(s),
                          ),
                  );
                },
              ),
            ),
    );
  }
}
