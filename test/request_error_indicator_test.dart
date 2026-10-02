import 'package:material_ui/material_ui.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mnchat/core/services/request_errors.dart';
import 'package:mnchat/ui/widgets/request_error_indicator.dart';

/// 一个最小宿主：Scaffold + 可选的 FAB 位置，用来挂 [RequestErrorIndicator]。
Widget _host() => ProviderScope(
  child: MaterialApp(
    home: Scaffold(
      floatingActionButton: const RequestErrorIndicator(),
      body: const Text('body'),
    ),
  ),
);

void main() {
  setUp(RequestErrorBus.instance.clear);
  tearDown(RequestErrorBus.instance.clear);

  testWidgets('没有失败时角标不占位', (tester) async {
    await tester.pumpWidget(_host());
    expect(find.textContaining('请求失败'), findsNothing);
  });

  testWidgets('有失败时显示计数，点开详情能看到标签 / 业务码 / 地址', (tester) async {
    RequestErrorBus.instance.report(
      label: '拍档列表（我）',
      endpoint: 'https://shequ.mini1.cn:8081//miniw/bestpartner?s7=***&s7t=***',
      code: 9,
      message: '',
    );
    RequestErrorBus.instance.report(
      label: '网络请求',
      endpoint: 'https://shequ.mini1.cn:8081/miniw/upgrade?act=x',
      code: 500,
      message: 'connection error',
    );
    await tester.pumpWidget(_host());
    await tester.pump();

    // 两个失败 → 角标显示 2
    expect(find.text('2 个请求失败'), findsOneWidget);

    await tester.tap(find.text('2 个请求失败'));
    await tester.pumpAndSettle();

    expect(find.text('请求失败记录'), findsOneWidget);
    expect(find.textContaining('拍档列表（我）'), findsOneWidget);
    expect(find.textContaining('NO_ROUTE'), findsOneWidget);
    expect(find.textContaining('miniw/bestpartner'), findsOneWidget);
    expect(find.textContaining('网络请求'), findsOneWidget);
    expect(find.textContaining('connection error'), findsOneWidget);

    // 清空后弹窗里显示空态
    await tester.tap(find.text('清空'));
    await tester.pump();
    expect(find.text('暂无失败记录'), findsOneWidget);
  });

  testWidgets('重复失败在详情里显示次数', (tester) async {
    for (var i = 0; i < 3; i++) {
      RequestErrorBus.instance.report(
        label: '拍档列表（我）',
        endpoint: 'e',
        code: 9,
      );
    }
    await tester.pumpWidget(_host());
    await tester.pump();

    expect(find.text('3 个请求失败'), findsOneWidget);
    await tester.tap(find.text('3 个请求失败'));
    await tester.pumpAndSettle();
    expect(find.textContaining('×3'), findsOneWidget);
  });

  testWidgets('新失败会弹吐司，点「详情」打开列表', (tester) async {
    await tester.pumpWidget(
      ProviderScope(
        child: MaterialApp(
          home: Scaffold(
            body: const RequestErrorListener(child: Text('body')),
          ),
        ),
      ),
    );
    await tester.pump();

    RequestErrorBus.instance.report(
      label: '拍档列表（我）',
      endpoint: 'e',
      code: 9,
    );
    await tester.pump(); // 让 stream 事件到达
    await tester.pumpAndSettle(); // 完成吐司入场动画

    expect(find.textContaining('拍档列表（我）'), findsOneWidget);
    expect(find.text('详情'), findsOneWidget);

    await tester.tap(find.text('详情'));
    await tester.pumpAndSettle();
    expect(find.text('请求失败记录'), findsOneWidget);
  });
}
