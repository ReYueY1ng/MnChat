// 桌面快捷键与剪贴板图片路径解析。
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:mnchat/core/models/clipboard_image.dart';
import 'package:mnchat/ui/widgets/desktop_shortcuts.dart';

void main() {
  Future<void> pressWithCtrl(WidgetTester tester, LogicalKeyboardKey key) async {
    await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
    await tester.sendKeyEvent(key);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
    await tester.pump();
  }

  testWidgets('Ctrl+F / Ctrl+K / Esc 分别触发三个回调', (tester) async {
    var search = 0;
    var quick = 0;
    var escape = 0;
    await tester.pumpWidget(
      MaterialApp(
        home: DesktopShortcuts(
          onSearch: () => search++,
          onQuickSwitch: () => quick++,
          onEscape: () => escape++,
          child: const Scaffold(body: SizedBox()),
        ),
      ),
    );

    await pressWithCtrl(tester, LogicalKeyboardKey.keyF);
    expect(search, 1);
    await pressWithCtrl(tester, LogicalKeyboardKey.keyK);
    expect(quick, 1);
    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pump();
    expect(escape, 1);
  });

  group('剪贴板图片路径', () {
    test('普通路径 / 引号 / file URI 都能识别，去重并保持顺序', () {
      final existing = {'/tmp/a.png', '/tmp/b.jpg', '/tmp/c.webp'};
      final paths = imagePathsFromClipboard(
        '/tmp/a.png\n"/tmp/b.jpg"\nfile:///tmp/c.webp\n/tmp/a.png\n',
        exists: existing.contains,
      );
      expect(paths, ['/tmp/a.png', '/tmp/b.jpg', '/tmp/c.webp']);
    });

    test('非图片扩展名、不存在的文件、空行都跳过', () {
      final paths = imagePathsFromClipboard(
        '/tmp/readme.txt\n/tmp/missing.png\n\n/tmp/ok.PNG',
        exists: (p) => p == '/tmp/ok.PNG',
      );
      expect(paths, ['/tmp/ok.PNG']);
    });

    test('最多返回 max 条', () {
      final text = List.generate(20, (i) => '/tmp/$i.png').join('\n');
      final paths = imagePathsFromClipboard(
        text,
        exists: (_) => true,
        max: 3,
      );
      expect(paths, hasLength(3));
      expect(paths.last, '/tmp/2.png');
    });

    test('拖拽文件：isImagePath / firstImagePath 过滤非图片', () {
      expect(isImagePath('/tmp/A.PNG'), isTrue);
      expect(isImagePath('/tmp/a.txt'), isFalse);
      expect(firstImagePath(['/tmp/a.txt', '/tmp/b.webp']), '/tmp/b.webp');
      expect(firstImagePath(['/tmp/a.txt']), isNull);
      expect(firstImagePath(const []), isNull);
    });

    test('空前/脏文本不抛', () {
      expect(imagePathsFromClipboard('', exists: (_) => true), isEmpty);
      expect(
        imagePathsFromClipboard('file://', exists: (_) => true),
        isEmpty,
      );
    });
  });
}
