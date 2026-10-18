// 最近玩伴解析：用 2026-10-16 线上实测的原始响应当夹具，并覆盖脏数据。
import 'package:flutter_test/flutter_test.dart';
import 'package:mnchat/core/models/recent_partner.dart';

void main() {
  test('线上实测夹具有一位玩伴，且只把合理区间的元素 4 当时间', () {
    // 原始证据：/tmp/ulw-run-mnchat/evidence/probe_recent_partner.txt
    final decoded = <String, Object?>{
      'result': 0,
      'partner_list': <Object?>[
        <Object?>[338892830, 301, 80384, 44634364715060, 1786814057],
      ],
    };
    final partners = parseRecentPartners(decoded);
    expect(partners, hasLength(1));
    expect(partners.single.uin, 338892830);
    expect(partners.single.lastTimeSeconds, 1786814057);
    expect(partners.single.lastTime, isNotNull);
  });

  test('result/code 非 0 → 空列表', () {
    expect(parseRecentPartners({'result': 8, 'partner_list': <Object?>[]}), isEmpty);
    expect(
      parseRecentPartners({
        'code': 9,
        'partner_list': <Object?>[
          <Object?>[1],
        ],
      }),
      isEmpty,
    );
  });

  test('非 Map / 缺字段 → 空列表', () {
    expect(parseRecentPartners(null), isEmpty);
    expect(parseRecentPartners('nope'), isEmpty);
    expect(parseRecentPartners({'result': 0}), isEmpty);
    expect(parseRecentPartners({'result': 0, 'partner_list': 42}), isEmpty);
  });

  test('脏条目只跳过，不抛', () {
    final partners = parseRecentPartners({
      'result': 0,
      'partner_list': <Object?>[
        <Object?>[], // 空元组
        'x', // 非 List
        <Object?>[0, 1], // uin 非正
        <Object?>['abc', 1], // uin 非数字
        <Object?>[7, 1, 2, 3], // 少元素 → 时间为 null
        <Object?>[8, 1, 2, 3, 5], // 元素 4 不在 epoch 区间 → 时间为 null
        <Object?>[7, 9], // 重复 uin → 只留首次
      ],
    });
    expect(partners.map((p) => p.uin).toList(), [7, 8]);
    expect(partners.first.lastTimeSeconds, isNull);
    expect(partners.last.lastTimeSeconds, isNull);
  });

  test('数字字符串 uin 也接受（服务端两种形态都见过）', () {
    final partners = parseRecentPartners({
      'result': 0,
      'partner_list': <Object?>[
        <Object?>['123456', 1],
      ],
    });
    expect(partners.single.uin, 123456);
  });
}
