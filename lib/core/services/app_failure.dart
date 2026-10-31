/// 统一的失败类型 —— 把「传输层异常 / HTTP 状态 / 协议解析 / 业务码 / 本地」
/// 收敛成一组可穷举的变体，避免各客户端各自拼错误文案。
///
/// 目前只用于 [createDio] 的错误上报（[classifyDio]）；后续客户端从
/// 抛裸 `DioException` / 返回空 Map 迁移时可以直接复用。
library;

import 'package:dio/dio.dart';

/// 一次失败的分类结果（sealed，可对变体做穷举 switch）。
sealed class AppFailure {
  const AppFailure._();

  /// 连不上服务端（断网 / DNS / socket 断开 / 证书问题）。
  const factory AppFailure.network() = NetworkFailure;

  /// 连接 / 发送 / 接收超时。
  const factory AppFailure.timeout() = TimeoutFailure;

  /// 服务端返回了非 2xx 的 HTTP 状态。
  const factory AppFailure.httpStatus(int status, {String? detail}) =
      HttpStatusFailure;

  /// 响应格式不对（解不开 / 缺字段）。
  const factory AppFailure.protocol(String detail) = ProtocolFailure;

  /// HTTP 成功但业务码非 0。
  const factory AppFailure.business(int code, String? message) =
      BusinessFailure;

  /// 本地原因（被取消、缓存/文件读写失败等）。
  const factory AppFailure.local(String detail) = LocalFailure;

  /// 一行可直接展示给人看的摘要（永不为空）。
  String get summary;
}

final class NetworkFailure extends AppFailure {
  const NetworkFailure() : super._();

  @override
  String get summary => '网络连接失败';
}

final class TimeoutFailure extends AppFailure {
  const TimeoutFailure() : super._();

  @override
  String get summary => '请求超时';
}

final class HttpStatusFailure extends AppFailure {
  const HttpStatusFailure(this.status, {this.detail}) : super._();

  /// HTTP 状态码（拿不到时为 0）。
  final int status;

  /// 服务端的 statusMessage 等补充说明。
  final String? detail;

  @override
  String get summary {
    final d = detail;
    return d == null || d.isEmpty ? 'HTTP $status' : 'HTTP $status（$d）';
  }
}

final class ProtocolFailure extends AppFailure {
  const ProtocolFailure(this.detail) : super._();

  /// 具体哪里解析失败。
  final String detail;

  @override
  String get summary => detail.isEmpty ? '协议解析失败' : '协议解析失败：$detail';
}

final class BusinessFailure extends AppFailure {
  const BusinessFailure(this.code, this.message) : super._();

  /// 业务码（`code` / `ret` / `result`）。
  final int code;

  /// 服务端 `msg`，可能为空。
  final String? message;

  @override
  String get summary {
    final m = message;
    return m == null || m.isEmpty ? '业务错误 $code' : '业务错误 $code：$m';
  }
}

final class LocalFailure extends AppFailure {
  const LocalFailure(this.detail) : super._();

  /// 本地失败原因。
  final String detail;

  @override
  String get summary => detail.isEmpty ? '本地错误' : detail;
}

/// 把 dio 的异常映射成 [AppFailure]。
///
/// 只做分类，不改变请求/重试行为：`badResponse` 保留原始状态码，
/// 超时与连接类异常分别归到 timeout / network，取消归到 local（「已取消」）。
AppFailure classifyDio(DioException e) {
  return switch (e.type) {
    DioExceptionType.connectionTimeout ||
    DioExceptionType.sendTimeout ||
    DioExceptionType.receiveTimeout ||
    DioExceptionType.transformTimeout =>
      const AppFailure.timeout(),
    DioExceptionType.connectionError ||
    DioExceptionType.unknown ||
    DioExceptionType.badCertificate =>
      const AppFailure.network(),
    DioExceptionType.badResponse => AppFailure.httpStatus(
        e.response?.statusCode ?? 0,
        detail: _nonEmpty(e.response?.statusMessage),
      ),
    DioExceptionType.cancel => const AppFailure.local('已取消'),
  };
}

String? _nonEmpty(String? s) => s == null || s.isEmpty ? null : s;
