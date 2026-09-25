import 'package:material_ui/material_ui.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mnchat/ui/widgets/avatar_view.dart';
import 'package:mnchat/ui/widgets/rich_text_view.dart';

/// 渲染层回归：游戏昵称带标记时，头像首字与标题都必须清洗之后才显示。
void main() {
  Future<void> pump(WidgetTester tester, Widget child) {
    return tester.pumpWidget(
      ProviderScope(
        child: MaterialApp(
          home: Scaffold(body: Center(child: child)),
        ),
      ),
    );
  }

  group('AvatarView', () {
    testWidgets('首字取清洗后的字符，而不是 [ 或 <', (tester) async {
      await pump(tester, const AvatarView(name: '[i][color][b]顾念'));
      expect(find.text('顾'), findsOneWidget);
      expect(find.text('['), findsNothing);

      await pump(tester, const AvatarView(name: '<a>谢俞<a>'));
      expect(find.text('谢'), findsOneWidget);
      expect(find.text('<'), findsNothing);
    });

    testWidgets('清洗后为空 → 回退图标，不显示标记', (tester) async {
      await pump(tester, const AvatarView(name: '[i][b]'));
      expect(find.byIcon(Icons.person), findsOneWidget);
      expect(find.text('['), findsNothing);
    });
  });

  group('RichTextView', () {
    testWidgets('剥离标记后显示纯文本', (tester) async {
      await pump(tester, const RichTextView('[i][color][b]顾念'));
      expect(find.textContaining('顾念'), findsOneWidget);
      expect(find.textContaining('[i]'), findsNothing);
      expect(find.textContaining('[color]'), findsNothing);
    });

    testWidgets('普通文本直接显示', (tester) async {
      await pump(tester, const RichTextView('Lullaby'));
      expect(find.text('Lullaby'), findsOneWidget);
    });

    testWidgets('@ 提及夹带标记时清洗（@[color]名字）', (tester) async {
      await pump(tester, const RichTextView('@[color]点赞关注，评论开抽'));
      expect(find.textContaining('@点赞关注'), findsOneWidget);
      expect(find.textContaining('[color]'), findsNothing);
    });

    testWidgets('尖括号标签 <s></s> 被剥离', (tester) async {
      await pump(tester, const RichTextView('<s></s>蛤糖山'));
      expect(find.textContaining('蛤糖山'), findsOneWidget);
      expect(find.textContaining('<s>'), findsNothing);
    });

    testWidgets('游戏颜色码 #cRRGGBB 不原样显示', (tester) async {
      await pump(tester, const RichTextView('#cFF0000请提高警惕'));
      expect(find.textContaining('请提高警惕'), findsOneWidget);
      expect(find.textContaining('#cFF0000'), findsNothing);
    });
  });
}
