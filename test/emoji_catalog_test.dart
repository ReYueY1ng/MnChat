import 'package:flutter_test/flutter_test.dart';
import 'package:mnchat/core/chat_emoji.dart' show emojiRepr;
import 'package:mnchat/core/emoticon.dart'
    show kSpriteRect, rectForCode, spriteNameForCode;
import 'package:mnchat/core/models/emoji_catalog.dart';
import 'package:mnchat/core/protocol/lua_table.dart' show decodeHttpResponse;

/// 表情系统：代码流 / 配置解析 / 内置包一致性单测（对齐 emojisysdatamanager.lua）。
void main() {
  group('包内互动表情（`图ID>序号`）', () {
    // 真实收包：content 是提示文案，interCode 是下面这段。
    const realCode = '[mdemo]2&10006&ani_expression_saizi>5[/mdemo]';

    test('解析出图 ID 与结果序号', () {
      final ref = parseEmojiCodeRefs(realCode).single;
      expect(ref.packId, '10006');
      expect(ref.picId, 'ani_expression_saizi');
      expect(ref.anim, '5');
    });

    test('映射到内置素材：骰子 1_<结果>、猜拳 2_<结果>', () {
      expect(interactiveAnimName('ani_expression_saizi', anim: '5'), '1_5');
      expect(interactiveAnimName('ani_expression_caiquan', anim: '3'), '2_3');
      // 面板里的包内图标没有序号 → 取第一个结果
      expect(interactiveAnimName('ani_expression_saizi'), '1_1');
      expect(interactiveAnimName('ani_expression_caiquan'), '2_1');
      // 越界/异常序号不崩，退回第一个
      expect(interactiveAnimName('ani_expression_saizi', anim: '9'), '1_1');
      expect(interactiveAnimName('ani_expression_caiquan', anim: 'x'), '2_1');
      // 普通表情不受影响
      expect(interactiveAnimName('ani_expression_shuidiaole'), isNull);
    });
  });

  group('emojiSendCode（GetEmojiLabel 对齐）', () {
    test('旧包用 #A<包ID><图ID>', () {
      const pack1 = EmojiPack(id: '1');
      const pack3 = EmojiPack(id: '3');
      expect(
        emojiSendCode(pack1, const EmojiPic(packId: '1', picId: '06')),
        '#A106',
      );
      expect(
        emojiSendCode(pack3, const EmojiPic(packId: '3', picId: '01')),
        '#A301',
      );
    });

    test('新包用 [mdemo]<Type>&<包ID>&<图ID>[/mdemo]', () {
      const pack = EmojiPack(id: '5', type: EmojiPackType.static);
      expect(
        emojiSendCode(pack, const EmojiPic(packId: '5', picId: '01')),
        '[mdemo]1&5&01[/mdemo]',
      );
    });

    test('动态表情带随机动画序号 >N', () {
      const pack = EmojiPack(id: '7', type: EmojiPackType.dynamic);
      expect(
        emojiSendCode(
          pack,
          const EmojiPic(packId: '7', picId: '03'),
          aniIndex: 2,
        ),
        '[mdemo]2&7&03>2[/mdemo]',
      );
    });
  });

  group('parseEmojiCodeRefs', () {
    test('旧表情代码', () {
      final refs = parseEmojiCodeRefs('你好#A106呀');
      expect(refs.length, 1);
      expect(refs.first.packId, '1');
      expect(refs.first.picId, '06');
      expect(refs.first.fromDynamic, isFalse);
      expect(refs.first.raw, '#A106');
    });

    test('动态表情代码（含动画序号）', () {
      final refs = parseEmojiCodeRefs('看这个[mdemo]2&7&03>2[/mdemo]哈哈');
      expect(refs.length, 1);
      expect(refs.first.packId, '7');
      expect(refs.first.picId, '03');
      expect(refs.first.type, EmojiPackType.dynamic);
      expect(refs.first.fromDynamic, isTrue);
    });

    test('新旧混排互不重叠', () {
      final refs = parseEmojiCodeRefs('#A101[mdemo]1&5&02[/mdemo]#A118');
      expect(refs.length, 3);
      final raws = refs.map((r) => r.raw).toList();
      expect(raws, contains('#A101'));
      expect(raws, contains('[mdemo]1&5&02[/mdemo]'));
      expect(raws, contains('#A118'));
    });

    test('无表情返回空', () {
      expect(parseEmojiCodeRefs('普通文本').isEmpty, isTrue);
      expect(parseEmojiCodeRefs('').isEmpty, isTrue);
    });
  });

  group('parseEmojiSystemConfig（visual-cfg emoji_system）', () {
    test('解析 LuaTable 文本的 emojis 数组', () {
      const text = "{emojis={"
          "{ID=5,Type=1,GetType=2,emoji_cfgs_url='http://x/5/infos.list',"
          "emoji_files_url={['01']='http://x/5/01.zip',['02']='http://x/5/02.zip'}}"
          "}}";
      final packs = parseEmojiSystemConfig(decodeHttpResponse(text));
      expect(packs.length, 1);
      final p = packs.first;
      expect(p.id, '5');
      expect(p.type, EmojiPackType.static);
      expect(p.getType, EmojiGetType.buy);
      expect(p.cfgsUrl, 'http://x/5/infos.list');
      expect(p.filesUrl['01'], 'http://x/5/01.zip');
      expect(p.isLegacy, isFalse);
    });

    test('缺 ID 的项跳过；非表结构返回空', () {
      expect(parseEmojiSystemConfig(decodeHttpResponse('{emojis={{Type=1}}}')),
          isEmpty);
      expect(parseEmojiSystemConfig(null), isEmpty);
      expect(parseEmojiSystemConfig(<String, Object?>{}), isEmpty);
    });

    // 真实样本：线上 `miniw/ma/<md5>.lua`（emoji_system）的逐字摘录。
    // 关键点：它用 **Lua 长括号字符串** `[[...]]` 写中文说明 —— 这正是线上
    // 「no parseable Lua table segment」报错的来源。
    test('真实 config 片段：长括号字符串 + 字符串型 Type + 尾逗号', () {
      const real = '''
 {
  emojis = {
    {
      ID = '10013',
      Name = '拾之蜜语',
      Type = '2',
      Photo = 'https://webpicture.mini1.cn/x.png',
      GetType = '4',
      BuyType = '10000',
      Access = [[花小楼换装舞会活动获得]],
      version_min = '1.54.0',
      emoji_cfgs_url = 'https://webpicture.mini1.cn/a.bin',
      pic_sets_url = 'https://webpicture.mini1.cn/b.zip',
      emoji_files_url = {
        ani_expression_OK = 'https://webpicture.mini1.cn/ok.zip',
        ani_expression_yingguangbang = 'https://webpicture.mini1.cn/ygb.zip',
      },
    },
    {
      ID = '1',
      Name = '熊孩子',
      Type = '1',
      GetType = '0',
    },
  },
}
''';
      final packs = parseEmojiSystemConfig(decodeHttpResponse(real));
      expect(packs.length, 2);

      final p = packs.firstWhere((x) => x.id == '10013');
      expect(p.type, EmojiPackType.dynamic);
      expect(p.getType, EmojiGetType.activity);
      expect(p.title, '拾之蜜语'); // 包名取自 Name
      expect(p.displayTitle, '拾之蜜语');
      expect(p.cfgsUrl, 'https://webpicture.mini1.cn/a.bin');
      expect(p.filesUrl['ani_expression_OK'], 'https://webpicture.mini1.cn/ok.zip');
      expect(p.filesUrl.length, 2);

      final legacy = packs.firstWhere((x) => x.id == '1');
      expect(legacy.type, EmojiPackType.static);
      expect(legacy.isLegacy, isTrue);
      expect(legacy.title, '熊孩子');
    });
  });

  group('parsePackInfosList（infos.list）', () {
    test('按 ID/icon 数组配对', () {
      final pics = parsePackInfosList('5', {
        'ID': ['06', '01'],
        'icon': ['qinqin.png', 'xieyanxiao.png'],
      });
      expect(pics.length, 2);
      expect(pics[0].packId, '5');
      expect(pics[0].picId, '06');
      expect(pics[0].icon, 'qinqin.png');
      expect(pics[0].iconName, 'qinqin');
    });

    test('icon 缺项时留空但仍产出条目', () {
      final pics = parsePackInfosList('5', {
        'ID': ['01'],
      });
      expect(pics.length, 1);
      expect(pics[0].icon, '');
    });

    // 真实样本：游戏运行时 `data/http/emoji/10006/infos.list`（逐字摘录）。
    // 验证「解析器对得上真实格式」+「骰子/猜拳的动画序号与结果一一对应」。
    test('真实 infos.list（pack 10006）：icon 无扩展名，anis 与 mod 一致', () {
      const real = '''
{
    "ID": ["ani_expression_001", "ani_expression_005", "ani_expression_caiquan", "ani_expression_saizi"],
    "icon": ["ani_expression_001", "ani_expression_005", "ani_expression_caiquan", "ani_expression_saizi"],
    "anis": {
        "ani_expression_caiquan": ["animation1", "animation2", "animation3"],
        "ani_expression_saizi": ["animation1", "animation2", "animation3", "animation4", "animation5", "animation6"]
    }
}
''';
      final pics = parsePackInfosList('10006', decodeHttpResponse(real));
      expect(pics.length, 4);

      final saizi = pics.firstWhere((p) => p.picId == 'ani_expression_saizi');
      expect(saizi.icon, 'ani_expression_saizi'); // 真实格式不带扩展名
      expect(saizi.iconName, 'ani_expression_saizi');
      expect(saizi.anis.length, 6);

      final caiquan = pics.firstWhere(
        (p) => p.picId == 'ani_expression_caiquan',
      );
      expect(caiquan.anis.length, 3);

      // anis 的序号 ↔ @IMFC 结果的种类数完全对齐。
      for (final e in kImfcEmojis) {
        final pic = e.index == 1 ? saizi : caiquan;
        expect(pic.anis.length, e.mod, reason: '@IMFC&${e.index}');
      }
    });

    // 真实样本：`ani_expression_saizi.atlas` 的区域名（逐字摘录）。
    // 证明 @IMFC&1_N 的 sprite 名 `1_N` 与游戏图集区域名是同一套。
    test('真实 saizi atlas 的区域名与 ImfcRef.sprite 对得上', () {
      const atlasRegions = ['1_1', '1_2', '1_3', '1_4', '1_5', '1_6'];
      final dice = kImfcEmojis.firstWhere((e) => e.index == 1);
      final expected = [
        for (var r = 1; r <= dice.mod; r++) ImfcRef(index: 1, result: r).sprite,
      ];
      expect(atlasRegions, expected);
      for (final name in atlasRegions) {
        expect(kSpriteRect[name], isNotNull, reason: name);
      }
    });
  });

  group('内置旧包（照抄 chatconfig.lua）', () {
    test('1/3 号包各 18 个表情，且 1 号包映射到本地图集', () {
      expect(kBuiltinPackPics['1']!.length, 18);
      expect(kBuiltinPackPics['3']!.length, 18);
      expect(kBuiltinEmojiPacks.map((p) => p.id), ['1', '3']);

      // 1 号包首个（qinqin）在 chatconfig.lua 里对应 #A106，且本地图集有坐标。
      final first = kBuiltinPackPics['1']!.first;
      expect(first.icon, 'qinqin.png');
      expect(emojiSendCode(const EmojiPack(id: '1'), first), '#A106');
      expect(rectForCode('#A106'), isNotNull);
    });

    test('3 号包（花小楼）同样映射到本地图集（hua_* 区域）', () {
      final first = kBuiltinPackPics['3']!.first;
      expect(first.icon, 'hua_qinqin.png');
      expect(emojiSendCode(const EmojiPack(id: '3'), first), '#A306');
      expect(rectForCode('#A306'), isNotNull);
      expect(spriteNameForCode('#A306'), 'hua_qinqin');
      expect(emojiRepr('#A306'), isNot('#A306'));
    });

    test('两个内置包的全部代码都能解析到图集坐标', () {
      for (final entry in kBuiltinPackPics.entries) {
        for (final pic in entry.value) {
          final code = emojiSendCode(EmojiPack(id: entry.key), pic);
          expect(
            rectForCode(code),
            isNotNull,
            reason: '$code（${pic.icon}）应在 kSpriteRect 中有坐标',
          );
        }
      }
    });

    test('新包 [mdemo] 代码不走图集（走下载）', () {
      expect(
        rectForCode('[mdemo]1&5&01[/mdemo]'),
        isNull,
      );
      expect(spriteNameForCode('[mdemo]1&5&01[/mdemo]'), isNull);
    });
  });

  group('互动表情（骰子 / 猜拳，@IMFC）', () {
    test('内置定义与 chatconfig.lua 一致', () {
      expect(kImfcEmojis.length, 2);
      expect(kImfcEmojis[0].index, 1);
      expect(kImfcEmojis[0].mod, 6); // 骰子 6 种结果
      expect(kImfcEmojis[1].index, 2);
      expect(kImfcEmojis[1].mod, 3); // 猜拳 3 种结果
      expect(kImfcEmojis[1].icon, '2_0'); // 封面是三种手势合集
    });

    test('interCode / 消息文本格式', () {
      expect(imfcInterCode(1, 3), '@IMFC&1_3');
      expect(imfcInterCode(2, 2), '@IMFC&2_2');
      // 文本 = 低版本文案 + parsKey + interCode（对齐 ChatHelper:DoSendRoomChat）
      expect(
        imfcMessageText(1, 3),
        '$kImfcFallbackText$kImfcParsKey@IMFC&1_3',
      );
    });

    test('parseImfc 兼容各形态', () {
      // 裸代码
      var ref = parseImfc('@IMFC&1_3');
      expect(ref!.index, 1);
      expect(ref.result, 3);
      expect(ref.sprite, '1_3');

      // parsKey 拼接形态（游戏实际收发的文本）
      ref = parseImfc('$kImfcFallbackText$kImfcParsKey@IMFC&2_2');
      expect(ref!.index, 2);
      expect(ref.result, 2);
      expect(ref.sprite, '2_2');

      // 老数据里的 JSON 信封（早期 MNChat 自己发的，仍要能渲染）
      ref = parseImfc('{"content":"$kImfcFallbackText","extend_data":"@IMFC&1_6"}');
      expect(ref!.index, 1);
      expect(ref.result, 6);
      expect(ref.sprite, '1_6');

      // 自己发出去的文本也解得回来
      ref = parseImfc(imfcMessageText(1, 6));
      expect(ref!.index, 1);
      expect(ref.result, 6);
      expect(ref.sprite, '1_6');

      // 非互动表情
      expect(parseImfc('普通文本'), isNull);
      expect(parseImfc(null), isNull);
      expect(parseImfc('@IMFC&'), isNull);
    });

    test('全部结果与封面都能在 kSpriteRect 中找到坐标', () {
      for (final e in kImfcEmojis) {
        expect(kSpriteRect[e.icon], isNotNull, reason: '封面 ${e.icon}');
        for (var r = 1; r <= e.mod; r++) {
          final sprite = ImfcRef(index: e.index, result: r).sprite;
          expect(kSpriteRect[sprite], isNotNull, reason: sprite);
        }
      }
    });

    test('Unicode 兜底映射', () {
      expect(imfcUnicode(const ImfcRef(index: 1, result: 1)), '⚀');
      expect(imfcUnicode(const ImfcRef(index: 1, result: 6)), '⚅');
      expect(imfcUnicode(const ImfcRef(index: 2, result: 1)), '✋');
      expect(imfcUnicode(const ImfcRef(index: 2, result: 2)), '✌️');
      expect(imfcUnicode(const ImfcRef(index: 2, result: 3)), '✊');
    });
  });
}
