/// 统一的 HTTP 客户端工厂。
///
/// 使用 dio 平台默认 adapter：原生平台为 `IOHttpClientAdapter`（走系统代理）。
/// **不强制禁代理直连**。
///
/// 传输层失败（超时 / 断网 / 4xx / 5xx）统一上报到 `RequestErrorBus`，UI 会弹
/// 提示并列出「哪个请求失败了」；业务码失败（HTTP 200 但 `code != 0`）由各
/// client 自己上报（它们才看得到业务码）。
library;

import 'package:dio/dio.dart';

import '../services/request_errors.dart' show RequestErrorBus;
import '../utils/log.dart' show redactUrl;
import 'config.dart' show kUa;

/// 创建 Dio 实例（dio 默认 adapter：原生 IO）。
///
/// 为默认请求设置模拟客户端 `User-Agent`（kUa），并挂一个把传输失败上报给
/// [RequestErrorBus] 的拦截器。
Dio createDio({Duration? connectTimeout, Duration? receiveTimeout}) {
  final timeout = connectTimeout ?? const Duration(seconds: 15);
  final dio = Dio(BaseOptions(
    connectTimeout: timeout,
    receiveTimeout: receiveTimeout ?? const Duration(seconds: 15),
    headers: {'User-Agent': kUa},
  ));
  dio.interceptors.add(InterceptorsWrapper(
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
