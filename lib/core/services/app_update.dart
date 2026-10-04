/// 应用更新检查 —— **只在用户手动点「检查更新」时**发一次请求。
///
/// 数据源是 GitHub Release（构建产物也是 CI 上传到那里的，见
/// `.github/workflows/build_*.yml`）。应用不做任何后台轮询：这是一个逆向客户端，
/// 不该在没人看的时候自己去外网拉东西。
library;

import 'package:dio/dio.dart';

import '../net/http_factory.dart' show createDio;

/// 一次检查的结果。
class UpdateCheckResult {
  const UpdateCheckResult({
    required this.current,
    this.latest,
    this.url,
    this.error,
  });

  /// 当前版本（`core/app_info.dart` 的 `kAppVersion`）。
  final String current;

  /// 远端最新版本，已去掉 `v` 前缀；失败时为 null。
  final String? latest;

  /// 该 Release 的网页地址。
  final String? url;

  /// 失败原因（网络不通 / 限流 / 返回格式异常）；成功时为 null。
  final String? error;

  bool get ok => error == null && latest != null;

  /// 是否真的有新版本。
  bool get hasUpdate => ok && compareVersion(latest!, current) > 0;
}

/// 比较点分版本号：`a > b` 返回正数，相等返回 0。
///
/// 宽松 semver 口径：先比 `-` / `+` 之前的主版本数字段；主版本相同再比预发布号，
/// 带预发布号的比同主版本的正式版**旧**（`1.0.0-beta.2 < 1.0.0`）。
/// 非数字段一律当 0，绝不抛异常 —— 远端 tag 是自由文本。
int compareVersion(String a, String b) {
  final core = _compareNumeric(_corePart(a), _corePart(b));
  if (core != 0) return core;
  final pa = _prePart(a);
  final pb = _prePart(b);
  if (pa == null && pb == null) return 0;
  if (pa == null) return 1; // a 是正式版、b 是预发布 → a 更新
  if (pb == null) return -1;
  return _compareNumeric(pa, pb);
}

/// `-` / `+` 之前的主版本部分。
String _corePart(String s) {
  var i = s.indexOf('-');
  final plus = s.indexOf('+');
  if (plus >= 0 && (i < 0 || plus < i)) i = plus;
  return i < 0 ? s : s.substring(0, i);
}

/// `-` 之后的预发布号；没有则 null。
String? _prePart(String s) {
  final i = s.indexOf('-');
  if (i < 0) return null;
  final plus = s.indexOf('+', i);
  return plus < 0 ? s.substring(i + 1) : s.substring(i + 1, plus);
}

/// 逐段比数字（缺位补 0，非数字段当 0）。
int _compareNumeric(String a, String b) {
  List<int> parts(String s) => s
      .split('.')
      .map((p) => int.tryParse(RegExp(r'^\d+').stringMatch(p) ?? '') ?? 0)
      .toList();
  final pa = parts(a);
  final pb = parts(b);
  final n = pa.length > pb.length ? pa.length : pb.length;
  for (var i = 0; i < n; i++) {
    final x = i < pa.length ? pa[i] : 0;
    final y = i < pb.length ? pb[i] : 0;
    if (x != y) return x - y;
  }
  return 0;
}

/// GitHub Release 查询客户端。
class AppUpdateClient {
  AppUpdateClient({Dio? dio}) : _dio = dio ?? createDio();

  final Dio _dio;

  /// latest release 的 API；仓库地址与 `git remote`（GitHub）一致。
  static const String releaseApi =
      'https://api.github.com/repos/ReYueY1ng/MnChat/releases/latest';

  /// 查不到时给用户一个可点的兜底地址。
  static const String releasesPage =
      'https://github.com/ReYueY1ng/MnChat/releases';

  /// 查询最新版本。任何失败都返回带 [UpdateCheckResult.error] 的结果，不抛。
  Future<UpdateCheckResult> check(String current) async {
    try {
      final resp = await _dio.get<Object?>(
        releaseApi,
        options: Options(
          headers: const {'Accept': 'application/vnd.github+json'},
          // GitHub 未认证接口限流是 60 次/小时；手动检查够用，超时给短一点。
          receiveTimeout: const Duration(seconds: 10),
        ),
      );
      final data = resp.data;
      if (data is! Map) {
        return UpdateCheckResult(current: current, error: '返回格式异常');
      }
      final tag = '${data['tag_name'] ?? ''}';
      final url = '${data['html_url'] ?? releasesPage}';
      final version = tag.startsWith('v') ? tag.substring(1) : tag;
      if (version.isEmpty) {
        return UpdateCheckResult(current: current, error: 'Release 里没有版本号');
      }
      return UpdateCheckResult(current: current, latest: version, url: url);
    } catch (e) {
      return UpdateCheckResult(current: current, error: '$e');
    }
  }
}
