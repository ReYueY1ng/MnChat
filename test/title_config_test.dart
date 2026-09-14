import 'package:flutter_test/flutter_test.dart';
import 'package:mnchat/core/services/title_config.dart';

const _index = '''
{
  MiniWorks = '2cabdc2831eda608',
  title_manager = 'e15d0771fae187f3',
  shop = '86000fe6ed327ce4',
}''';

const _titleCfg = '''
{
  title_list = {
    {
      ItemID = 1008311,
      ID = 20055,
      sort = 3,
      Name = '城市规划师',
      photo = 'act_58_title_2005',
    },
    {
      ID = 2020,
      sort = 5,
      Name = '自定义称号（7天）',
    },
    {
      ID = 2033,
      Name = "双引号称号",
    },
  },
  title_typeList = {
    { ID = 1, sort = 1 },
  },
}''';

void main() {
  group('parseConfigIndex', () {
    test('解析 name → md5', () {
      final m = parseConfigIndex(_index);
      expect(m['title_manager'], 'e15d0771fae187f3');
      expect(m['shop'], '86000fe6ed327ce4');
    });
  });

  group('parseTitleNames', () {
    test('解析 title_list 的 ID → Name', () {
      final names = parseTitleNames(_titleCfg);
      expect(names[20055], '城市规划师');
      expect(names[2020], '自定义称号（7天）');
    });

    test('兼容双引号', () {
      final names = parseTitleNames(_titleCfg);
      expect(names[2033], '双引号称号');
    });

    test('title_typeList 无 Name 时被忽略', () {
      final names = parseTitleNames(_titleCfg);
      expect(names.containsKey(1), isFalse);
    });

    test('空文本返回空 map', () {
      expect(parseTitleNames(''), isEmpty);
      expect(parseConfigIndex(''), isEmpty);
    });
  });
}
