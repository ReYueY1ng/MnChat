import 'package:flutter_test/flutter_test.dart';
import 'package:mnchat/core/services/map_info.dart';

/// `/miniw/map` `get_map_list_info` 解析器单元测试。
///
/// 实测响应（2026-10-05）：以纯数字 owid 为键，名称在 `[owid].select.name`；
/// 查不到时只回 `{"urls": [...]}`。合法载荷 / 缺键 / 错类型 / 空 → 文档化
/// 结果（空 map 或跳过该条），绝不抛异常。
void main() {
  group('parseMapNames', () {
    test('合法载荷：取 select.name（实测片段）', () {
      final names = parseMapNames(const {
        '66241560236659': {
          'comment': {'like': 2, 'play_count': 2},
          'select': {
            'name': '一个幸运方块生存',
            'uin': 279630451,
            'memo': '挖掘幸运方块来获得资源',
            'worldtype': '4',
          },
          'init_time': 1687575350,
        },
      });
      expect(names, {'66241560236659': '一个幸运方块生存'});
    });

    test('多个 owid：逐条取；查不到的条目返回的名字照收', () {
      final names = parseMapNames(const {
        '64983134818931': {
          'select': {'name': '生存'},
        },
        '99999999999999': {
          'select': {'name': '作者已删除'},
        },
      });
      expect(names, {
        '64983134818931': '生存',
        '99999999999999': '作者已删除',
      });
    });

    test('缺 select：回退条目顶层 name', () {
      expect(parseMapNames(const {'7': {'name': '顶层名'}}), {'7': '顶层名'});
    });

    test('脏数据：urls 条 / 非 Map 条目 / 缺 name / 空 name 全跳过', () {
      expect(
        parseMapNames(const {
          'urls': ['http://map%d.mini1.cn/map/'],
          '1': 'oops',
          '2': {'select': <String, Object?>{}},
          '3': {'select': {'name': ''}},
          '4': {'select': {'name': '有效'}},
        }),
        {'4': '有效'},
      );
    });

    test('空 / 非 Map / 字符串 → 空 map', () {
      expect(parseMapNames(null), isEmpty);
      expect(parseMapNames('boom'), isEmpty);
      expect(parseMapNames(const []), isEmpty);
      expect(parseMapNames(const {}), isEmpty);
    });

    test('多个 owid 用 "-" 连接（mapservice.lua:5239-5244 的拼法）', () {
      expect(kMapIdSeparator, '-');
    });
  });
}
