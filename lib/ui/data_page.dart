/// 聊天记录页 —— 导出 / 导入本地聊天数据。
///
/// 导出：把当前账号的消息 / 会话 / 好友写成 JSON 文件；
/// 导入：从 JSON 备份文件增量合并（跳过已存在的记录，不覆盖本地数据）。
library;

import 'dart:typed_data';

import 'package:drift/drift.dart' show countAll;
import 'package:file_picker/file_picker.dart';
import 'package:material_ui/material_ui.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/services/backup.dart';
import '../core/services/backup_crypto.dart' show isEncryptedBackup;
import '../core/storage/app_database.dart' show AppDatabase;
import '../state/providers.dart';
import 'theme/app_tokens.dart';

import 'widgets/app_l10n.dart' show l10nOf;

/// 数据备份页：导出 / 导入聊天记录。
class DataPage extends ConsumerStatefulWidget {
  const DataPage({super.key});

  @override
  ConsumerState<DataPage> createState() => _DataPageState();
}

class _DataPageState extends ConsumerState<DataPage> {
  bool _busy = false;

  /// 当前正在执行的任务标识（'export' / 'import'），用于在对应卡片显示进度。
  String? _busyTask;

  bool _loadingCounts = true;
  int _messageCount = 0;
  int _sessionCount = 0;

  @override
  void initState() {
    super.initState();
    _loadCounts();
  }

  Future<void> _loadCounts() async {
    final db = ref.read(databaseProvider);
    final owner = ref.read(myUinProvider);
    try {
      final messages = await _countMessages(db, owner);
      final sessions = await _countSessions(db, owner);
      if (!mounted) return;
      setState(() {
        _messageCount = messages;
        _sessionCount = sessions;
        _loadingCounts = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() => _loadingCounts = false);
    }
  }

  Future<int> _countMessages(AppDatabase db, int owner) async {
    final count = countAll();
    final query = db.selectOnly(db.chatMessages)
      ..addColumns([count])
      ..where(db.chatMessages.ownerUin.equals(owner));
    final row = await query.getSingle();
    return row.read(count) ?? 0;
  }

  Future<int> _countSessions(AppDatabase db, int owner) async {
    final count = countAll();
    final query = db.selectOnly(db.chatSessions)
      ..addColumns([count])
      ..where(db.chatSessions.ownerUin.equals(owner));
    final row = await query.getSingle();
    return row.read(count) ?? 0;
  }

  void _snack(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(message)));
  }

  Future<void> _export({String? passphrase}) async {
    final l10n = l10nOf(context);
    final owner = ref.read(myUinProvider);
    if (owner == 0) {
      _snack(l10nOf(context)?.dataSignBeforeExporting ?? '请先登录后再导出');
      return;
    }
    setState(() {
      _busy = true;
      _busyTask = 'export';
    });
    try {
      final service = BackupService(ref.read(databaseProvider));
      final bytes = await service.exportJson(owner, passphrase: passphrase);
      // file_picker 12.x 的 saveFile 会自行写入字节：桌面端写盘并返回 Uri。
      // 取消（未选择路径）时返回 null。
      final uri = await FilePicker.saveFile(
        dialogTitle: l10n?.dataExportChatHistory ?? '导出聊天记录',
        fileName:
            'mnchat_backup_${owner}_${_timestamp()}'
            '${passphrase == null ? '' : '_enc'}.json',
        bytes: Uint8List.fromList(bytes),
        mimeType: 'application/json',
        type: FileType.custom,
        allowedExtensions: const ['json'],
      );
      if (!mounted) return;
      if (uri != null) {
        final path = uri.scheme == 'file' ? uri.toFilePath() : uri.toString();
        _snack(l10nOf(context)?.chatExported(path) ?? '已导出到 $path');
      } else {
        _snack(l10nOf(context)?.dataCanceled ?? '已取消');
      }
    } catch (e) {
      _snack(l10nOf(context)?.chatFailedExport(e) ?? '导出失败：$e');
    } finally {
      if (mounted) {
        setState(() {
          _busy = false;
          _busyTask = null;
        });
      }
    }
  }

  /// 加密导出：先让用户设置口令，再写带 AES-GCM 信封的备份。
  Future<void> _exportEncrypted() async {
    final passphrase = await showPassphraseDialog(context, confirm: true);
    if (passphrase == null || passphrase.isEmpty || !mounted) return;
    await _export(passphrase: passphrase);
  }

  Future<void> _import() async {
    final l10n = l10nOf(context);
    setState(() {
      _busy = true;
      _busyTask = 'import';
    });
    try {
      final picked = await FilePicker.pickFile(
        dialogTitle: l10nOf(context)?.dataChooseChatHistoryBackup ?? '选择聊天记录备份文件',
        type: FileType.custom,
        allowedExtensions: const ['json'],
      );
      if (picked == null) {
        _snack(l10n?.dataCanceled ?? '已取消');
        return;
      }
      final bytes = await picked.readAsBytes();
      if (!mounted) return;

      String? passphrase;
      if (isEncryptedBackup(bytes)) {
        passphrase = await showPassphraseDialog(context, confirm: false);
        if (passphrase == null || passphrase.isEmpty || !mounted) {
          _snack(l10n?.dataCanceled ?? '已取消');
          return;
        }
      }

      final confirmed = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: Text(l10nOf(context)?.dataImportChatHistory ?? '导入聊天记录'),
          content: Text(
            l10nOf(context)?.dataImportMergeConfirm ??
                '将把备份文件中的消息 / 会话 / 好友合并到当前账号，已存在的记录会自动跳过，不会删除或覆盖本地数据。是否继续？',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: Text(l10nOf(context)?.commonCancel ?? '取消'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: Text(l10nOf(context)?.dataImport ?? '导入'),
            ),
          ],
        ),
      );
      if (confirmed != true) return;

      final service = BackupService(ref.read(databaseProvider));
      final result = await service.importJson(bytes, passphrase: passphrase);
      await _loadCounts();
      _snack(
        l10n?.dataImportSummary(
              result.messages,
              result.sessions,
              result.friends,
            ) ??
            '导入完成：消息 ${result.messages} 条，会话 ${result.sessions} 个，好友 ${result.friends} 个',
      );
    } catch (e) {
      _snack(l10n?.dataImportFailed(e) ?? '导入失败：$e');
    } finally {
      if (mounted) {
        setState(() {
          _busy = false;
          _busyTask = null;
        });
      }
    }
  }

  String _timestamp() {
    final now = DateTime.now();
    String two(int v) => v.toString().padLeft(2, '0');
    return '${now.year}${two(now.month)}${two(now.day)}'
        '_${two(now.hour)}${two(now.minute)}${two(now.second)}';
  }

  Widget _leading(IconData icon, String task) {
    if (_busy && _busyTask == task) {
      return const SizedBox(
        width: 24,
        height: 24,
        child: CircularProgressIndicator(strokeWidth: 2),
      );
    }
    return Icon(icon);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final summary = _loadingCounts
        ? l10nOf(context)?.dataCounting ?? '统计中…'
        : l10nOf(context)?.dataMessagesChats(_messageCount, _sessionCount) ?? '共 $_messageCount 条消息 · $_sessionCount 个会话';

    return Scaffold(
      appBar: AppBar(title: Text(l10nOf(context)?.dataChatHistory ?? '聊天记录')),
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: AppSizes.narrowContent),
          child: ListView(
            padding: const EdgeInsets.all(AppSpacing.md),
            children: [
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(AppSpacing.lg),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Icon(
                            Icons.storage_outlined,
                            color: theme.colorScheme.primary,
                          ),
                          const SizedBox(width: AppSpacing.md),
                          Text(l10nOf(context)?.dataLocalData ?? '本地数据', style: theme.textTheme.titleSmall),
                        ],
                      ),
                      const SizedBox(height: AppSpacing.sm),
                      Text(
                        summary,
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: theme.colorScheme.outline,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: AppSpacing.md),
              Card(
                child: ListTile(
                  leading: _leading(Icons.upload_file_outlined, 'export'),
                  title: Text(l10nOf(context)?.dataExportChatHistory ?? '导出聊天记录'),
                  subtitle: Text(l10nOf(context)?.dataExportCurrentAccountsMessages ?? '把当前账号的消息 / 会话 / 好友导出为 JSON 文件'),
                  trailing: const Icon(Icons.chevron_right),
                  onTap: _busy ? null : _export,
                ),
              ),
              const SizedBox(height: AppSpacing.md),
              Card(
                child: ListTile(
                  leading: _leading(Icons.lock_outline, 'export-encrypted'),
                  title: Text(
                    l10nOf(context)?.dataExportEncrypted ?? '导出（加密）',
                  ),
                  subtitle: Text(
                    l10nOf(context)?.dataExportEncryptedHint ??
                        '设置口令后用 AES-256-GCM 加密备份文件',
                  ),
                  trailing: const Icon(Icons.chevron_right),
                  onTap: _busy ? null : _exportEncrypted,
                ),
              ),
              const SizedBox(height: AppSpacing.md),
              Card(
                child: ListTile(
                  leading: _leading(Icons.download_outlined, 'import'),
                  title: Text(l10nOf(context)?.dataImportChatHistory ?? '导入聊天记录'),
                  subtitle: Text(l10nOf(context)?.dataMergeImportJSONBackup ?? '从 JSON 备份文件合并导入（自动跳过已存在的记录）'),
                  trailing: const Icon(Icons.chevron_right),
                  onTap: _busy ? null : _import,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// 口令输入框的测试定位 key（保持名字稳定）。
const Key dataPassphraseFieldKey = Key('data_passphrase_field');
const Key dataPassphraseConfirmFieldKey = Key(
  'data_passphrase_confirm_field',
);
const Key dataPassphraseOkKey = Key('data_passphrase_ok');

/// 询问备份口令；取消返回 null。
Future<String?> showPassphraseDialog(
  BuildContext context, {
  required bool confirm,
}) {
  return showDialog<String>(
    context: context,
    builder: (_) => PassphraseDialog(confirm: confirm),
  );
}

/// 设置（需二次确认）或输入备份口令。
class PassphraseDialog extends StatefulWidget {
  const PassphraseDialog({super.key, required this.confirm});

  /// true = 设置新口令（需确认）；false = 输入已有口令。
  final bool confirm;

  @override
  State<PassphraseDialog> createState() => _PassphraseDialogState();
}

class _PassphraseDialogState extends State<PassphraseDialog> {
  final _passphrase = TextEditingController();
  final _again = TextEditingController();
  String? _error;

  @override
  void dispose() {
    _passphrase.dispose();
    _again.dispose();
    super.dispose();
  }

  void _submit() {
    final p = _passphrase.text;
    final l10n = l10nOf(context);
    if (p.isEmpty) {
      setState(() {
        _error = l10n?.dataPassphraseEmpty ?? '口令不能为空';
      });
      return;
    }
    if (widget.confirm && p != _again.text) {
      setState(() {
        _error = l10n?.dataPassphraseMismatch ?? '两次输入的口令不一致';
      });
      return;
    }
    Navigator.pop(context, p);
  }

  @override
  Widget build(BuildContext context) {
    final l10n = l10nOf(context);
    return AlertDialog(
      title: Text(
        widget.confirm
            ? l10n?.dataSetBackupPassphrase ?? '设置备份口令'
            : l10n?.dataEnterBackupPassphrase ?? '输入备份口令',
      ),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          TextField(
            key: dataPassphraseFieldKey,
            controller: _passphrase,
            autofocus: true,
            obscureText: true,
            decoration: InputDecoration(
              labelText: l10n?.dataPassphrase ?? '口令',
              hintText: l10n?.dataPassphraseHint ?? '至少 6 位，忘记后无法恢复',
            ),
          ),
          if (widget.confirm)
            TextField(
              key: dataPassphraseConfirmFieldKey,
              controller: _again,
              obscureText: true,
              decoration: InputDecoration(
                labelText: l10n?.dataPassphraseAgain ?? '再次输入',
              ),
            ),
          if (_error != null)
            Padding(
              padding: const EdgeInsets.only(top: AppSpacing.sm),
              child: Text(
                _error!,
                style: TextStyle(color: Theme.of(context).colorScheme.error),
              ),
            ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: Text(l10n?.commonCancel ?? '取消'),
        ),
        FilledButton(
          key: dataPassphraseOkKey,
          onPressed: _submit,
          child: Text(l10n?.dataConfirm ?? '确定'),
        ),
      ],
    );
  }
}
