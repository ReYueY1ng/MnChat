import 'package:flutter_test/flutter_test.dart';
import 'package:mnchat/core/models/nickname.dart';

/// 游戏返回的昵称/正文常带富文本标记，若无清洗会原样显示成
/// `[i][color][b]顾念`，头像首字母还会取到 `<` / `[`。
/// 这里锁定清洗契约，避免回归。
void main() {
  group('plainNickname', () {
    test('剥离 [i]/[color]/[b] 等标记', () {
      expect(plainNickname('[i][color][b]顾念'), '顾念');
    });

    test('剥离 <a> 链接标记', () {
      expect(plainNickname('<a>_谢俞<a>'), '_谢俞');
    });

    test('剥离其他尖括号标签（<s></s> 等，游戏不止 <a>）', () {
      expect(plainNickname('<s></s>蛤糖山'), '蛤糖山');
    });

    test('剥离游戏颜色码 #cRRGGBB 与换行码 #n', () {
      // stringdef.csv 的安全提示即写作 `#cFF0000对话中如涉及...`
      expect(plainNickname('#cFF0000顾念'), '顾念');
      expect(plainNickname('#c00FF00a#nb'), 'ab');
    });

    test('剥离 [u] / [size=..] 标记', () {
      expect(plainNickname('[u]斩玉京'), '斩玉京');
      expect(plainNickname('[size=14]力量龙龙'), '力量龙龙');
    });

    test('仅标记 → 空串（调用方回退到迷你号）', () {
      expect(plainNickname('[i][b]'), '');
    });

    test('反斜杠空白转义换成空格（线上实例：昵称 `我\\n的轨\\n迹`）', () {
      // 单行控件里真换行会被 ellipsis 吃掉，等于丢字，所以统一变空格。
      expect(plainNickname(r'我\n的轨\n迹'), '我 的轨 迹');
      expect(plainNickname(r'a\tb'), 'a b');
      expect(plainNickname(r'a\rb'), 'a b');
      // 与标记 / 颜色码同时出现时也要洗掉。
      expect(plainNickname(r'[b]我\n的轨迹'), '我 的轨迹');
      // 正常昵称不受影响（除了首尾空白）。
      expect(plainNickname('顾念'), '顾念');
    });

    test('null / 空白 → 空串', () {
      expect(plainNickname(null), '');
      expect(plainNickname('   '), '');
    });

    test('无标记昵称原样返回', () {
      expect(plainNickname('Lullaby'), 'Lullaby');
      expect(plainNickname('秋.'), '秋.');
    });
  });

  group('hasRichMarkup', () {
    test('识别标记与话题', () {
      expect(hasRichMarkup('[i]X'), isTrue);
      expect(hasRichMarkup('<a>X'), isTrue);
      expect(hasRichMarkup('#{福利&u:1:2}#'), isTrue);
    });

    test('普通文本不误判', () {
      expect(hasRichMarkup('Lullaby'), isFalse);
      expect(hasRichMarkup(null), isFalse);
      expect(hasRichMarkup(''), isFalse);
    });
  });

  group('topicLabels', () {
    test('抽取话题标签并保持顺序', () {
      expect(topicLabels('#{福利&u:1531751616:1704366345}#{动态可以抽奖了&o:177}'), [
        '福利',
        '动态可以抽奖了',
      ]);
    });

    test('去重', () {
      expect(topicLabels('#{福利&u:1}#{福利&o:2}'), ['福利']);
    });

    test('无话题 → 空列表', () {
      expect(topicLabels('普通正文'), isEmpty);
      expect(topicLabels(null), isEmpty);
    });
  });

  group('plainContent', () {
    test('话题标记降级为 #标签，其余标记剥离', () {
      expect(plainContent('[i]来抽奖#{福利&u:1:2}'), '来抽奖#福利');
    });

    test('相邻话题都保留（游戏真实格式，标记无结尾 #）', () {
      expect(
        plainContent('#{福利&u:1531751616:1704366345}#{动态可以抽奖了&o:177}'),
        '#福利#动态可以抽奖了',
      );
    });
  });
}
