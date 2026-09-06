/// 统一的 HTTP 客户端工厂。
///
/// 使用 dio 平台默认 adapter：原生平台为 `IOHttpClientAdapter`（走系统代理），
/// Web 平台为 `BrowserHttpClientAdapter`（基于 XMLHttpRequest/fetch）。
/// **不强制禁代理直连**。
library;

import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart' show kIsWeb;

import 'config.dart' show kUa;

/// 创建 Dio 实例（dio 默认 adapter：原生 IO / Web Browser）。
///
/// 原生平台为默认请求设置模拟客户端 `User-Agent`（kUa）；Web 平台**不设置**
/// —— 浏览器里 `User-Agent` 是 forbidden header，JS 无法自定义，强行设置会
/// 被服务器 CORS preflight 拒绝（'user-agent' 不在 Access-Control-Allow-Headers 中）。
Dio createDio({Duration? connectTimeout, Duration? receiveTimeout}) {
  final timeout = connectTimeout ?? const Duration(seconds: 15);
  return Dio(BaseOptions(
    connectTimeout: timeout,
    receiveTimeout: receiveTimeout ?? const Duration(seconds: 15),
    headers: kIsWeb ? null : {'User-Agent': kUa},
  ));
}