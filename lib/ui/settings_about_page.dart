/// 设置 · 关于子页。
///
/// 内容：版本信息、检查更新（手动触发一次 GitHub Release 查询）、开源许可，
/// 以及把「版本 + 平台 + 最近的请求失败」导出成文本用于排障。
library;

import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart'
    show defaultTargetPlatform, kDebugMode;
import 'package:material_ui/material_ui.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path_provider/path_provider.dart';

import '../core/app_info.dart';
import '../core/net/config.dart' show kClientVersionStr, kCltVersion;
import '../core/services/app_update.dart';
import '../core/services/app_update_installer.dart' show UpdateInstaller;
import '../core/services/diagnostics.dart' show DiagnosticsService;
import '../core/services/request_errors.dart' show RequestErrorBus, RequestFailure;
import '../core/utils/rotating_log.dart' show RotatingLogFile;
import '../state/providers.dart';
import 'theme/app_tokens.dart';
import 'widgets/settings_tiles.dart';

import 'widgets/app_l10n.dart' show l10nOf;

class SettingsAboutPage extends ConsumerStatefulWidget {
  const SettingsAboutPage({super.key, this.client});

  /// 更新检查客户端（测试注入；生产为 null）。
  final AppUpdateClient? client;

  @override
  ConsumerState<SettingsAboutPage> createState() => _SettingsAboutPageState();
}

class _SettingsAboutPageState extends ConsumerState<SettingsAboutPage> {
  bool _checking = false;
  int _logBytes = 0;

  @override
  void initState() {
    super.initState();
    _loadLogState();
  }

  Future<RotatingLogFile> _logFile() async {
    final support = await getApplicationSupportDirectory();
    final file = RotatingLogFile(
      directory: Directory('${support.path}/logs'),
    );
    await file.init();
    return file;
  }

  Future<void> _loadLogState() async {
    try {
      final file = await _logFile();
      final bytes = await file.totalBytes();
      if (mounted) setState(() => _logBytes = bytes);
    } catch (_) {
      // 无文件系统权限等：保持 0。
    }
  }

  Future<void> _clearLogs() async {
    try {
      final file = await _logFile();
      await file.clear();
      if (!mounted) return;
      setState(() => _logBytes = 0);
      showSettingsToast(context, l10nOf(context)?.settingsAboutLogsCleared ?? '日志已清空');
    } catch (e) {
      if (mounted) showSettingsToast(context, l10nOf(context)?.settingsAboutFailedClear(e) ?? '清空失败：$e');
    }
  }

  String get _platformLabel =>
      '${defaultTargetPlatform.name}${kDebugMode ? ' (debug)' : ''}';

  Future<void> _checkUpdate() async {
    if (_checking) return;
    setState(() => _checking = true);
    final result = await (widget.client ?? AppUpdateClient()).check(
      kAppVersion,
    );
    if (!mounted) return;
    setState(() => _checking = false);
    final l10n = l10nOf(context);

    final String message;
    if (!result.ok) {
      message = l10nOf(context)?.settingsAboutCheckFailedYouAlso(result.error.toString()) ?? '检查失败：${result.error}\n\n也可以直接到 Releases 页面查看：\n'
          '${AppUpdateClient.releasesPage}';
    } else if (result.hasUpdate) {
      message = l10nOf(context)?.settingsAboutNewVersionAvailableCurrent(
          result.latest.toString(),
          kAppVersion,
          result.url.toString(),
        ) ?? '发现新版本 ${result.latest}（当前 $kAppVersion）\n\n${result.url}';
    } else {
      message = l10nOf(context)?.settingsAboutAlreadyUpDate(kAppVersion) ?? '已是最新版本（$kAppVersion）';
    }

    await showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(result.hasUpdate ? l10nOf(context)?.settingsAboutNewVersionFound ?? '发现新版本' : l10nOf(context)?.settingsAboutCheckUpdates ?? '检查更新'),
        content: Text(message),
        actions: [
          if (result.ok && result.hasUpdate && _assetForPlatform(result) != null)
            FilledButton(
              onPressed: () {
                Navigator.pop(ctx);
                _downloadUpdate(result);
              },
              child: Text(
                l10n?.settingsAboutDownloadUpdate ?? '下载并安装',
              ),
            ),
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: Text(l10n?.settingsAboutGotIt ?? '知道了'),
          ),
        ],
      ),
    );
  }

  /// 当前平台对应的发布产物。
  UpdateAsset? _assetForPlatform(UpdateCheckResult result) {
    final ext = switch (defaultTargetPlatform) {
      TargetPlatform.android => '.apk',
      TargetPlatform.windows => '.zip',
      TargetPlatform.linux => '.tar.gz',
      _ => null,
    };
    return ext == null ? null : result.assetForExtension(ext);
  }

  /// 下载更新包（可选 SHA-256 校验）并交给系统打开。
  Future<void> _downloadUpdate(UpdateCheckResult result) async {
    final l10n = l10nOf(context);
    final asset = _assetForPlatform(result);
    if (asset == null) {
      showSettingsToast(
        context,
        l10n?.settingsAboutNoPackageForPlatform ?? '该版本没有提供当前平台的安装包',
      );
      return;
    }
    final dir = await getTemporaryDirectory();
    if (!mounted) return;
    final progress = ValueNotifier<(int, int?)>((0, null));
    unawaited(
      showDialog<void>(
        context: context,
        barrierDismissible: false,
        builder: (ctx) => AlertDialog(
          title: Text(l10n?.settingsAboutDownloading ?? '正在下载更新'),
          content: ValueListenableBuilder<(int, int?)>(
            valueListenable: progress,
            builder: (_, value, _) {
              final total = value.$2;
              return Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  LinearProgressIndicator(
                    value: total == null || total <= 0 ? null : value.$1 / total,
                  ),
                  const SizedBox(height: AppSpacing.sm),
                  Text(
                    total == null || total <= 0
                        ? '${(value.$1 / 1024).toStringAsFixed(0)} KB'
                        : '${(value.$1 / total * 100).toStringAsFixed(0)}%',
                  ),
                ],
              );
            },
          ),
        ),
      ),
    );

    try {
      final file = await (widget.client ?? AppUpdateClient()).downloadAsset(
        asset,
        directory: dir,
        onProgress: (received, total) => progress.value = (received, total),
      );
      if (!mounted) return;
      Navigator.of(context).pop();
      final opened = await UpdateInstaller().open(file);
      if (!mounted) return;
      showSettingsToast(
        context,
        opened
            ? l10n?.settingsAboutUpdateOpened ?? '已打开安装包'
            : l10n?.settingsAboutUpdateSaved ?? '安装包已下载，可在文件管理器中手动安装',
      );
    } catch (e) {
      if (!mounted) return;
      Navigator.of(context).pop();
      showSettingsToast(
        context,
        l10n?.settingsAboutUpdateDownloadFailed ?? '下载失败，请检查网络后重试',
      );
    } finally {
      progress.dispose();
    }
  }

  /// 导出诊断信息。
  ///
  /// 这里导出的是**诊断快照**而不是原始日志：`core/utils/log.dart` 只往
  /// debugPrint 写、不落盘，没有可导出的日志文件。快照包含版本 / 平台 /
  /// 构建类型 / 最近的请求失败（`RequestErrorBus` 保留最近 30 条），
  /// 正是排查「哪个请求挂了」需要的东西。
  Future<void> _exportDiagnostics() async {
    final l10n = l10nOf(context);
    final String report;
    try {
      final logFile = await _logFile();
      report = await DiagnosticsService(
        logFile: logFile,
        db: ref.read(databaseProvider),
      ).buildReport(ownerUin: ref.read(myUinProvider));
    } catch (e) {
      if (mounted) showSettingsToast(context, l10nOf(context)?.settingsAboutFailedCollectDiagnostics(e) ?? '汇总诊断失败：$e');
      return;
    }

    final buffer = StringBuffer(report)
      ..writeln()
      ..writeln(l10n?.settingsAboutRecentRequestFailures ?? '## 最近的请求失败');
    final failures = RequestErrorBus.instance.failures.value;
    if (failures.isEmpty) {
      buffer.writeln(l10n?.settingsAboutNone ?? '（无）');
    } else {
      for (final f in failures) {
        buffer.writeln(_failureLine(f));
      }
    }
    final bytes = utf8.encode(buffer.toString());

    try {
      final uri = await FilePicker.saveFile(
        dialogTitle: l10n?.settingsAboutExportDiagnostics ?? '导出诊断信息',
        fileName:
            'mnchat_diagnostics_${DateTime.now().millisecondsSinceEpoch}.txt',
        bytes: Uint8List.fromList(bytes),
        mimeType: 'text/plain',
        type: FileType.custom,
        allowedExtensions: const ['txt'],
      );
      if (!mounted) return;
      if (uri == null) {
        showSettingsToast(context, l10nOf(context)?.dataCanceled ?? '已取消');
      } else {
        final path = uri.scheme == 'file' ? uri.toFilePath() : uri.toString();
        showSettingsToast(context, l10nOf(context)?.chatExported(path) ?? '已导出到 $path');
      }
    } catch (e) {
      if (mounted) showSettingsToast(context, l10nOf(context)?.chatFailedExport(e) ?? '导出失败：$e');
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
      appBar: AppBar(title: Text(l10nOf(context)?.settingsAboutAbout ?? '关于')),
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: AppSizes.narrowContent),
          child: ListView(
            padding: const EdgeInsets.all(AppSpacing.md),
            children: [
              SettingsSectionHeader(l10nOf(context)?.settingsAboutVersion ?? '版本'),
              SettingsInfoTile(
                icon: Icons.info_outline,
                title: 'MnChat v$kAppVersion',
                subtitle:
                    l10nOf(context)?.settingsAboutClientLine(
                      kClientVersionStr,
                      kCltVersion,
                      _platformLabel,
                    ) ??
                    '迷你世界外部聊天客户端 · 客户端 $kClientVersionStr ($kCltVersion) · $_platformLabel',
              ),
              SettingsNavTile(
                icon: Icons.system_update_alt_outlined,
                title: l10nOf(context)?.settingsAboutCheckUpdates ?? '检查更新',
                subtitle: _checking ? l10nOf(context)?.settingsAboutChecking ?? '正在检查…' : l10nOf(context)?.settingsAboutCheckLatestBuildGitHub ?? '查询 GitHub 上的最新构建',
                onTap: _checkUpdate,
              ),

              SettingsSectionHeader(l10nOf(context)?.settingsAboutOther ?? '其他'),
              SettingsNavTile(
                icon: Icons.article_outlined,
                title: l10nOf(context)?.settingsAboutOpenSourceLicenses ?? '开源许可',
                subtitle: l10nOf(context)?.settingsAboutThirdPartyDependenciesLicenses ?? '第三方依赖与许可证',
                onTap: () => showLicensePage(
                  context: context,
                  applicationName: 'MnChat',
                  applicationVersion: kAppVersion,
                ),
              ),
              SettingsNavTile(
                icon: Icons.bug_report_outlined,
                title: l10nOf(context)?.settingsAboutExportDiagnostics ?? '导出诊断信息',
                subtitle: l10nOf(context)?.settingsAboutVersionPlatformTableCounts ?? '版本 / 平台 / 表计数 / 日志尾部 / 最近请求失败',
                onTap: _exportDiagnostics,
              ),
              SettingsInfoTile(
                icon: Icons.description_outlined,
                title: l10nOf(context)?.settingsAboutLogFiles ?? '日志文件',
                subtitle: _logBytes == 0
                    ? l10nOf(context)?.settingsAboutNoLogsYet ?? '暂无日志'
                    : l10nOf(context)?.settingsAboutLogSizeNote(
                            (_logBytes / 1024).toStringAsFixed(1),
                          ) ??
                          '${(_logBytes / 1024).toStringAsFixed(1)} KB · 应用私有目录（自动轮转）',
              ),
              SettingsNavTile(
                icon: Icons.delete_sweep_outlined,
                title: l10nOf(context)?.settingsAboutClearLogs ?? '清空日志',
                subtitle: l10nOf(context)?.settingsAboutDeleteRotatedLogFiles ?? '删除全部轮转日志文件',
                onTap: _clearLogs,
              ),
              const SizedBox(height: AppSpacing.xl),
            ],
          ),
        ),
      ),
    );
  }
}
