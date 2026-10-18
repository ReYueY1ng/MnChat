/// `query_recent_partner`（最近一起玩过的伙伴）响应的宽松解析。
///
/// 线上实测（2026-10-16，账号 279630451，`/server/friend`，走生产
/// `FriendClient.queryRecentPartner()`，3/3 `result:0`）：
/// ```
/// {"result":0,"partner_list":[[338892830,301,80384,44634364715060,1786814057]]}
/// ```
/// 五元组。**只有元素 0 能确认是迷你号**；其余字段含义尚无证据（元素 4 落在
/// epoch 秒区间，按"最近一起玩的时间"展示，属推测，已在 UI 上标注）。
/// 解析口径与仓库其它解析器一致：脏数据只跳过、绝不抛。
library;

/// 一位最近玩伴。
class RecentPartner {
  /// 迷你号（元组元素 0）。
  final int uin;

  /// 原始元组（字段含义未确定，原样保留，便于后续对齐服务端）。
  final List<Object?> raw;

  /// 最近一起玩的时间（epoch 秒）；元素 4 不在合理区间时为 null。
  final int? lastTimeSeconds;

  const RecentPartner({
    required this.uin,
    required this.raw,
    this.lastTimeSeconds,
  });

  /// 最近一起玩的时间（本地时区）。
  DateTime? get lastTime => lastTimeSeconds == null
      ? null
      : DateTime.fromMillisecondsSinceEpoch(lastTimeSeconds! * 1000);
}

/// epoch 秒的合理区间（2001-09 ~ 2033-05）；超出则不当时间用。
const int _kMinEpochSeconds = 1_000_000_000;
const int _kMaxEpochSeconds = 2_000_000_000;

/// 解析响应；`result`/`code` 非 0、缺 `partner_list`、脏条目 → 空列表 / 跳过。
List<RecentPartner> parseRecentPartners(Object? decoded) {
  if (decoded is! Map) return const [];
  final result = decoded['result'] ?? decoded['code'];
  if (result is num && result != 0) return const [];
  final list = decoded['partner_list'];
  if (list is! List) return const [];

  final out = <RecentPartner>[];
  final seen = <int>{};
  for (final row in list) {
    if (row is! List || row.isEmpty) continue;
    final uin = _toInt(row.first);
    if (uin == null || uin <= 0) continue;
    if (!seen.add(uin)) continue; // 同一人只留首次
    final last = row.length > 4 ? _toInt(row[4]) : null;
    out.add(
      RecentPartner(
        uin: uin,
        raw: row.cast<Object?>(),
        lastTimeSeconds:
            (last != null &&
                last >= _kMinEpochSeconds &&
                last <= _kMaxEpochSeconds)
            ? last
            : null,
      ),
    );
  }
  return out;
}

/// 宽松取 int（数字 / 数字字符串），其它 → null。
int? _toInt(Object? v) {
  if (v is num) return v.toInt();
  return int.tryParse('$v');
}
