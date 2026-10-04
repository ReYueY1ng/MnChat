/// 设置 · 关于子页。
///
/// 内容：版本信息、检查更新（手动触发一次 GitHub Release 查询）、开源许可，
/// 以及把「版本 + 平台 + 最近的请求失败」导出成文本用于排障。
library;

import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart'
    show defaultTargetPlatform, kDebugMode;
import 'package:material_ui/material_ui.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/app_info.dart';
import '../core/net/config.dart' show kClientVersionStr, kCltVersion;
import '../core/services/app_update.dart';
import '../core/services/request_errors.dart' show RequestErrorBus, RequestFailure;
import '../state/providers.dart';
import 'theme/app_tokens.dart';
import 'widgets/settings_tiles.dart';

class SettingsAboutPage extends ConsumerStatefulWidget {
  const SettingsAboutPage({super.key});

  @override
  ConsumerState<SettingsAboutPage> createState() => _SettingsAboutPageState();
}

class _SettingsAboutPageState extends ConsumerState<SettingsAboutPage> {
  bool _checking = false;

  String get _platformLabel =>
      '${defaultTargetPlatform.name}${kDebugMode ? ' (debug)' : ''}';

  Future<void> _checkUpdate() async {
    if (_checking) return;
    setState(() => _checking = true);
    final result = await AppUpdateClient().check(kAppVersion);
    if (!mounted) return;
    setState(() => _checking = false);

    final String message;
    if (!result.ok) {
      message = '检查失败：${result.error}\n\n也可以直接到 Releases 页面查看：\n'
          '${AppUpdateClient.releasesPage}';
    } else if (result.hasUpdate) {
      message = '发现新版本 ${result.latest}（当前 $kAppVersion）\n\n${result.url}';
    } else {
      message = '已是最新版本（$kAppVersion）';
    }

    await showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(result.hasUpdate ? '发现新版本' : '检查更新'),
        content: Text(message),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('知道了'),
          ),
        ],
      ),
    );
  }

  /// 导出诊断信息。
  ///
  /// 这里导出的是**诊断快照**而不是原始日志：`core/utils/log.dart` 只往
  /// debugPrint 写、不落盘，没有可导出的日志文件。快照包含版本 / 平台 /
  /// 构建类型 / 最近的请求失败（`RequestErrorBus` 保留最近 30 条），
  /// 正是排查「哪个请求挂了」需要的东西。
  Future<void> _exportDiagnostics() async {
    final buffer = StringBuffer()
      ..writeln('# MnChat 诊断信息')
      ..writeln('导出时间: ${DateTime.now().toIso8601String()}')
      ..writeln('应用版本: $kAppVersion')
      ..writeln('客户端版本: $kClientVersionStr ($kCltVersion)')
      ..writeln('平台: $_platformLabel')
      ..writeln('Uin: ${ref.read(myUinProvider)}')
      ..writeln();
    final failures = RequestErrorBus.instance.failures.value;
    buffer.writeln('## 最近的请求失败（${failures.length} 条）');
    if (failures.isEmpty) {
      buffer.writeln('（无）');
    } else {
      for (final f in failures) {
        buffer.writeln(_failureLine(f));
      }
    }

    try {
      final uri = await FilePicker.saveFile(
        dialogTitle: '导出诊断信息',
        fileName:
            'mnchat_diagnostics_${DateTime.now().millisecondsSinceEpoch}.txt',
        bytes: Uint8List.fromList(buffer.toString().codeUnits),
        mimeType: 'text/plain',
        type: FileType.custom,
        allowedExtensions: const ['txt'],
      );
      if (!mounted) return;
      if (uri == null) {
        showSettingsToast(context, '已取消');
      } else {
        final path = uri.scheme == 'file' ? uri.toFilePath() : uri.toString();
        showSettingsToast(context, '已导出到 $path');
      }
    } catch (e) {
      if (mounted) showSettingsToast(context, '导出失败：$e');
    }
  }

  static String _failureLine(RequestFailure f) {
    final code = f.code == null ? '' : ' code=${f.code}';
    final status = f.statusKey == null ? '' : '/${f.statusKey}';
    final msg = f.message.isEmpty ? '' : ' msg=${f.message}';
    return '- [${f.at.toIso8601String()}] ${f.label}$code$status'
        ' ${f.endpoint}$msg';
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('关于')),
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: AppSizes.narrowContent),
          child: ListView(
            padding: const EdgeInsets.all(AppSpacing.md),
            children: [
              const SettingsSectionHeader('版本'),
              SettingsInfoTile(
                icon: Icons.info_outline,
                title: 'MnChat v$kAppVersion',
                subtitle: '迷你世界外部聊天客户端 · '
                    '客户端 $kClientVersionStr ($kCltVersion) · $_platformLabel',
              ),
              SettingsNavTile(
                icon: Icons.system_update_alt_outlined,
                title: '检查更新',
                subtitle: _checking ? '正在检查…' : '查询 GitHub 上的最新构建',
                onTap: _checkUpdate,
              ),

              const SettingsSectionHeader('其他'),
              SettingsNavTile(
                icon: Icons.article_outlined,
                title: '开源许可',
                subtitle: '第三方依赖与许可证',
                onTap: () => showLicensePage(
                  context: context,
                  applicationName: 'MnChat',
                  applicationVersion: kAppVersion,
                ),
              ),
              SettingsNavTile(
                icon: Icons.bug_report_outlined,
                title: '导出诊断信息',
                subtitle: '版本 / 平台 / 最近的请求失败，排障用',
                onTap: _exportDiagnostics,
              ),
              const SizedBox(height: AppSpacing.xl),
            ],
          ),
        ),
      ),
    );
  }
}
