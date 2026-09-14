import 'package:flutter_test/flutter_test.dart';
import 'package:mnchat/core/models/homepage_modules.dart';

/// 主页模块（title / achieve / social_sign）解析器单测。
///
/// 覆盖：正常结构、`data` 嵌套、数字字符串容错、脏数据跳过、缺失降级
/// （返回 0 / 空列表 / null，绝不抛异常）。
void main() {
  group('homepageTitleId', () {
    test('取 title.data.match_title.use_title.id', () {
      expect(
        homepageTitleId({
          'title': {
            'data': {
              'match_title': {
                'use_title': {'id': 1077},
              },
            },
          },
        }),
        1077,
      );
    });

    test('数字字符串 id 也能解析', () {
      expect(
        homepageTitleId({
          'title': {
            'data': {
              'match_title': {
                'use_title': {'id': '1077'},
              },
            },
          },
        }),
        1077,
      );
    });

    test('缺少任一层级 → 0（不抛异常）', () {
      expect(homepageTitleId(null), 0);
      expect(homepageTitleId(const {}), 0);
      expect(homepageTitleId(const {'title': 1}), 0);
      expect(homepageTitleId(const {'title': <String, Object?>{}}), 0);
      expect(
        homepageTitleId(const {
          'title': {'data': 'x'},
        }),
        0,
      );
      expect(
        homepageTitleId(const {
          'title': {
            'data': {'match_title': 3},
          },
        }),
        0,
      );
      expect(
        homepageTitleId(const {
          'title': {
            'data': {
              'match_title': {'use_title': 'bad'},
            },
          },
        }),
        0,
      );
    });

    test('id 非数字 → 0', () {
      expect(
        homepageTitleId(const {
          'title': {
            'data': {
              'match_title': {
                'use_title': {'id': 'abc'},
              },
            },
          },
        }),
        0,
      );
    });
  });

  group('homepageMedals', () {
    test('解析 achieve.data.medal_list → [(id, level)]', () {
      final medals = homepageMedals(const {
        'achieve': {
          'data': {
            'medal_list': [
              {'id': 1001, 'level': 3},
              {'id': '1002', 'level': '5'},
            ],
          },
        },
      });
      expect(medals, [(1001, 3), (1002, 5)]);
    });

    test('脏条目跳过：非 Map / id 非正 / 缺 id', () {
      final medals = homepageMedals(const {
        'achieve': {
          'data': {
            'medal_list': [
              'bad',
              {'id': 0, 'level': 1},
              {'id': -3, 'level': 1},
              {'level': 2},
              {'id': 1003},
            ],
          },
        },
      });
      expect(medals, [(1003, 0)]);
    });

    test('缺模块 / 结构不符 → 空列表', () {
      expect(homepageMedals(null), isEmpty);
      expect(homepageMedals(const {}), isEmpty);
      expect(homepageMedals(const {'achieve': 'x'}), isEmpty);
      expect(homepageMedals(const {'achieve': <String, Object?>{}}), isEmpty);
      expect(
        homepageMedals(const {
          'achieve': {'data': <String, Object?>{}},
        }),
        isEmpty,
      );
      expect(
        homepageMedals(const {
          'achieve': {
            'data': {'medal_list': 'x'},
          },
        }),
        isEmpty,
      );
    });
  });

  group('homepageDeclaration', () {
    test('字段平铺在 social_sign 模块层', () {
      final d = homepageDeclaration(const {
        'social_sign': {'social_lab': 3, 'game_lab': 5},
      });
      expect(d, isNotNull);
      expect(d!.socialLab, 3);
      expect(d.gameLab, 5);
      expect(d.text, isNotEmpty);
    });

    test('字段包在 social_sign.data 里也能解析', () {
      final d = homepageDeclaration(const {
        'social_sign': {
          'data': {'social_lab': '3', 'game_lab': '5'},
        },
      });
      expect(d!.socialLab, 3);
      expect(d.gameLab, 5);
    });

    test('未设置（全 0）→ null', () {
      expect(
        homepageDeclaration(const {
          'social_sign': {'social_lab': 0, 'game_lab': 0},
        }),
        isNull,
      );
      expect(
        homepageDeclaration(const {
          'social_sign': {
            'data': {'social_lab': 0, 'game_lab': 0},
          },
        }),
        isNull,
      );
    });

    test('缺模块 / 结构不符 → null（不抛异常）', () {
      expect(homepageDeclaration(null), isNull);
      expect(homepageDeclaration(const {}), isNull);
      expect(homepageDeclaration(const {'social_sign': 7}), isNull);
    });
  });
}
