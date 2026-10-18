// 语音条的空/脏数据态：只做不碰网络的那部分（点播放要真的下载/起播放器，
// 由 tool 级与桌面取证覆盖）。
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:mnchat/ui/theme/app_theme.dart' show buildAppTheme;
import 'package:mnchat/ui/widgets/voice_message_bar.dart';

Widget _host(Widget child) => MaterialApp(
  theme: buildAppTheme(Brightness.light),
  home: Scaffold(body: Center(child: child)),
);

void main() {
  testWidgets('语音条默认形态：播放键 + 波形 + 时长', (tester) async {
    await tester.pumpWidget(
      _host(
        const VoiceMessageBar(url: 'http://cdn.test/a/clip.png', seconds: 7),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.byKey(voiceBubbleKey), findsOneWidget);
    expect(find.byKey(voicePlayButtonKey), findsOneWidget);
    expect(find.byIcon(Icons.play_arrow_rounded), findsOneWidget);
    expect(find.text('7″'), findsOneWidget);
    // 波形条数固定（进度就画在这些柱子的着色上）。
    expect(find.byType(AnimatedContainer), findsNWidgets(VoiceMessageBar.barCount));
    // 波形可拖动（拖动定位的热区）。
    expect(find.byKey(voiceWaveformKey), findsOneWidget);
  });

  testWidgets('未播放时拖波形：不误触开播、不抛', (tester) async {
    await tester.pumpWidget(
      _host(
        const VoiceMessageBar(url: 'http://cdn.test/a/clip.png', seconds: 7),
      ),
    );
    await tester.pumpAndSettle();

    final wave = find.byKey(voiceWaveformKey);
    await tester.drag(wave, const Offset(60, 0));
    await tester.pumpAndSettle();

    // 还是待播形态（没变成加载/播放），时长仍是载荷里的总长。
    expect(find.byIcon(Icons.play_arrow_rounded), findsOneWidget);
    expect(find.text('7″'), findsOneWidget);
    expect(find.byType(CircularProgressIndicator), findsNothing);
  });

  testWidgets('没有 URL 时点击：提示不支持，不抛也不卡在加载态', (tester) async {
    await tester.pumpWidget(_host(const VoiceMessageBar(url: '', seconds: 0)));
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(voicePlayButtonKey));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));

    expect(find.text('当前平台暂不支持播放语音'), findsOneWidget);
    // 回到可点状态（不是一直转圈）。
    expect(find.byIcon(Icons.play_arrow_rounded), findsOneWidget);
  });
}
