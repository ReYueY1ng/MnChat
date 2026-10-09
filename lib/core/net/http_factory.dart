/// 统一的 HTTP 客户端工厂。
///
/// 使用 dio 平台默认 adapter：原生平台为 `IOHttpClientAdapter`（走系统代理）。
/// **不强制禁代理直连**。
///
/// 传输层失败（超时 / 断网 / 4xx / 5xx）统一上报到 `RequestErrorBus`，UI 会弹
/// 提示并列出「哪个请求失败了」；业务码失败（HTTP 200 但 `code != 0`）由各
/// client 自己上报（它们才看得到业务码）。
///
/// 另外每次请求都交给 [DuplicateRequestMonitor] 记一笔指纹：同一接口在
/// [DuplicateRequestMonitor.window] 内被发第二次以上时打 warn —— 网关按账号
/// 排队，连发的第二条会回 `code=9/23`，这是需要立刻看见的信号。
library;

import 'package:dio/dio.dart';

import '../services/request_errors.dart' show RequestErrorBus;
import '../utils/log.dart' show log, redactUrl;
import 'config.dart' show kUa;
import 'duplicate_request_monitor.dart'
    show DuplicateRequestMonitor, requestFingerprint;

/// 创建 Dio 实例（dio 默认 adapter：原生 IO）。
///
/// 为默认请求设置模拟客户端 `User-Agent`（kUa），并挂一个拦截器：
/// 统计重复请求（[DuplicateRequestMonitor]）+ 把传输失败上报给 [RequestErrorBus]。
Dio createDio({Duration? connectTimeout, Duration? receiveTimeout}) {
  final timeout = connectTimeout ?? const Duration(seconds: 15);
  final dio = Dio(BaseOptions(
    connectTimeout: timeout,
    receiveTimeout: receiveTimeout ?? const Duration(seconds: 15),
    headers: {'User-Agent': kUa},
  ));
  dio.interceptors.add(InterceptorsWrapper(
    onRequest: (o, handler) {
      // 观测绝不能影响请求本身：指纹解析失败（脏 query）就当这次没统计。
      try {
        final monitor = DuplicateRequestMonitor.instance;
        final fingerprint = requestFingerprint(o.method, o.uri);
        final count = monitor.record(fingerprint);
        // 第 2 次 + 之后每 10 次：既立刻可见，又不刷屏。
        if (count > 1 && (count == 2 || count % 10 == 0)) {
          log.warn(
            '同一接口 ${monitor.window.inMilliseconds}ms 内第 $count 次请求'
            '（网关按账号排队，连发会回 code=9/23）: $fingerprint',
            tag: 'Net',
          );
        }
      } catch (e) {
        log.debug('重复请求计数失败（已忽略）: $e', tag: 'Net');
      }
      handler.next(o);
    },
    onError: (e, handler) {
      RequestErrorBus.instance.report(
        label: '网络请求',
        endpoint: redactUrl(e.requestOptions.uri.toString()),
        code: e.response?.statusCode,
        message: e.message ?? e.type.name,
      );
      handler.next(e);
    },
  ));
  return dio;
}
