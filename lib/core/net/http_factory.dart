/// 统一的 HTTP 客户端工厂。
///
/// 使用 dio 平台默认 adapter：原生平台为 `IOHttpClientAdapter`（走系统代理）。
/// **不强制禁代理直连**。
library;

import 'package:dio/dio.dart';

import 'config.dart' show kUa;

/// 创建 Dio 实例（dio 默认 adapter：原生 IO）。
///
/// 为默认请求设置模拟客户端 `User-Agent`（kUa）。
Dio createDio({Duration? connectTimeout, Duration? receiveTimeout}) {
  final timeout = connectTimeout ?? const Duration(seconds: 15);
  return Dio(BaseOptions(
    connectTimeout: timeout,
    receiveTimeout: receiveTimeout ?? const Duration(seconds: 15),
    headers: {'User-Agent': kUa},
  ));
}