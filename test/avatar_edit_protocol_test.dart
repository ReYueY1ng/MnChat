import 'package:flutter_test/flutter_test.dart';
import 'package:mnchat/core/services/family.dart'
    show FamilyClient, parseShowFamily;
import 'package:mnchat/core/services/profile.dart'
    show DiyAuditState, parseDiyHeadInfo;
import 'package:mnchat/core/services/title_config.dart'
    show
        OwnedTitle,
        TitleCatalog,
        TitleConfigEntry,
        TitleShowData,
        TitleType,
        formatTitleDate,
        parseConfigIndex,
        parseTitleEntries,
        parseTitleNames,
        parseTitleTypes;

/// 头像编辑三页签（DIY / 称号 / 家族）协议解析的纯函数单测。
void main() {
  group('parseDiyHeadInfo（DIY 审核态）', () {
    test('pass_url 审核通过：可用且无审核文案', () {
      final info = parseDiyHeadInfo({
        'use_diy': 1,
        'type': 1,
        'id': 1,
        'diy_header': {'pass_url': 'https://x/pass.png', 'aduit_fail': 0},
      });
      expect(info, isNotNull);
      expect(info!.auditState, DiyAuditState.approved);
      expect(info.displayUrl, 'https://x/pass.png');
      expect(info.selectable, isTrue);
      expect(info.auditLabel, isNull);
      expect(info.useDiy, isTrue);
      expect(info.type, 1);
      expect(info.id, 1);
    });

    test('pre_url 审核中：展示本人可见图 + 文案', () {
      final info = parseDiyHeadInfo({
        'use_diy': 1,
        'diy_header': {'pre_url': 'https://x/pre.png', 'aduit_fail': 0},
      });
      expect(info!.auditState, DiyAuditState.pending);
      expect(info.displayUrl, 'https://x/pre.png');
      expect(info.selectable, isTrue);
      expect(info.auditLabel, '审核中');
    });

    test('aduit_fail==1 审核失败：不可选，仍展示本人可见图', () {
      final info = parseDiyHeadInfo({
        'use_diy': 1,
        'diy_header': {'pre_url': 'https://x/pre.png', 'aduit_fail': 1},
      });
      expect(info!.auditState, DiyAuditState.failed);
      expect(info.auditLabel, '审核失败');
      expect(info.selectable, isFalse);
      expect(info.displayUrl, 'https://x/pre.png');
    });

    test('无 diy_header 且无本体字段 → null；非 Map → null', () {
      expect(parseDiyHeadInfo({'diy_header': null}), isNull);
      expect(parseDiyHeadInfo('x'), isNull);
    });
  });

  group('称号配置解析', () {
    const cfg = '''
title_list = {
  { ItemID = 1008311, ID = 20055, sort = 3, Name = '城市规划师' },
  { ItemID = 100856, ID = 2020, sort = 5, Name = '自定义称号（7天）' },
},
title_typeList = {
  { id = 5, sort = 5, name = '自定义' },
  { id = 2, sort = 2, name = '开发者' },
  { id = 3, sort = 4, name = '其他' },
  { id = 4, sort = 3, name = '迷你季' },
},
''';

    test('title_list → ID:名称+sort（小写 title_typeList 不误入）', () {
      final entries = parseTitleEntries(cfg);
      expect(entries.length, 2);
      expect(entries[20055]!.name, '城市规划师');
      expect(entries[20055]!.sort, 3);
      expect(entries[2020]!.name, '自定义称号（7天）');
      expect(entries[2020]!.sort, 5);
    });

    test('title_typeList → 分类（id/name/sort）', () {
      final types = parseTitleTypes(cfg);
      expect(types.length, 4);
      final catalog = TitleCatalog(entries: parseTitleEntries(cfg), types: types);
      // 按 sort 升序：开发者(2) / 迷你季(3) / 其他(4) / 自定义(5)。
      expect(
        catalog.sortedTypes.map((t) => t.name).toList(),
        ['开发者', '迷你季', '其他', '自定义'],
      );
      expect(catalog.sortedTypes.first.id, 2);
    });

    test('parseTitleNames 向后兼容', () {
      expect(parseTitleNames(cfg)[20055], '城市规划师');
    });

    test('parseConfigIndex 提取 md5', () {
      final idx = parseConfigIndex("title_manager = '8d5bc05b04370a6a'");
      expect(idx['title_manager'], '8d5bc05b04370a6a');
    });
  });

  group('TitleShowData.parse（get_title_showdata）', () {
    test('owned / expired / use_title 与毫秒归一', () {
      final r = TitleShowData.parse({
        'owned': [
          {'ID': 101, 'StartTime': 1753977600, 'ExpireTime': -1, 'Custom': 0},
          {
            'ID': 102,
            'StartTime': 1753977600000,
            'ExpireTime': 1790000000000,
            'Custom': 1,
          },
        ],
        'expired': [
          {'ID': 103, 'StartTime': 0, 'ExpireTime': 1700000000},
        ],
        'use_title': {'ID': 101},
      });
      expect(r.owned.length, 2);
      expect(r.expired.length, 1);
      expect(r.all.length, 3);
      expect(r.useTitleId, 101);
      expect(r.owned[0].expireLabel, '永久');
      expect(r.owned[0].validRange.endsWith('--永久'), isTrue);
      expect(r.owned[1].custom, isTrue);
      expect(r.owned[1].expired, isFalse);
      expect(r.expired[0].expired, isTrue);
    });

    test('脏数据只跳过，不抛异常', () {
      final r = TitleShowData.parse({
        'owned': [
          {'ID': 0},
          'x',
          {'ID': 5},
        ],
      });
      expect(r.owned.length, 1);
      expect(r.owned.first.id, 5);
    });
  });

  group('formatTitleDate / validRange', () {
    test('秒与毫秒得到同一日期，格式为 YYYY.MM.DD', () {
      const secs = 1753977600;
      expect(
        formatTitleDate(secs * 1000),
        formatTitleDate(secs),
      );
      expect(formatTitleDate(secs), matches(RegExp(r'^\d{4}\.\d{2}\.\d{2}$')));
    });

    test('有效期区间：永久 / 到期', () {
      expect(
        const OwnedTitle(id: 1, startTime: 0, expireTime: -1).validRange,
        '—--永久',
      );
      final t = OwnedTitle(id: 2, startTime: 1753977600, expireTime: 1790000000);
      expect(t.validRange.endsWith('--${formatTitleDate(1790000000)}'), isTrue);
    });
  });

  group('parseShowFamily（get_show_family）', () {
    test('data / family 信封与空值', () {
      expect(
        parseShowFamily({
          'data': {'family_id': 7, 'name': 'MoonX'},
        })?.familyId,
        7,
      );
      expect(
        parseShowFamily({
          'family': {'family_id': 8, 'name': 'A'},
        })?.name,
        'A',
      );
      expect(parseShowFamily({'data': <String, Object?>{}}), isNull);
      expect(parseShowFamily({'data': {'family_id': 0}}), isNull);
    });

    test('FamilyClient.isSuccess 认 ret/code', () {
      expect(FamilyClient.isSuccess({'ret': 0}), isTrue);
      expect(FamilyClient.isSuccess({'code': 0}), isTrue);
      expect(FamilyClient.isSuccess({'code': 1}), isFalse);
      expect(FamilyClient.isSuccess(<String, Object?>{}), isFalse);
    });
  });

  test('TitleConfigEntry / TitleType 值语义', () {
    expect(
      const TitleConfigEntry(id: 1, name: 'a', sort: 2),
      isA<TitleConfigEntry>(),
    );
    expect(const TitleType(id: 2, name: '开发者', sort: 2).name, '开发者');
  });
}
