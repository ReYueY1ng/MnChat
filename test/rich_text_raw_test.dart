import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mnchat/state/providers.dart';
import 'package:mnchat/ui/widgets/rich_text_view.dart';

/// 「富文本显示原文本」开关回归：
/// - 开启：带标签的昵称原样显示（不解析、不丢标签）；
/// - 关闭：与旧行为一致，解析后不显示字面标签。
void main() {
  const marked = '[i][color][b]顾念';

  /// 以指定开关状态 pump [RichTextView]。
  Future<void> pump(WidgetTester tester, {required bool raw}) {
    return tester.pumpWidget(
      ProviderScope(
        overrides: [
          richTextRawProvider.overrideWith(() => _FakeRawNotifier(raw)),
        ],
        child: const MaterialApp(
          home: Scaffold(body: Center(child: RichTextView(marked))),
        ),
      ),
    );
  }

  testWidgets('开启原文本：标签串原样显示', (tester) async {
    await pump(tester, raw: true);
    expect(find.text(marked), findsOneWidget);
    expect(find.textContaining('[i]'), findsOneWidget);
  });

  testWidgets('关闭原文本：解析渲染，不显示字面标签', (tester) async {
    await pump(tester, raw: false);
    expect(find.textContaining('顾念'), findsOneWidget);
    expect(find.textContaining('[i]'), findsNothing);
    expect(find.textContaining('[color]'), findsNothing);
  });
}

/// 测试替身：直接固定开关值，不读写设置存储。
class _FakeRawNotifier extends RichTextRawNotifier {
  _FakeRawNotifier(this.value);

  final bool value;

  @override
  bool build() => value;
}
