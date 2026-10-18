/// 拍档"默契度衰减"提醒的纯计算（无 IO、无 Flutter）。
///
/// 官方规则（调研自官方社区帖，见 `notes/facts/miniworld-social-ecosystem.md`）：
/// 一起玩 / 单聊 / 分享 / 赠礼都会涨默契度（每日有上限）；**连续 30 天不互动起
/// 每天 -7**；有拍档关系保底 100，无关系保底 0；双方默契度达 100 才能建立关系。
/// 这里只做"要不要提醒 / 再不互动会掉到多少"的算术，不碰网络。
library;

/// 开始衰减的连续未互动天数。
const int kPartnerStaleDays = 30;

/// 衰减速率（每天）。
const int kPartnerDecayPerDay = 7;

/// 有拍档关系时的默契度保底。
const int kPartnerTacitFloorWithRelation = 100;

/// 无关系时的保底。
const int kPartnerTacitFloorNoRelation = 0;

/// [lastInteractAt] 距 [now] 已过去多少整天；两个参数任一为空返回 null。
int? daysSinceInteraction(DateTime? lastInteractAt, {DateTime? now}) {
  if (lastInteractAt == null) return null;
  final base = now ?? DateTime.now();
  final diff = base.difference(lastInteractAt);
  if (diff.isNegative) return 0;
  return diff.inDays;
}

/// 是否已进入衰减区（连续未互动 ≥ [kPartnerStaleDays] 天）。
///
/// 没有互动时间（老数据 / 对方从没聊过）→ false：宁可不提醒，也不误报。
bool isPartnerStale(DateTime? lastInteractAt, {DateTime? now}) {
  final days = daysSinceInteraction(lastInteractAt, now: now);
  return days != null && days >= kPartnerStaleDays;
}

/// 按官方规则预测默契度：[days] 天不互动后的值。
///
/// - `days <= 30` → 原值不变；
/// - 之后每天 -7，且不低于 [floor]（有拍档关系 100 / 无关系 0）。
int projectTacitnum(
  int current, {
  required int days,
  required bool hasRelation,
}) {
  if (current <= 0 || days <= kPartnerStaleDays) return current < 0 ? 0 : current;
  final floor = hasRelation
      ? kPartnerTacitFloorWithRelation
      : kPartnerTacitFloorNoRelation;
  final decayed = current - kPartnerDecayPerDay * (days - kPartnerStaleDays);
  return decayed < floor ? floor : decayed;
}

/// 提醒文案：`已 N 天未互动`。
String staleDaysLabel(int days) => '已 $days 天未互动';
