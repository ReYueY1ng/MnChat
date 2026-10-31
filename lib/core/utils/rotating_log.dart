/// 轮转日志文件 + 行级脱敏。
///
/// 为什么需要它：`log.dart` 只写 `debugPrint`，release 只保留 warn 且控制台不落盘；
/// 用户报「消息丢了 / 收不到」时开发者手上没有任何现场。这里把日志写进应用私有
/// 目录，按大小轮转，且对 URL/JSON 里的 s2/s2t/密码/token 再做一次兜底脱敏
/// （调用方应当已经用 `redactUrl`，但日志来源多，不能只靠约定）。
library;

import 'dart:async';
import 'dart:convert';
import 'dart:io';

/// 对一行日志脱敏：`s2=…` / `"token":"…"` 一类的值替换成 `***`。
String redactLogLine(String line) {
  var out = line.replaceAllMapped(
    RegExp(
      r'\b(s2t|s2|passwd|password|token|jwt|sign|md5)=([^&\s]+)',
      caseSensitive: false,
    ),
    (m) => '${m[1]}=***',
  );
  out = out.replaceAllMapped(
    RegExp(
      r'("(?:s2t|s2|passwd|password|token|jwt|sign|md5)"\s*:\s*")([^"]*)(")',
      caseSensitive: false,
    ),
    (m) => '${m[1]}***${m[3]}',
  );
  return out;
}

/// 一个按大小轮转的日志文件：`mnchat.log` → `mnchat.log.1` → … → `mnchat.log.<keep>`。
class RotatingLogFile {
  RotatingLogFile({
    required this.directory,
    this.baseName = 'mnchat',
    this.maxBytes = 1024 * 1024,
    this.keep = 3,
    DateTime Function()? now,
  }) : _now = now ?? DateTime.now;

  final Directory directory;
  final String baseName;

  /// 单个文件大小上限。
  final int maxBytes;

  /// 保留的旧文件个数（总文件数 = keep + 1）。
  final int keep;

  final DateTime Function() _now;

  final List<String> _buffer = [];
  int _bufferBytes = 0;
  int _writtenBytes = 0;
  Timer? _flushTimer;

  File get currentFile => File('${directory.path}/$baseName.log');

  File _rotated(int i) => File('${directory.path}/$baseName.log.$i');

  /// 创建目录并读取当前文件大小；返回当前日志文件。
  Future<File> init() async {
    await directory.create(recursive: true);
    _writtenBytes = await currentFile.exists() ? await currentFile.length() : 0;
    return currentFile;
  }

  /// 写入一行（自动脱敏 + 加时间戳）。缓冲到 8KB 或 1 秒后落盘。
  void write(String line) {
    final redacted = redactLogLine(line);
    final stamped = '${_now().toIso8601String()} $redacted';
    _buffer.add(stamped);
    _bufferBytes += stamped.length + 1;
    if (_bufferBytes >= 8192) {
      unawaited(flush());
      return;
    }
    _flushTimer ??= Timer(const Duration(seconds: 1), () {
      _flushTimer = null;
      unawaited(flush());
    });
  }

  /// 把缓冲写进文件；必要时先轮转。
  Future<void> flush() async {
    _flushTimer?.cancel();
    _flushTimer = null;
    if (_buffer.isEmpty) return;
    final bytes = utf8.encode('${_buffer.join('\n')}\n');
    _buffer.clear();
    _bufferBytes = 0;
    try {
      if (_writtenBytes + bytes.length > maxBytes) {
        await _rotate();
      }
      await currentFile.writeAsBytes(bytes, mode: FileMode.append, flush: false);
      _writtenBytes += bytes.length;
    } catch (_) {
      // 落盘失败不能反过来打断业务；日志是尽力而为。
    }
  }

  Future<void> _rotate() async {
    // 从最老的文件开始往后挪，避免覆盖。
    for (var i = keep; i > 1; i--) {
      final from = _rotated(i - 1);
      if (await from.exists()) {
        await from.rename(_rotated(i).path);
      }
    }
    if (await currentFile.exists()) {
      await currentFile.rename(_rotated(1).path);
    }
    _writtenBytes = 0;
  }

  /// 清空全部日志文件。
  Future<void> clear() async {
    await flush();
    for (var i = 0; i <= keep; i++) {
      final f = i == 0 ? currentFile : _rotated(i);
      if (await f.exists()) await f.delete();
    }
    _writtenBytes = 0;
  }

  /// 全部日志文件的总字节数（设置页展示）。
  Future<int> totalBytes() async {
    var total = 0;
    for (var i = 0; i <= keep; i++) {
      final f = i == 0 ? currentFile : _rotated(i);
      if (await f.exists()) total += await f.length();
    }
    return total;
  }

  /// 最近若干行（诊断包用）：从最老到最新拼接后取尾部。
  Future<List<String>> tail({int lines = 200}) async {
    final all = <String>[];
    for (var i = keep; i >= 0; i--) {
      final f = i == 0 ? currentFile : _rotated(i);
      if (!await f.exists()) continue;
      try {
        all.addAll(const LineSplitter().convert(await f.readAsString()));
      } catch (_) {
        // 坏文件跳过。
      }
    }
    return all.length <= lines ? all : all.sublist(all.length - lines);
  }

  void dispose() {
    _flushTimer?.cancel();
    _flushTimer = null;
    unawaited(flush());
  }
}
