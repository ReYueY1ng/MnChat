// 默契度衰减提醒的纯计算验证：边界（恰好 30 天）与保底规则。
import 'package:flutter_test/flutter_test.dart';
import 'package:mnchat/core/models/partner_nudge.dart';

void main() {
  final now = DateTime(2026, 10, 16, 12);

  group('未互动天数', () {
    test('没有互动时间 → null（不提醒）', () {
      expect(daysSinceInteraction(null, now: now), isNull);
      expect(isPartnerStale(null, now: now), isFalse);
    });

    test('未来时间按 0 天（时钟漂移不产生负数）', () {
      expect(
        daysSinceInteraction(now.add(const Duration(days: 3)), now: now),
        0,
      );
    });
  });

  group('衰减边界', () {
    test('29 天不提醒，恰好 30 天开始提醒', () {
      expect(
        isPartnerStale(now.subtract(const Duration(days: 29)), now: now),
        isFalse,
      );
      expect(
        isPartnerStale(now.subtract(const Duration(days: 30)), now: now),
        isTrue,
      );
    });

    test('30 天内默契度不变', () {
      expect(projectTacitnum(500, days: 30, hasRelation: false), 500);
      expect(projectTacitnum(500, days: 1, hasRelation: false), 500);
    });

    test('第 31 天起每天 -7', () {
      expect(projectTacitnum(500, days: 31, hasRelation: false), 493);
      expect(projectTacitnum(500, days: 40, hasRelation: false), 430);
    });

    test('有拍档关系保底 100，无关系保底 0', () {
      expect(projectTacitnum(150, days: 100, hasRelation: true), 100);
      expect(projectTacitnum(150, days: 100, hasRelation: false), 0);
      expect(projectTacitnum(500, days: 1000, hasRelation: false), 0);
    });

    test('默契度非正时原样返回（不产生负数）', () {
      expect(projectTacitnum(0, days: 90, hasRelation: false), 0);
      expect(projectTacitnum(-5, days: 90, hasRelation: false), 0);
    });
  });

  test('提醒文案', () {
    expect(staleDaysLabel(45), '已 45 天未互动');
  });
}
