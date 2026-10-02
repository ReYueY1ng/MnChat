/// 轻量分级日志设施 —— 全项目 `print` / `debugPrint` 的统一出口。
///
/// 输出格式固定为 `[级别][标签] 消息`，级别大写、标签为模块名，便于在
/// 控制台里按模块或级别 grep（例如 `grep '\[WARN\]\[TrayService\]'`）。
///
/// 分级自低到高为 trace / debug / info / warn / error；低于 [Log.minLevel]
/// 的调用会被直接丢弃，不做任何格式化与输出。默认门限：debug / profile
/// 构建全部输出，release 构建只保留 warn 及以上。
///
/// 本设施只依赖 `package:flutter/foundation.dart` 的 `debugPrint`，不碰
/// `dart:io`，因此 android / linux / windows 全平台可用。
///
/// 用法：
/// ```dart
/// const String _logTag = 'ChatService';
///
/// log.debug('query_friend_list failed: $e', tag: _logTag);
/// log.warn('URL（已脱敏）: ${redactUrl(url)}', tag: _logTag);
/// ```
library;

import 'package:flutter/foundation.dart' show debugPrint, kReleaseMode;

/// 日志级别，声明顺序即严重度顺序（越靠后越严重）。
enum LogLevel {
  trace('TRACE'),
  debug('DEBUG'),
  info('INFO'),
  warn('WARN'),
  error('ERROR');

  const LogLevel(this.label);

  /// 输出文本中的级别名，大写以便 grep。
  final String label;
}

/// 输出回调：默认写 `debugPrint`，测试可替换它来捕获日志行。
typedef LogSink = void Function(String line);

/// 全局日志入口；业务代码只需 import 本文件后调用 [log]。
const Log log = Log._();

/// 分级日志器 —— 请使用全局常量 [log]，不要自行构造。
class Log {
  const Log._();

  /// 输出门限；低于该级别的调用被直接丢弃。
  ///
  /// debug / profile 构建默认 [LogLevel.trace]（全放），release 构建默认
  /// [LogLevel.warn]（只保留警告与错误）。
  static LogLevel minLevel = kReleaseMode ? LogLevel.warn : LogLevel.trace;

  /// 自定义输出回调；为 null 时输出到 `debugPrint`。
  ///
  /// 供测试注入以断言级别门限，业务代码不要设置。
  static LogSink? sink;

  /// 最低级别：细粒度流程跟踪，仅排障时使用。
  void trace(String message, {String tag = _defaultTag}) =>
      _write(LogLevel.trace, tag, message);

  /// 调试级别：开发期诊断信息，release 构建默认不输出。
  void debug(String message, {String tag = _defaultTag}) =>
      _write(LogLevel.debug, tag, message);

  /// 普通信息：值得记录的正常流程节点。
  void info(String message, {String tag = _defaultTag}) =>
      _write(LogLevel.info, tag, message);

  /// 警告：可恢复的失败或异常回退路径。
  void warn(String message, {String tag = _defaultTag}) =>
      _write(LogLevel.warn, tag, message);

  /// 错误：需要关注的失败（如消息持久化失败）。
  void error(String message, {String tag = _defaultTag}) =>
      _write(LogLevel.error, tag, message);
}

/// 未显式传 tag 时的默认标签。
const String _defaultTag = 'app';

/// 按级别过滤后写出 `[级别][标签] 消息`。
void _write(LogLevel level, String tag, String message) {
  if (level.index < Log.minLevel.index) return;
  final line = '[${level.label}][$tag] $message';
  final sink = Log.sink;
  if (sink != null) {
    sink(line);
    return;
  }
  debugPrint(line);
}

/// 查询串中需要脱敏的参数名（小写比较）。
///
/// 迷你世界的接口把会话令牌 `s2` / `s2t` 与请求签名 `md5` 直接放在 URL
/// 查询串里，原样落日志等同泄露凭据。
const Set<String> _sensitiveQueryKeys = {
  's2',
  's2t',
  // s7 是整段 query 的自定义 base64（里面就带着 s2t 与 auth），同样敏感。
  's7',
  's7t',
  'md5',
  'sign',
  'signature',
  'sig',
  'token',
  'access_token',
  'password',
  'passwd',
  'pwd',
  'session',
  'sessionid',
  'key',
};

/// 把 URL 中敏感查询参数的值替换为 `***`，用于安全地记录请求地址。
///
/// 非 URL、无查询串或查询串中参数名不敏感时原样返回；只有值被替换，
/// 参数名与其余参数保留，仍可据此定位请求。
String redactUrl(String url) {
  final q = url.indexOf('?');
  if (q < 0 || q == url.length - 1) return url;
  final parts = url.substring(q + 1).split('&');
  for (var i = 0; i < parts.length; i++) {
    final eq = parts[i].indexOf('=');
    if (eq <= 0) continue;
    final name = parts[i].substring(0, eq);
    if (_sensitiveQueryKeys.contains(name.toLowerCase())) {
      parts[i] = '$name=***';
    }
  }
  return '${url.substring(0, q + 1)}${parts.join('&')}';
}
