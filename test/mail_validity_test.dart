/// `mailValidityText`（邮件有效期文案，对齐游戏 `GetCurMailTimeStr`）回归。
///
/// 出处：`mainchatsystemmsg.lua:1025-1059`；文案取自 GetS：4086=「有效期：」、
/// 4087=「天」、4088=「小时」、30170=「有效期：永久」、611=「永久」、1057=「已过期」。
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:mnchat/core/services/message_center.dart';

void main() {
  const now = 1700000000;

  test('无 end_time（0）→ 永久', () {
    expect(mailValidityText(0, now: now), '有效期：永久');
    expect(mailValidityText(-5, now: now), '有效期：永久');
  });

  test('已过期 → 已过期', () {
    expect(mailValidityText(now - 1, now: now), '有效期：已过期');
    expect(mailValidityText(now, now: now), '有效期：已过期');
  });

  test('剩余 N 天 N 小时', () {
    // 2 天 3 小时
    expect(
      mailValidityText(now + 2 * 24 * 3600 + 3 * 3600, now: now),
      '有效期：2天3小时',
    );
    // 不足一天：0 天 5 小时
    expect(mailValidityText(now + 5 * 3600, now: now), '有效期：0天5小时');
  });

  test('剩余天数 > 30000 → 永久（GetS 30170）', () {
    expect(
      mailValidityText(now + 40000 * 24 * 3600, now: now),
      '有效期：永久',
    );
  });
}
