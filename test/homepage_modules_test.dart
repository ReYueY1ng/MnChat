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

  // 计数类解析器约定：模块缺失 / 结构不符 / 非 0 code 返回的空 data → null；
  // 模块存在但值确为 0 → 0。以下每组覆盖：正常 / 数字字符串 / 缺失 / 类型不符 /
  // 非零 code（getUserHomepage 在 code!=0 时返回空 map，等价于 `{}`）。
  group('homepageCharmValue', () {
    test('取 charm.data.charm_value', () {
      expect(
        homepageCharmValue(const {
          'charm': {
            'data': {'charm_value': 12345},
          },
        }),
        12345,
      );
    });

    test('数字字符串容错', () {
      expect(
        homepageCharmValue(const {
          'charm': {
            'data': {'charm_value': '888'},
          },
        }),
        888,
      );
    });

    test('模块存在但值为 0 → 0（区别于缺失）', () {
      expect(
        homepageCharmValue(const {
          'charm': {
            'data': {'charm_value': 0},
          },
        }),
        0,
      );
    });

    test('缺失 / 类型不符 / 非零 code 空响应 → null', () {
      expect(homepageCharmValue(null), isNull);
      expect(homepageCharmValue(const {}), isNull);
      expect(homepageCharmValue(const {'charm': 1}), isNull);
      expect(
        homepageCharmValue(const {
          'charm': {
            'data': {'charm_value': 'abc'},
          },
        }),
        isNull,
      );
    });
  });

  group('homepageWorkCount', () {
    test('map_list 条数 + goods_count.total', () {
      expect(
        homepageWorkCount(const {
          'map': {
            'data': {
              'map_list': [
                {'id': 1, 'name': 'a'},
                {'id': 2, 'name': 'b'},
              ],
              'goods_count': {'total': 3},
            },
          },
        }),
        5,
      );
    });

    test('缺 goods_count 时回退统计 goods[].data.list', () {
      expect(
        homepageWorkCount(const {
          'map': {
            'data': {
              'map_list': [
                {'id': 1},
              ],
              'goods': {
                'r1': {
                  'data': {
                    'list': [
                      {'id': 10},
                      {'id': 11},
                    ],
                  },
                },
              },
            },
          },
        }),
        3,
      );
    });

    test('缺失 / 类型不符 / 非零 code 空响应 → null', () {
      expect(homepageWorkCount(null), isNull);
      expect(homepageWorkCount(const {}), isNull);
      expect(homepageWorkCount(const {'map': 'x'}), isNull);
      expect(
        homepageWorkCount(const {
          'map': {
            'data': {'map_list': 'x'},
          },
        }),
        0,
      );
    });
  });

  group('homepageWorks', () {
    test('解析 map_list → [(id, name)]', () {
      final works = homepageWorks(const {
        'map': {
          'data': {
            'map_list': [
              {'id': 11, 'name': '跑酷'},
              {'id': '12', 'name': '生存'},
            ],
          },
        },
      });
      expect(works.length, 2);
      expect(works[0].id, 11);
      expect(works[0].name, '跑酷');
      expect(works[1].id, 12);
    });

    test('脏条目跳过 / 空名回退 #id', () {
      final works = homepageWorks(const {
        'map': {
          'data': {
            'map_list': [
              'bad',
              {'id': 0, 'name': 'x'},
              {'id': 13},
            ],
          },
        },
      });
      expect(works.length, 1);
      expect(works.first.id, 13);
      expect(works.first.name, '#13');
    });

    test('缺失 / 非零 code 空响应 → 空列表', () {
      expect(homepageWorks(null), isEmpty);
      expect(homepageWorks(const {}), isEmpty);
      expect(
        homepageWorks(const {
          'map': {
            'data': {'map_list': 5},
          },
        }),
        isEmpty,
      );
    });
  });

  group('homepagePostingCount', () {
    test('优先取 posting.data.posting_count', () {
      expect(
        homepagePostingCount(const {
          'posting': {
            'data': {'posting_count': 7},
          },
        }),
        7,
      );
    });

    test('无 posting_count 时统计 posting_data.list 中 homepage_hide != 1', () {
      expect(
        homepagePostingCount(const {
          'posting': {
            'data': {
              'posting_data': {
                'list': [
                  {'pid': 1},
                  {'pid': 2, 'homepage_hide': 1},
                  {'pid': 3, 'homepage_hide': 0},
                ],
              },
            },
          },
        }),
        2,
      );
    });

    test('缺失 / 类型不符 / 非零 code 空响应 → null', () {
      expect(homepagePostingCount(null), isNull);
      expect(homepagePostingCount(const {}), isNull);
      expect(homepagePostingCount(const {'posting': 1}), isNull);
      expect(
        homepagePostingCount(const {
          'posting': {
            'data': {'posting_data': 'x'},
          },
        }),
        0,
      );
    });
  });

  group('homepageChaseLightCount', () {
    test('取 avatar_collect.data.count', () {
      expect(
        homepageChaseLightCount(const {
          'avatar_collect': {
            'data': {'count': 42},
          },
        }),
        42,
      );
    });

    test('数字字符串容错', () {
      expect(
        homepageChaseLightCount(const {
          'avatar_collect': {
            'data': {'count': '9'},
          },
        }),
        9,
      );
    });

    test('缺失 / 类型不符 / 非零 code 空响应 → null', () {
      expect(homepageChaseLightCount(null), isNull);
      expect(homepageChaseLightCount(const {}), isNull);
      expect(homepageChaseLightCount(const {'avatar_collect': 1}), isNull);
      expect(
        homepageChaseLightCount(const {
          'avatar_collect': {
            'data': {'count': 'x'},
          },
        }),
        isNull,
      );
    });
  });

  group('homepageSkinCount', () {
    test('统计 skin_list / mount_list / weapon_list / seat.seat_list', () {
      expect(
        homepageSkinCount(const {
          'skin': {
            'data': {
              'skin_list': [
                {'SkinID': 1},
                {'SkinID': 2},
              ],
              'mount_list': [
                {'RiderID': 3},
              ],
              'weapon_list': [
                {'id': 4},
              ],
              'seat': {
                'seat_list': [
                  {'ID': 5},
                  {'ID': 6},
                ],
              },
            },
          },
        }),
        6,
      );
    });

    test('缺失 / 类型不符 / 非零 code 空响应 → null', () {
      expect(homepageSkinCount(null), isNull);
      expect(homepageSkinCount(const {}), isNull);
      expect(homepageSkinCount(const {'skin': 'x'}), isNull);
      expect(
        homepageSkinCount(const {
          'skin': {
            'data': <String, Object?>{},
          },
        }),
        0,
      );
    });
  });

  group('homepageHeadFrameCount', () {
    test('head_frame.data 为数组 → 条数', () {
      expect(
        homepageHeadFrameCount(const {
          'head_frame': {
            'data': [
              {'id': 1},
              {'id': 2},
              {'id': 3},
            ],
          },
        }),
        3,
      );
    });

    test('缺失 / data 非数组 / 非零 code 空响应 → null', () {
      expect(homepageHeadFrameCount(null), isNull);
      expect(homepageHeadFrameCount(const {}), isNull);
      expect(
        homepageHeadFrameCount(const {
          'head_frame': {'data': 'x'},
        }),
        isNull,
      );
    });
  });

  group('homepageMedals2', () {
    test('解析 achieve2.data 数组 → [(id, level)]（max_level 优先）', () {
      final medals = homepageMedals2(const {
        'achieve2': {
          'data': [
            {'id': 1001, 'max_level': 3, 'level': 1},
            {'id': '1002', 'level': '5'},
          ],
        },
      });
      expect(medals, [(1001, 3), (1002, 5)]);
    });

    test('脏条目跳过：非 Map / id 非正', () {
      final medals = homepageMedals2(const {
        'achieve2': {
          'data': [
            'bad',
            {'id': 0},
            {'id': -1},
            {'id': 1003},
          ],
        },
      });
      expect(medals, [(1003, 0)]);
    });

    test('缺失 / 非零 code 空响应 → 空列表', () {
      expect(homepageMedals2(null), isEmpty);
      expect(homepageMedals2(const {}), isEmpty);
      expect(
        homepageMedals2(const {
          'achieve2': {'data': 'x'},
        }),
        isEmpty,
      );
    });
  });

  group('homepageStats', () {
    test('解析 role_info 四项统计', () {
      final s = homepageStats(const {
        'role_info': {
          'data': {
            'profile': {
              'relation': {'friend_attention': 12, 'friend_beattention': 34},
            },
            'popularity': 567,
            'credit': 100,
          },
        },
      });
      expect(s, isNotNull);
      expect(s!.following, 12);
      expect(s.followers, 34);
      expect(s.popularity, 567);
      expect(s.credit, 100);
    });

    test('数字字符串容错；单项缺失 → null（区别于 0）', () {
      final s = homepageStats(const {
        'role_info': {
          'data': {
            'profile': {
              'relation': {'friend_attention': '7'},
            },
            'credit': 0,
          },
        },
      });
      expect(s!.following, 7);
      expect(s.followers, isNull);
      expect(s.popularity, isNull);
      expect(s.credit, 0);
    });

    test('role_info 缺失 / 类型不符 / 非零 code 空响应 → null', () {
      expect(homepageStats(null), isNull);
      expect(homepageStats(const {}), isNull);
      expect(homepageStats(const {'role_info': 1}), isNull);
      expect(
        homepageStats(const {
          'role_info': {'data': 'x'},
        }),
        isNull,
      );
    });
  });
}
