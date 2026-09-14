/// 聊天记录页 —— 导出 / 导入本地聊天数据。
///
/// 导出：把当前账号的消息 / 会话 / 好友写成 JSON 文件；
/// 导入：从 JSON 备份文件增量合并（跳过已存在的记录，不覆盖本地数据）。
library;

import 'dart:typed_data';

import 'package:drift/drift.dart' show countAll;
import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/services/backup.dart';
import '../core/storage/app_database.dart' show AppDatabase;
import '../state/providers.dart';
import 'theme/app_tokens.dart';

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

  Future<void> _export() async {
    final owner = ref.read(myUinProvider);
    if (owner == 0) {
      _snack('请先登录后再导出');
      return;
    }
    setState(() {
      _busy = true;
      _busyTask = 'export';
    });
    try {
      final service = BackupService(ref.read(databaseProvider));
      final bytes = await service.exportJson(owner);
      // file_picker 12.x 的 saveFile 会自行写入字节：桌面端写盘并返回 Uri，
      // Web 端直接触发下载（返回 null），因此无需 dart:io，也不影响 Web 构建。
      final uri = await FilePicker.saveFile(
        dialogTitle: '导出聊天记录',
        fileName: 'mnchat_backup_${owner}_${_timestamp()}.json',
        bytes: Uint8List.fromList(bytes),
        mimeType: 'application/json',
        type: FileType.custom,
        allowedExtensions: const ['json'],
      );
      if (!mounted) return;
      if (uri != null) {
        final path = uri.scheme == 'file' ? uri.toFilePath() : uri.toString();
        _snack('已导出到 $path');
      } else if (kIsWeb) {
        _snack('已开始下载备份文件');
      } else {
        _snack('已取消');
      }
    } catch (e) {
      _snack('导出失败：$e');
    } finally {
      if (mounted) {
        setState(() {
          _busy = false;
          _busyTask = null;
        });
      }
    }
  }

  Future<void> _import() async {
    setState(() {
      _busy = true;
      _busyTask = 'import';
    });
    try {
      final picked = await FilePicker.pickFile(
        dialogTitle: '选择聊天记录备份文件',
        type: FileType.custom,
        allowedExtensions: const ['json'],
      );
      if (picked == null) {
        _snack('已取消');
        return;
      }
      final bytes = await picked.readAsBytes();
      if (!mounted) return;

      final confirmed = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Text('导入聊天记录'),
          content: const Text(
            '将把备份文件中的消息 / 会话 / 好友合并到当前账号，'
            '已存在的记录会自动跳过，不会删除或覆盖本地数据。是否继续？',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('取消'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('导入'),
            ),
          ],
        ),
      );
      if (confirmed != true) return;

      final service = BackupService(ref.read(databaseProvider));
      final result = await service.importJson(bytes);
      await _loadCounts();
      _snack(
        '导入完成：消息 ${result.messages} 条，'
        '会话 ${result.sessions} 个，好友 ${result.friends} 个',
      );
    } catch (e) {
      _snack('导入失败：$e');
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
        ? '统计中…'
        : '共 $_messageCount 条消息 · $_sessionCount 个会话';

    return Scaffold(
      appBar: AppBar(title: const Text('聊天记录')),
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: AppSizes.narrowContent),
          child: ListView(
            padding: const EdgeInsets.all(12),
            children: [
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Icon(
                            Icons.storage_outlined,
                            color: theme.colorScheme.primary,
                          ),
                          const SizedBox(width: 12),
                          Text('本地数据', style: theme.textTheme.titleSmall),
                        ],
                      ),
                      const SizedBox(height: 8),
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
              const SizedBox(height: 12),
              Card(
                child: ListTile(
                  leading: _leading(Icons.upload_file_outlined, 'export'),
                  title: const Text('导出聊天记录'),
                  subtitle: const Text('把当前账号的消息 / 会话 / 好友导出为 JSON 文件'),
                  trailing: const Icon(Icons.chevron_right),
                  onTap: _busy ? null : _export,
                ),
              ),
              const SizedBox(height: 12),
              Card(
                child: ListTile(
                  leading: _leading(Icons.download_outlined, 'import'),
                  title: const Text('导入聊天记录'),
                  subtitle: const Text('从 JSON 备份文件合并导入（自动跳过已存在的记录）'),
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
