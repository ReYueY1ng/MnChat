import 'dart:ui' as ui;

import 'package:flutter/services.dart' show rootBundle;
// 必须用 material_ui（项目实际使用的 Material 库）：与 flutter/material 不是同一套，
// 混用会让 InkWell/Material 的祖先校验失效。
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:mnchat/core/emoticon.dart'
    show EmojiAnimImage, ImfcEmojiImage, animFrameIndexAt, isWidgetVisible;
import 'package:mnchat/core/models/emoji_catalog.dart'
    show ImfcRef, emojiAnimAsset, emojiPackAnimName;
import 'package:mnchat/state/providers.dart' show emojiStoreProvider;
import 'package:mnchat/ui/widgets/rich_text_view.dart' show RichTextView;

/// 消息内联表情渲染的组件级回归：表情代码不能以原文形式显示给用户。
void main() {
  // 素材解码缓存是进程级的：跨用例复用会互相干扰（widget 测试里跨 zone 的
  // Future 可能永远不完成），每个用例前清一次。
  setUp(EmojiAnimImage.debugResetCache);

  Widget wrap(String text) => ProviderScope(
        // 测试不接网络/数据库：表情仓库置空，走「旧表情图集 / 占位」分支。
        overrides: [emojiStoreProvider.overrideWithValue(null)],
        child: MaterialApp(home: Scaffold(body: RichTextView(text))),
      );

  /// 直接挂普通 widget（补 Material 祖先）。
  Widget host(Widget child) => MaterialApp(home: Material(child: child));

  /// 当前**真正画出来**的那一帧（`_EmojiPainter.image`）。
  ///
  /// 用它判断「有没有在播」：没画面 → null；画面在变 → 动画在推进。
  /// （别用 `hasScheduledFrame`：AnimationController 起播后那一刻它是 false，
  /// 断言会假失败。）
  ui.Image? paintedFrame(WidgetTester tester) {
    final all = find.descendant(
      of: find.byType(ImfcEmojiImage),
      matching: find.byType(CustomPaint),
    );
    if (all.evaluate().isEmpty) return null;
    // 多个互动表情时取第一个即可
    final painter = tester.widget<CustomPaint>(all.first).painter;
    return (painter as dynamic).image as ui.Image;
  }

  /// 等真实 I/O（读素材 + 解码）走完 —— 互动表情要解码后才有画面 / 才会开播。
  ///
  /// 必须用 `runAsync`：普通 `pump` 下这个 Future 永远不完成，会把
  /// `_PlayOnceAnimImage` 的静态缓存「卡住」，连累后面的测试。
  Future<void> settleEmoji(WidgetTester tester) async {
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 200)),
    );
    await tester.pump();
  }

  testWidgets('动态表情代码 [mdemo]...[/mdemo] 不显示为原文', (tester) async {
    await tester.pumpWidget(wrap('看这个[mdemo]1&5&01[/mdemo]哈哈'));
    await tester.pump();

    expect(find.textContaining('[mdemo]'), findsNothing);
    expect(find.textContaining('[/mdemo]'), findsNothing);
    // 表情两侧的正常文本仍保留。
    expect(find.textContaining('看这个'), findsOneWidget);
    expect(find.textContaining('哈哈'), findsOneWidget);
  });

  testWidgets('动态表情代码带动画序号时同样不泄漏原文', (tester) async {
    await tester.pumpWidget(wrap('[mdemo]2&7&03>2[/mdemo]'));
    await tester.pump();
    expect(find.textContaining('mdemo'), findsNothing);
    expect(find.textContaining('&'), findsNothing);
  });

  testWidgets('旧表情代码 #A1xx 不显示为原文', (tester) async {
    await tester.pumpWidget(wrap('你好#A106'));
    await tester.pump();
    expect(find.textContaining('#A106'), findsNothing);
    expect(find.textContaining('你好'), findsOneWidget);
  });

  testWidgets('互动表情 @IMFC&N_M 不显示为原文（也不会被当成 @提及）', (tester) async {
    await tester.pumpWidget(wrap('掷个骰子@IMFC&1_3'));
    await settleEmoji(tester);

    expect(find.textContaining('@IMFC'), findsNothing);
    expect(find.textContaining('1_3'), findsNothing);
    expect(find.textContaining('掷个骰子'), findsOneWidget);
  });

  testWidgets('猜拳结果同样按帧渲染', (tester) async {
    await tester.pumpWidget(wrap('@IMFC&2_2'));
    await settleEmoji(tester);
    expect(find.textContaining('@IMFC'), findsNothing);
    expect(find.textContaining('2_2'), findsNothing);
  });

  // 真实收到的互动表情是这个形状（用户库里的一条）：
  // content 是低版本提示文案，interCode 是 `[mdemo]2&10006&ani_expression_saizi>5[/mdemo]`
  // —— 包内并没有一张叫 `ani_expression_saizi>5` 的图，必须映射到内置 `1_5.webp`，
  // 否则会退化成灰色占位图标（Icons.emoji_emotions_outlined）。
  group('包内互动表情（骰子/猜拳）映射到内置素材', () {
    testWidgets('骰子：不再显示灰色占位图标', (tester) async {
      await tester.pumpWidget(
        wrap('[mdemo]2&10006&ani_expression_saizi>5[/mdemo]'),
      );
      await settleEmoji(tester);
      expect(find.byIcon(Icons.emoji_emotions_outlined), findsNothing);
      expect(find.textContaining('mdemo'), findsNothing);
    });

    testWidgets('猜拳：不再显示灰色占位图标', (tester) async {
      await tester.pumpWidget(
        wrap('[mdemo]2&10006&ani_expression_caiquan>3[/mdemo]'),
      );
      await settleEmoji(tester);
      expect(find.byIcon(Icons.emoji_emotions_outlined), findsNothing);
    });

    testWidgets('未知序号退回第一个结果，而不是占位', (tester) async {
      await tester.pumpWidget(
        wrap('[mdemo]2&10006&ani_expression_saizi>9[/mdemo]'),
      );
      await settleEmoji(tester);
      expect(find.byIcon(Icons.emoji_emotions_outlined), findsNothing);
    });
  });

  group('动画播放策略（互动=停末帧，表达=循环）', () {
    testWidgets('历史消息：直接显示结果帧，不播动画', (tester) async {
      // 骰子/猜拳是即时反馈：历史记录不该一遍遍重播，结果帧就是最终画面。
      await tester.pumpWidget(
        host(
          const ImfcEmojiImage(
            ref: ImfcRef(index: 1, result: 3),
            size: 64,
            animate: false,
          ),
        ),
      );
      await settleEmoji(tester);

      // 有画面（末帧 = 结果），且画面不再变化（没在播）
      final first = paintedFrame(tester);
      expect(first, isNotNull, reason: '历史消息也要有画面（结果帧）');
      await tester.pump(const Duration(milliseconds: 500));
      expect(identical(paintedFrame(tester), first), isTrue,
          reason: '历史消息不该逐帧推进（不播动画）');
    });

    testWidgets('新到的消息：会播动画', (tester) async {
      await tester.pumpWidget(
        host(
          const ImfcEmojiImage(ref: ImfcRef(index: 1, result: 3), size: 64),
        ),
      );
      await settleEmoji(tester);

      final first = paintedFrame(tester);
      expect(first, isNotNull, reason: '解码完就该有画面');
      await tester.pump(const Duration(milliseconds: 500));
      expect(identical(paintedFrame(tester), first), isFalse,
          reason: '新消息应逐帧播下去');
    });

    test('isWidgetVisible：视口外不算可见，露出过半才算', () {
      const viewport = Size(400, 800);
      // 完全在视口内
      expect(isWidgetVisible(const Rect.fromLTWH(0, 300, 400, 100), viewport),
          isTrue);
      // 露出 60%（过半）→ 算可见
      expect(isWidgetVisible(const Rect.fromLTWH(0, 740, 400, 100), viewport),
          isTrue);
      // 只露出 20% → 不算
      expect(isWidgetVisible(const Rect.fromLTWH(0, 780, 400, 100), viewport),
          isFalse);
      // 完全在视口下方（列表 cacheExtent 里的历史消息就是这种）
      expect(isWidgetVisible(const Rect.fromLTWH(0, 900, 400, 100), viewport),
          isFalse);
      // 完全在视口上方
      expect(isWidgetVisible(const Rect.fromLTWH(0, -200, 400, 100), viewport),
          isFalse);
    });

    testWidgets('视口外的互动表情不提前开播，滚进视野才开始播', (tester) async {
      // 复现列表的行为：组件先被构建（在 cacheExtent 内），但还没进视野。
      // 修复前它在 build 时就 forward()，等用户滚上去早就播完了。
      final controller = ScrollController();
      addTearDown(controller.dispose);
      await tester.pumpWidget(
        host(
          SingleChildScrollView(
            controller: controller,
            child: Column(
              children: [
                const SizedBox(height: 700), // 顶到视口外（测试视口高 600）
                for (var i = 1; i <= 3; i++)
                  SizedBox(
                    height: 100,
                    child: Center(
                      child: ImfcEmojiImage(
                        ref: ImfcRef(index: 1, result: i),
                        size: 48,
                      ),
                    ),
                  ),
              ],
            ),
          ),
        ),
      );
      await settleEmoji(tester);
      expect(paintedFrame(tester), isNull, reason: '视口外不该开播（也就没有画面）');

      controller.jumpTo(700);
      await tester.pump();
      final first = paintedFrame(tester);
      expect(first, isNotNull, reason: '滚进视野后应开始播');
      await tester.pump(const Duration(milliseconds: 500));
      expect(identical(paintedFrame(tester), first), isFalse,
          reason: '滚进视野后动画在推进');
    });

    test('animFrameIndexAt：按帧时长推进，结束时夹在最后一帧', () {
      // 骰子：21 帧 × 100ms
      final dice = List<int>.filled(21, 100);
      expect(animFrameIndexAt(dice, 0), 0);
      expect(animFrameIndexAt(dice, 99), 0);
      expect(animFrameIndexAt(dice, 100), 1);
      expect(animFrameIndexAt(dice, 1999), 19);
      // 末帧必须停住：t=最后一段、以及超过总时长都不回绕
      expect(animFrameIndexAt(dice, 2000), 20);
      expect(animFrameIndexAt(dice, 2100), 20);
      expect(animFrameIndexAt(dice, 999999), 20);
    });

    test('混合时长也按各自时长推进', () {
      const d = [50, 200, 50];
      expect(animFrameIndexAt(d, 0), 0);
      expect(animFrameIndexAt(d, 49), 0);
      expect(animFrameIndexAt(d, 50), 1);
      expect(animFrameIndexAt(d, 249), 1);
      expect(animFrameIndexAt(d, 250), 2);
      expect(animFrameIndexAt(d, 300), 2);
    });

    test('空帧序列不崩', () {
      expect(animFrameIndexAt(const [], 0), 0);
      expect(animFrameIndexAt(const [], 500), 0);
    });

    testWidgets('互动表情（loop:false）会自己播完并停下，不会无限循环', (tester) async {
      await tester.pumpWidget(
        host(
          const ImfcEmojiImage(
            ref: ImfcRef(index: 1, result: 3),
            size: 64,
          ),
        ),
      );
      // 让真实 I/O（读素材 + 解码）跑完；解码后 AnimationController 才创建。
      await tester.runAsync(() => Future<void>.delayed(
            const Duration(milliseconds: 200),
          ));
      await tester.pump();
      // 放完 2.1s：能 settle 说明是 forward() 而非 repeat()。
      await tester.pump(const Duration(seconds: 3));
      expect(tester.binding.hasScheduledFrame, isFalse);
      expect(find.byType(ImfcEmojiImage), findsOneWidget);
    });

    // 素材本体校验：确认随包发布的 webp 真的是可解码的多帧动画
    // （防止文件被截断/写坏时上面的测试「因为走了 fallback 而假通过」）。
    testWidgets('随包素材可解码：骰子/猜拳/表情包都是多帧动画', (tester) async {
      Future<int> frameCount(String path) async {
        final bytes = await rootBundle.load(path);
        final codec = await ui.instantiateImageCodec(
          bytes.buffer.asUint8List(bytes.offsetInBytes, bytes.lengthInBytes),
        );
        final n = codec.frameCount;
        codec.dispose();
        return n;
      }

      await tester.runAsync(() async {
        // 骰子 6 面 + 猜拳 3 手：整个播放器路径走一遍（逐帧 getNextFrame），
        // 不能只问 frameCount —— 参数错误时是解码中途才炸的。
        for (final n in ['1_1', '1_2', '1_3', '1_4', '1_5', '1_6',
                         '2_1', '2_2', '2_3']) {
          final path = 'assets/emoticon/anim/$n.webp';
          final bytes = await rootBundle.load(path);
          final codec = await ui.instantiateImageCodec(
            bytes.buffer.asUint8List(bytes.offsetInBytes, bytes.lengthInBytes),
          );
          for (var i = 0; i < codec.frameCount; i++) {
            final f = await codec.getNextFrame();
            expect(f.image.width, greaterThan(0), reason: n);
          }
          // 只卡「确实是动画」这个下限：libwebp 会合并连续相同帧，
          // 帧数随编码参数浮动（当前骰子 21、猜拳 23~24），别写死。
          expect(codec.frameCount, greaterThan(5), reason: n);
          codec.dispose();
        }
        expect(
          await frameCount('assets/emoticon/anim/p10012-ani_expression_buxixi.webp'),
          greaterThan(5),
        );
      });
    });

    test('骰子/猜拳的各结果素材互不相同', () async {
      // 回归：spine2webp 取不到 t=duration 的最后一个关键帧，6 个骰子 animation
      // 会被导成同一份内容（结果面只在那一帧）→ 互动表情永远显示同一个「占位」图。
      // 这里按字节比对，任何「导出成全同一个」都会被抓到。
      await TestWidgetsFlutterBinding.ensureInitialized().runAsync(() async {
        Future<List<int>> bytes(String n) async {
          final b = await rootBundle.load('assets/emoticon/anim/$n.webp');
          return b.buffer.asUint8List(b.offsetInBytes, b.lengthInBytes);
        }

        final dice = <String, List<int>>{};
        for (final n in ['1_1', '1_2', '1_3', '1_4', '1_5', '1_6']) {
          dice[n] = await bytes(n);
        }
        for (final a in dice.keys) {
          for (final b in dice.keys) {
            if (a == b) continue;
            expect(dice[a]!, isNot(orderedEquals(dice[b]!)),
                reason: '$a 与 $b 内容相同');
          }
        }
        final a = await bytes('2_1');
        final b = await bytes('2_3');
        expect(a, isNot(orderedEquals(b)), reason: '猜拳 2_1 与 2_3 内容相同');
      });
    });

    test('素材名带包 ID，避免跨包同名互相覆盖', () {
      // 真实数据里 10006 与 10007 都有 ani_expression_022 / 025
      expect(
        emojiPackAnimName('10006', 'ani_expression_022'),
        isNot(emojiPackAnimName('10007', 'ani_expression_022')),
      );
      expect(
        emojiAnimAsset(emojiPackAnimName('10006', 'ani_expression_022')),
        'assets/emoticon/anim/p10006-ani_expression_022.webp',
      );
      // 互动表情仍按 sprite 名（只有一套，无冲突）
      expect(emojiAnimAsset('1_3'), 'assets/emoticon/anim/1_3.webp');
    });
  });
}
