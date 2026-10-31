/// 诊断支持：全局错误钩子 + 可导出的诊断包。
///
/// 诊断包内容只包含版本/平台/表计数/日志尾部；日志已做敏感字段脱敏。
library;

import 'dart:convert';
import 'dart:io';
import 'dart:ui' show PlatformDispatcher;

import 'package:flutter/foundation.dart'
    show FlutterError, FlutterErrorDetails, kReleaseMode;

import '../app_info.dart' show kAppVersion;
import '../storage/app_database.dart';
import '../utils/log.dart';
import '../utils/rotating_log.dart';

/// 组装诊断文本。
class DiagnosticsService {
  DiagnosticsService({required this.logFile, required this.db});

  final RotatingLogFile logFile;
  final AppDatabase db;

  Future<String> buildReport({int ownerUin = 0}) async {
    final sb = StringBuffer()
      ..writeln('MnChat diagnostics')
      ..writeln('generated=${DateTime.now().toIso8601String()}')
      ..writeln('app=$kAppVersion')
      ..writeln('release=$kReleaseMode')
      ..writeln('os=${Platform.operatingSystem} ${Platform.operatingSystemVersion}')
      ..writeln('dart=${Platform.version}')
      ..writeln('schema=${db.schemaVersion}')
      ..writeln('owner=$ownerUin');

    try {
      final stats = await db.storageStats();
      sb
        ..writeln('db_page_count=${stats.pageCount}')
        ..writeln('db_page_size=${stats.pageSize}')
        ..writeln('db_free_pages=${stats.freePages}')
        ..writeln('db_bytes=${stats.pageCount * stats.pageSize}');
      if (ownerUin != 0) {
        sb
          ..writeln('messages=${await db.countMessages(ownerUin)}')
          ..writeln('sessions=${(await db.allSessions(ownerUin)).length}')
          ..writeln('friends=${(await db.allFriends(ownerUin)).length}')
          ..writeln('outbox=${await db.outboxCount(ownerUin)}');
      }
    } catch (e) {
      sb.writeln('db_stats_error=$e');
    }

    sb
      ..writeln('log_file=${logFile.currentFile.path}')
      ..writeln('--- log tail ---');
    for (final line in await logFile.tail(lines: 300)) {
      sb.writeln(line);
    }
    return sb.toString();
  }

  Future<List<int>> exportBytes({int ownerUin = 0}) async =>
      utf8.encode(await buildReport(ownerUin: ownerUin));
}

/// 安装全局错误钩子：Flutter 框架错误与未捕获异步错误都写进日志。
///
/// 保留此前的 `FlutterError.onError`（Flutter 默认实现会打印并上报到
/// debugger），只在其后再补一条持久化记录。
void installCrashHandlers({void Function()? flush}) {
  final previous = FlutterError.onError;
  FlutterError.onError = (FlutterErrorDetails details) {
    previous?.call(details);
    log.error(
      'FlutterError: ${details.exceptionAsString()}\n${details.stack ?? ''}',
      tag: 'Crash',
    );
    flush?.call();
  };
  PlatformDispatcher.instance.onError = (Object error, StackTrace stack) {
    log.error('Uncaught: $error\n$stack', tag: 'Crash');
    flush?.call();
    // 已记录：不要因为一个未捕获异常直接杀掉应用。
    return true;
  };
}
