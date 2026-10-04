// 群聊 @ 提及判定：`@昵称` 的纯文本匹配口径。
//
// 服务端推送里没有「提及了谁」字段，@ 就是正文里的 `@昵称`，所以这里锁的是
// 一段纯函数的口径，包含已知的误命中（`@顾念之` 也算提到「顾念」）。
import 'package:flutter_test/flutter_test.dart';
import 'package:mnchat/core/models/mention.dart';

void main() {
  group('textMentions', () {
    test('命中：@ 后面就是昵称', () {
      expect(textMentions('@顾念 在吗', '顾念'), isTrue);
    });

    test('命中：@ 与昵称之间有空白（手打 @ 常带一个空格）', () {
      expect(textMentions('@ 顾念 在吗', '顾念'), isTrue);
    });

    test('命中：句中还有别的 @', () {
      expect(textMentions('@张三 你看 @顾念 发的图', '顾念'), isTrue);
    });

    test('命中：@ 后面紧跟内容，没有空格', () {
      expect(textMentions('@顾念在吗', '顾念'), isTrue);
    });

    test('已知误命中：@顾念之 也算提到「顾念」', () {
      expect(textMentions('@顾念之 在吗', '顾念'), isTrue);
    });

    test('不命中：正文根本没提', () {
      expect(textMentions('顾念 在吗', '顾念'), isFalse);
    });

    test('不命中：@ 后面是别人', () {
      expect(textMentions('@李四 在吗', '顾念'), isFalse);
    });

    test('不命中：@ 在末尾（提了但没写完 nickname）', () {
      expect(textMentions('在吗 @', '顾念'), isFalse);
    });

    test('不命中：昵称为空 —— 不知道昵称就宁可不提醒', () {
      expect(textMentions('@顾念 在吗', ''), isFalse);
      expect(textMentions('@顾念 在吗', '   '), isFalse);
    });

    test('不命中：空正文', () {
      expect(textMentions('', '顾念'), isFalse);
    });
  });
}
