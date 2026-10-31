/// 打开已下载的更新包：交给系统默认处理（Linux xdg-open / Windows explorer /
/// macOS open）。
///
/// Android 的安装需要 PackageInstaller 权限与 FileProvider，没有设备无法验证，
/// 因此这里明确返回 false，由调用方提示用户手动安装 —— 不假装支持。
library;

import 'dart:io';

/// 启动进程的注入点（测试用）。
typedef ProcessStarter =
    Future<ProcessResult> Function(String executable, List<String> args);

class UpdateInstaller {
  UpdateInstaller({ProcessStarter? start, String? platform})
    : _start = start ?? Process.run,
      _platform = platform ?? Platform.operatingSystem;

  final ProcessStarter _start;
  final String _platform;

  /// 平台是否支持「直接打开下载的更新包」。
  bool get supported => _commandFor('x') != null;

  (String, List<String>)? _commandFor(String path) => switch (_platform) {
    'linux' => ('xdg-open', <String>[path]),
    'windows' => ('explorer', <String>[path]),
    'macos' => ('open', <String>[path]),
    _ => null,
  };

  /// 打开 [file]；不支持或失败返回 false，不抛。
  Future<bool> open(File file) async {
    final command = _commandFor(file.path);
    if (command == null) return false;
    if (!await file.exists()) return false;
    try {
      final result = await _start(command.$1, command.$2);
      return result.exitCode == 0;
    } catch (_) {
      return false;
    }
  }
}
