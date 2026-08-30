/// 统一的 HTTP 客户端工厂。
///
/// 关键点：**禁用系统代理**。Dart `dart:io` 的 `HttpClient` 默认会读取
/// 环境变量 `HTTP_PROXY`/`HTTPS_PROXY`/`ALL_PROXY` 并走代理；在用户机器上
/// 这会导致连 迷你世界 服务器（chatpush.mini1.cn 等）被代理中间重置
/// （`连接被对方重置 errno=104`）。必须强制 DIRECT 直连。
library;

import 'dart:io';

import 'package:dio/dio.dart';
import 'package:dio/io.dart' show IOHttpClientAdapter;

/// 创建禁代理的 Dio 实例。
Dio createDio({Duration? connectTimeout, Duration? receiveTimeout}) {
  final timeout = connectTimeout ?? const Duration(seconds: 15);
  final dio = Dio(BaseOptions(
    connectTimeout: timeout,
    receiveTimeout: receiveTimeout ?? const Duration(seconds: 15),
  ));
  dio.httpClientAdapter = IOHttpClientAdapter(
    createHttpClient: () => createDirectHttpClient(timeout: timeout),
  );
  return dio;
}

/// 便捷创建 HttpClient（禁用代理，供非 Dio 场景使用）。
HttpClient createDirectHttpClient({Duration? timeout}) {
  final client = HttpClient();
  client.findProxy = (_) => 'DIRECT';
  client.connectionTimeout = timeout ?? const Duration(seconds: 15);
  return client;
}