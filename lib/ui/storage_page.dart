/// 存储管理页：数据库占用、保留期清理、按会话清理、VACUUM。
///
/// 只删本地记录（服务端历史仍在），删除前一律二次确认；清理后立即 VACUUM
/// 把页归还给文件系统（SQLite 默认不归还）。
library;

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';

import '../core/models/messages.dart' show ChatSession, ChatSessionType;
import '../state/providers.dart';
import 'theme/app_tokens.dart';
import 'widgets/settings_tiles.dart';

import 'widgets/app_l10n.dart' show l10nOf;

/// 保留期选项（天）。
const List<int> kStorageRetentionDays = <int>[30, 90, 365];

/// 保留期按钮的测试定位 key。
Key storageRetentionKey(int days) => Key('storage_retention_$days');

/// VACUUM 按钮的测试定位 key。
const Key storageVacuumKey = Key('storage_vacuum');

class StoragePage extends ConsumerStatefulWidget {
  const StoragePage({super.key});

  @override
  ConsumerState<StoragePage> createState() => _StoragePageState();
}

class _StoragePageState extends ConsumerState<StoragePage> {
  bool _busy = false;
  bool _loading = true;
  int _dbBytes = 0;
  int _freePages = 0;
  int _messageCount = 0;
  List<({String sessionKey, int count})> _sessions = const [];

  @override
  void initState() {
    super.initState();
    _reload();
  }

  Future<void> _reload() async {
    final db = ref.read(databaseProvider);
    final owner = ref.read(myUinProvider);
    try {
      final stats = await db.storageStats();
      final counts = owner == 0
          ? const <({String sessionKey, int count})>[]
          : await db.messageCountsBySession(owner);
      final total = counts.fold<int>(0, (a, b) => a + b.count);
      if (!mounted) return;
      setState(() {
        _dbBytes = stats.pageCount * stats.pageSize;
        _freePages = stats.freePages;
        _messageCount = total;
        _sessions = counts;
        _loading = false;
      });
    } catch (_) {
      if (mounted) setState(() => _loading = false);
    }
  }

  String get _sizeLabel {
    final mb = _dbBytes / (1024 * 1024);
    return mb < 1
        ? '${(_dbBytes / 1024).toStringAsFixed(0)} KB'
        : '${mb.toStringAsFixed(1)} MB';
  }

  Future<bool> _confirm(String title, String content) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(title),
        content: Text(content),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: Text(l10nOf(context)?.commonCancel ?? '取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: Text(l10nOf(context)?.actionDelete ?? '删除'),
          ),
        ],
      ),
    );
    return ok == true;
  }

  Future<void> _applyRetention(int days) async {
    if (_busy) return;
    final cutoff =
        DateTime.now().millisecondsSinceEpoch ~/ 1000 - days * 24 * 3600;
    final ok = await _confirm(
      l10nOf(context)?.storageKeepLastDays(days) ?? '只保留最近 $days 天',
      l10nOf(context)?.storagePermanentlyDeleteLocalChat(days) ?? '将永久删除本机 $days 天以前的聊天记录（服务端记录不受影响）。此操作无法撤销。',
    );
    if (!ok || !mounted) return;
    setState(() => _busy = true);
    try {
      final db = ref.read(databaseProvider);
      final owner = ref.read(myUinProvider);
      final removed = await db.deleteMessagesBefore(owner, cutoff);
      await db.vacuum();
      // 内存镜像也要同步丢弃，否则已打开的会话仍显示旧记录。
      for (final s in _sessions) {
        final type = s.sessionKey.startsWith('group_')
            ? ChatSessionType.group
            : ChatSessionType.friend;
        final id = int.tryParse(s.sessionKey.split('_').last) ?? 0;
        if (id == 0) continue;
        ref.read(chatServiceProvider).forgetHistory(type, id);
        ref.read(chatBridgeProvider).refresh(type, id);
      }
      await _reload();
      if (mounted) showSettingsToast(context, l10nOf(context)?.storageDeletedRecords(removed) ?? '已删除 $removed 条记录');
    } catch (e) {
      if (mounted) showSettingsToast(context, l10nOf(context)?.storageCleanupFailed(e) ?? '清理失败：$e');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _clearSession(String sessionKey) async {
    if (_busy) return;
    final ok = await _confirm(
      l10nOf(context)?.storageClearConversationHistory ?? '清理会话记录',
      l10nOf(context)?.storageDeleteLocalChatHistory(_nameOf(sessionKey)) ?? '将删除本机「${_nameOf(sessionKey)}」的全部聊天记录（服务端记录不受影响）。此操作无法撤销。',
    );
    if (!ok || !mounted) return;
    setState(() => _busy = true);
    try {
      final db = ref.read(databaseProvider);
      final owner = ref.read(myUinProvider);
      await db.deleteSessionMessages(owner, sessionKey);
      final type = sessionKey.startsWith('group_')
          ? ChatSessionType.group
          : ChatSessionType.friend;
      final id = int.tryParse(sessionKey.split('_').last) ?? 0;
      if (id != 0) {
        ref.read(chatServiceProvider).forgetHistory(type, id);
        ref.read(chatBridgeProvider).refresh(type, id);
      }
      await _reload();
      if (mounted) showSettingsToast(context, l10nOf(context)?.storageConversationHistoryCleared ?? '已清理该会话记录');
    } catch (e) {
      if (mounted) showSettingsToast(context, l10nOf(context)?.storageCleanupFailed(e) ?? '清理失败：$e');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _vacuum() async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      await ref.read(databaseProvider).vacuum();
      await _reload();
      if (mounted) showSettingsToast(context, l10nOf(context)?.storageReclaimedFreeSpace ?? '已回收空闲空间');
    } catch (e) {
      if (mounted) showSettingsToast(context, l10nOf(context)?.storageReclaimFailed(e) ?? '回收失败：$e');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  String _nameOf(String key) {
    final sessions =
        ref.watch(sessionListProvider).asData?.value.sessions ??
        const <ChatSession>[];
    for (final s in sessions) {
      if ('${s.type.name}_${s.id}' == key) return s.name;
    }
    return key;
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(title: Text(l10nOf(context)?.settingsPrivacyStorageManagement ?? '存储管理')),
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: AppSizes.narrowContent),
          child: ListView(
            padding: const EdgeInsets.all(AppSpacing.md),
            children: [
              SettingsSectionHeader(l10nOf(context)?.storageStorageUsed ?? '本机占用'),
              SettingsInfoTile(
                icon: Icons.storage_outlined,
                title: _loading ? l10nOf(context)?.dataCounting ?? '统计中…' : _sizeLabel,
                subtitle:
                    (l10nOf(context)?.storageMessagesAndSessions(
                              _messageCount,
                              _sessions.length,
                            ) ??
                            '$_messageCount 条消息 · ${_sessions.length} 个会话') +
                    (_freePages > 0
                        ? l10nOf(context)?.storageFreePagesNote(_freePages) ??
                            ' · $_freePages 个空闲页可回收'
                        : ''),
              ),
              SettingsNavTile(
                icon: Icons.compress_outlined,
                title: l10nOf(context)?.storageReclaimFreeSpace ?? '回收空闲空间',
                subtitle: _busy ? l10nOf(context)?.storageProcessing ?? '处理中…' : l10nOf(context)?.storageVACUUMRunAfterDeleting ?? 'VACUUM（删除记录后执行）',
                key: storageVacuumKey,
                onTap: _vacuum,
              ),

              SettingsSectionHeader(l10nOf(context)?.storageAutoCleanup ?? '自动清理'),
              for (final days in kStorageRetentionDays)
                SettingsNavTile(
                  icon: Icons.history_toggle_off_outlined,
                  title: l10nOf(context)?.storageKeepLastDays(days) ?? '只保留最近 $days 天',
                  subtitle: l10nOf(context)?.storageDeleteOlderLocalRecords ?? '删除更早的本机记录',
                  key: storageRetentionKey(days),
                  onTap: () => _applyRetention(days),
                ),

              SettingsSectionHeader(l10nOf(context)?.storageClearConversation ?? '按会话清理'),
              if (_sessions.isEmpty && !_loading)
                Padding(
                  padding: const EdgeInsets.all(AppSpacing.md),
                  child: Text(
                    l10nOf(context)?.storageNoLocalChatHistory ?? '本机还没有聊天记录',
                    style: theme.textTheme.bodySmall,
                  ),
                ),
              for (final s in _sessions)
                SettingsNavTile(
                  icon: s.sessionKey.startsWith('group_')
                      ? Icons.groups_outlined
                      : Icons.person_outline,
                  title: _nameOf(s.sessionKey),
                  subtitle: l10nOf(context)?.storageMessagesDotSessions(s.count, s.sessionKey) ?? '${s.count} 条 · ${s.sessionKey}',
                  onTap: () => _clearSession(s.sessionKey),
                ),
              const SizedBox(height: AppSpacing.xl),
            ],
          ),
        ),
      ),
    );
  }
}
