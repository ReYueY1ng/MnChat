/// 主页布局解析回归：`data.layout` 是 **JSON 对象字符串**（数字键 = 模块条目，
/// 其余键 = 元数据），客户端此前只认 JSON 数组所以永远解析成空。
///
/// 载荷取自 2026-10-08 用真实账号（279630451）探到的响应，按原样内联。
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:mnchat/core/models/homepage_modules.dart';

/// 真实响应形状：`data.layout` 是一串 JSON 对象文本。
Map<String, Object?> _probedResponse() => <String, Object?>{
  'code': 0,
  'msg': '成功',
  'data': <String, Object?>{
    'layout':
        '{"1":{"moduleId":2,"sizeType":"roleShowComponent"},'
        '"10":{"moduleId":13,"sizeType":"smallComponent"},'
        '"11":{"moduleId":16,"sizeType":"smallComponent"},'
        '"12":{"sortIndex":1},'
        '"2":{"moduleId":3,"sizeType":"smallComponent"},'
        '"3":{"moduleId":4,"sizeType":"middleComponent"},'
        '"checkDataVersion":79872,'
        '"privacySet":{"CharmGiftVisibility":1}}',
  },
};

void main() {
  test('对象形态：数字键按数值升序成为条目，其余进 meta', () {
    final l = homeLayout(_probedResponse());
    // 数字键 1,2,3,10,11,12 → 6 条，按数值升序。
    expect(l.entries.length, 6);
    expect(
      l.entries.map((e) => e['moduleId']).whereType<int>().toList(),
      [2, 3, 4, 13, 16],
    );
    expect(l.entries[2], {'moduleId': 4, 'sizeType': 'middleComponent'});
    // 「12」只有 sortIndex，也是一条（原样保留，不臆造 moduleId）。
    expect(l.entries.last, {'sortIndex': 1});
    expect(l.meta['checkDataVersion'], 79872);
    expect(l.meta['privacySet'], isA<Map>());
    expect(l.isEmpty, isFalse);
  });

  test('保存 round-trip：数字键重编 1..N，元数据原样带回', () {
    final l = homeLayout(_probedResponse());
    final reordered = [l.entries.last, ...l.entries.take(l.entries.length - 1)];
    final encoded = encodeHomeLayout(reordered, meta: l.meta);
    // 必须是 JSON 对象（不是数组），键从 "1" 重新编号。
    expect(encoded.startsWith('{'), isTrue);
    final back = homeLayout(<String, Object?>{
      'code': 0,
      'data': <String, Object?>{'layout': encoded},
    });
    expect(back.entries.first, {'sortIndex': 1});
    expect(back.entries.length, 6);
    expect(back.meta['checkDataVersion'], 79872);
  });

  test('数组形态仍兼容（早期抓包）', () {
    final l = homeLayout(<String, Object?>{
      'code': 0,
      'data': <String, Object?>{
        'layout': '[{"moduleId":5,"sizeType":"smallComponent"}]',
      },
    });
    expect(l.entries.single['moduleId'], 5);
    expect(l.meta, isEmpty);
  });

  test('失败/脏数据 → 空布局（不抛）', () {
    expect(homeLayout(null).isEmpty, isTrue);
    expect(homeLayout('nope').isEmpty, isTrue);
    expect(homeLayout(<String, Object?>{'code': 1, 'data': {}}).isEmpty, isTrue);
    expect(homeLayout(<String, Object?>{'code': 0}).isEmpty, isTrue);
    expect(
      homeLayout(<String, Object?>{
        'code': 0,
        'data': <String, Object?>{'layout': 'not json'},
      }).isEmpty,
      isTrue,
    );
  });
}
