/// 请求失败上报总线 —— 把「哪个请求失败了、服务端码是什么」汇总给 UI。
///
/// 背景：本仓库的客户端大量「静默降级」（失败 → 空数据），UI 只会显示空列表，
/// 分不清是「本来没数据」还是「请求挂了」。所有失败最终归到 [RequestErrorBus]：
///
/// - 业务码失败（HTTP 200 但 `code != 0`）：由各 client 调用 [RequestErrorBus.report]
///   （例如 [PartnerClient] 的 `code=9` 排队、`code=2` 服务未注册）；
/// - 传输层失败（超时 / 断网 / 4xx / 5xx）：[createDio] 的拦截器统一上报。
///
/// UI 侧：`RequestErrorIndicator` 显示常驻角标与详情弹窗，`RequestErrorListener`
/// 弹吐司（见 lib/ui/widgets/request_error_indicator.dart）。
///
/// 上报的 URL 必须已脱敏（[redactUrl]）：s7 包裹后的查询串里带着会话令牌。
library;

import 'dart:async';

import 'package:flutter/foundation.dart';

import '../utils/log.dart' show redactUrl;

/// 从请求 URL 推一个可读标签：`.../miniw/dynamics?act=pull_postings` →
/// `dynamics.pull_postings`（没有 `act` 时用 `cmd` / 路径末段）。
String labelFromUrl(String url) {
  final uri = Uri.tryParse(url);
  final segs = (uri?.path ?? url).split('/').where((s) => s.isNotEmpty).toList();
  final name = segs.isNotEmpty ? segs.last : url;
  final q = uri?.queryParameters ?? const <String, String>{};
  final act = q['act'] ?? q['cmd'] ?? q['method'] ?? '';
  return act.isEmpty ? name : '$name.$act';
}

/// 响应业务码检查：`code` / `ret` / `result`（数字或数字字符串）任一非 0
/// → 上报给 [RequestErrorBus] 并返回 true。
///
/// 各业务客户端解码响应后调一次，就能把「静默降级成空数据」的失败暴露到 UI。
/// 只认数字/数字字符串状态值：`result` 传对象（业务载荷）时不会被当成失败。
bool reportIfFailed(
  String url,
  Object? decoded, {
  String? label,
  Set<String> statusKeys = const <String>{'code', 'ret', 'result'},
}) {
  if (decoded is! Map) return false;
  int? code;
  String? statusKey;
  for (final key in statusKeys) {
    final v = decoded[key];
    if (v is num) {
      if (v != 0) {
        code = v.toInt();
        statusKey = key;
      }
    } else if (v is String) {
      final n = int.tryParse(v);
      if (n != null && n != 0) {
        code = n;
        statusKey = key;
      }
    }
    if (code != null) break;
  }
  if (code == null) return false;
  final msg = decoded['msg'] ?? decoded['errmsg'] ?? decoded['err_msg'] ?? '';
  RequestErrorBus.instance.report(
    label: label ?? labelFromUrl(url),
    endpoint: redactUrl(url),
    code: code,
    statusKey: statusKey,
    message: '$msg',
  );
  return true;
}

/// 响应是否**明确**业务成功。
///
/// 与 [reportIfFailed] 同一组状态键、同一套数值口径（只认数字/数字字符串），
/// 判定为：至少有一个状态键的值为 0，**且**没有任何状态键为非 0。
///
/// 为什么不再让调用方自己写 `resp['result'] ?? resp['ret']`：那种写法散在页面
/// 里，字段顺序或口径一旦和 [reportIfFailed] 分叉，就会出现「UI 说成功、失败
/// 角标同时在报」的相互矛盾提示（例：`{code=0, ret=9}` 旧写法取到 code=0 便
/// 算成功，上报那侧却按 ret=9 记了失败）。
///
/// 刻意保守：状态键缺失、值是业务对象（`result` 直接放载荷）、或响应不是 Map
/// 都返回 false，以免把「空表 / 解析失败」误当成功。
bool responseOk(
  Object? decoded, {
  Set<String> statusKeys = const <String>{'code', 'ret', 'result'},
}) {
  if (decoded is! Map) return false;
  var sawZero = false;
  for (final key in statusKeys) {
    final v = decoded[key];
    final n = v is num ? v.toInt() : (v is String ? int.tryParse(v) : null);
    if (n == null) continue;
    if (n != 0) return false;
    sawZero = true;
  }
  return sawZero;
}

/// 一次请求失败记录。
@immutable
class RequestFailure {
  /// 人话标签，例如「拍档列表」。
  final String label;

  /// 已脱敏的请求地址（含查询串，敏感参数为 `***`）。
  final String endpoint;

  /// 服务端业务码 / HTTP 状态码；传输异常为 null。
  final int? code;

  /// 这个码是从响应的哪个字段读出来的：`code` / `ret` / `result`。
  ///
  /// 关键区别：`code`/`ret` 是**网关**的码（[describeRequestCode] 那张取自
  /// `errorcode.lua` 的表就是它的）；而 `/server/friend` 这类服务返回的信封是
  /// `{"result":N}`，`result` 是**服务自己的**业务码，同一个 2 在那里不代表
  /// `UNKNOW_SERVICE`（实测：`query_friend_label_pool` 回 `{"result":2}`，而把
  /// cmd 拼错的请求回的是**空 body**）。所以摘要必须把字段名写对，并只对网关
  /// 码附上释义，否则会把「好友服务的业务错误」说成「服务未注册」。
  final String? statusKey;

  /// 服务端 `msg` 或异常文本（可能为空）。
  final String message;

  /// 最近一次发生时间。
  final DateTime at;

  /// 同一失败重复出现的次数（去重后的计数）。
  final int count;

  const RequestFailure({
    required this.label,
    required this.endpoint,
    required this.at,
    this.code,
    this.statusKey,
    this.message = '',
    this.count = 1,
  });

  /// 一行摘要：`拍档列表（code=9 NO_ROUTE）` / `好友标签池（result=2）`。
  ///
  /// `result` 不附释义：它不是网关码，用网关表解释会得出错误结论。
  String get summary {
    if (code == null) return '$label（网络异常）';
    final key = statusKey ?? 'code';
    final suffix = key == 'result' ? '' : ' ${describeRequestCode(code!)}';
    return '$label（$key=$code$suffix）';
  }

  RequestFailure copyWith({DateTime? at, int? count}) => RequestFailure(
    label: label,
    endpoint: endpoint,
    code: code,
    statusKey: statusKey,
    message: message,
    at: at ?? this.at,
    count: count ?? this.count,
  );

  /// 视作同一条失败：同标签同端点同字段同码。
  ///
  /// `statusKey` 也算进 key：`code=2`（网关 UNKNOW_SERVICE）与 `result=2`
  /// （好友服务自己的业务码）是两回事，不该合并成一条。
  bool sameAs(RequestFailure other) =>
      label == other.label &&
      endpoint == other.endpoint &&
      code == other.code &&
      statusKey == other.statusKey;
}

/// 业务码 → 人话。取自反编译 `luascript/errorcode.lua` 与线上实测，
/// 未收录的码原样返回 `#N`。
///
/// **只适用于网关码**（响应里的 `code` / `ret`）。`/server/friend` 这类服务
/// 返回 `{"result":N}`，那是服务自己的码表，用这张表解释会得出错误结论
/// （实测：`query_friend_label_pool` 回 `{"result":2}`，而拼错的 cmd 回空 body；
/// 这里的 2 不是 `UNKNOW_SERVICE`）。[RequestFailure.summary] 因此对 `result`
/// 不附释义。
String describeRequestCode(int code) {
  switch (code) {
    case 1:
      return '参数错误';
    case 2:
      return 'UNKNOW_SERVICE 服务未注册';
    case 8:
      return 'DEAD_NODE 节点不可用';
    case 9:
      return 'NO_ROUTE 网关排队/选路失败';
    case 10:
      return 'NO_CANDIDATE 无可用节点';
    case 23:
      return 'WAITTING 网关排队中';
    case 7012:
      return '认证失败';
    case 7013:
      return '账号鉴权信息失效';
    default:
      return '#$code';
  }
}

/// 请求失败总线（进程内单例）。
///
/// 同一 (label, endpoint, code) 的失败只保留一条，重复出现时更新时间与计数，
/// 不会刷屏；[stream] 只对新出现的失败发事件（吐司用）。
class RequestErrorBus {
  RequestErrorBus._();

  /// 全局实例。UI 通过 providers 里的 `requestErrorBusProvider` 拿它。
  static final RequestErrorBus instance = RequestErrorBus._();

  /// 最多保留多少条失败记录。
  static const int maxEntries = 30;

  final List<RequestFailure> _entries = <RequestFailure>[];
  final ValueNotifier<List<RequestFailure>> _failures =
      ValueNotifier<List<RequestFailure>>(const <RequestFailure>[]);
  final StreamController<RequestFailure> _events =
      StreamController<RequestFailure>.broadcast();

  /// 当前失败列表（最新在前）；UI 用 ValueListenableBuilder 监听。
  ValueListenable<List<RequestFailure>> get failures => _failures;

  /// 新失败事件（去重后）；吐司用。
  Stream<RequestFailure> get stream => _events.stream;

  /// 上报一次失败。[endpoint] 请传 [redactUrl] 处理过的地址。
  ///
  /// [statusKey] 是读出该码的字段名（`code`/`ret`/`result`），影响摘要措辞与
  /// 去重键：`result` 属于服务自己的码表，不能被当成网关的 `UNKNOW_SERVICE`。
  void report({
    required String label,
    required String endpoint,
    int? code,
    String? statusKey,
    String message = '',
  }) {
    final now = DateTime.now();
    final entry = RequestFailure(
      label: label,
      endpoint: endpoint,
      code: code,
      statusKey: statusKey,
      message: message,
      at: now,
    );
    final i = _entries.indexWhere((e) => e.sameAs(entry));
    if (i >= 0) {
      // 重复失败：计数 +1、刷新时间、提到最前，但不发事件（避免刷屏）。
      _entries[i] = _entries[i].copyWith(at: now, count: _entries[i].count + 1);
      final existing = _entries.removeAt(i);
      _entries.insert(0, existing);
    } else {
      _entries.insert(0, entry);
      if (_entries.length > maxEntries) {
        _entries.removeRange(maxEntries, _entries.length);
      }
      _events.add(entry);
    }
    _failures.value = List<RequestFailure>.unmodifiable(_entries);
  }

  /// 清空全部失败记录（详情弹窗的「清空」）。
  void clear() {
    _entries.clear();
    _failures.value = const <RequestFailure>[];
  }
}
