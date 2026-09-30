import 'dart:io';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
// 必须用 material_ui（项目实际使用的 Material 库），
// 否则 InkWell 找不到它要求的 Material 祖先（与 flutter/material 不是同一套）。
import 'package:material_ui/material_ui.dart';
import 'package:mnchat/core/models/emoji_catalog.dart' show ImfcEmoji;
import 'package:mnchat/core/services/emoji_store.dart';
import 'package:mnchat/core/services/miniw_extra.dart';
import 'package:mnchat/ui/widgets/emoji_picker.dart' show EmojiPickerPanel;

/// 表情面板 UI 单测：基础页签可选、我的页签展示内置表情包。
///
/// 用假 Dio（对所有请求返回 `{}`）驱动 [EmojiStore]：远端配置/已拥有列表都为空
/// → 仓库回退到内置 1/3 号包，全程不触网。
void main() {
  Dio emptyDio() {
    final dio = Dio();
    dio.interceptors.add(
      InterceptorsWrapper(
        onRequest: (options, handler) => handler.resolve(
          Response<dynamic>(
            requestOptions: options,
            data: '{}',
            statusCode: 200,
          ),
        ),
      ),
    );
    return dio;
  }

  EmojiStore storeWith(Dio dio, Directory tmp) => EmojiStore(
        client: EmojiClient(
          uin: 1,
          s2: 's2',
          s2t: 's2t',
          dio: dio,
          baseUrl: 'http://x',
        ),
        dio: dio,
        cacheRoot: tmp.path,
      );

  /// 真实场景里面板在 `showModalBottomSheet` 内（自带 Material）；
  /// 这里的宿主补一个 Material，否则 InkWell 会报缺少 Material 祖先。
  Widget host(Widget child) => MaterialApp(home: Material(child: child));

  void useTallSurface(WidgetTester tester) {
    tester.view.physicalSize = const Size(800, 1600);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
  }

  testWidgets('未登录（store 为空）只显示基础表情，点击回调收到 #A1xx', (tester) async {
    String? picked;
    await tester.pumpWidget(
      host(EmojiPickerPanel(store: null, onPick: (c) => picked = c)),
    );
    await tester.pump();

    // 底部表情包栏：只有「基础」（图标 + Tooltip，没有文字标签）。
    expect(find.byTooltip('基础'), findsOneWidget);
    expect(find.byTooltip('互动'), findsNothing);
    expect(find.byType(InkWell), findsWidgets);

    // 点第一个表情（网格第一格）
    await tester.tap(find.byType(InkWell).first);
    await tester.pump();
    expect(picked, '#A101');
  });

  testWidgets('有表情仓库时出现两个页签，我的页签展示内置表情包', (tester) async {
    useTallSurface(tester);
    // 注意：widget 测试跑在 FakeAsync 区里，`Directory.createTemp()`（异步版）
    // 永远等不到事件循环 → 必须用同步版。
    final tmp = Directory.systemTemp.createTempSync('emoji_picker_test');
    addTearDown(() {
      if (tmp.existsSync()) tmp.deleteSync(recursive: true);
    });
    final dio = emptyDio();
    final store = storeWith(dio, tmp);

    // 在真实时间线下预热仓库（dio/文件 IO 在 FakeAsync 下不会推进）。
    await tester.runAsync(() => store.load());

    await tester.pumpWidget(host(EmojiPickerPanel(store: store, onPick: (_) {})));
    await tester.pump();
    await tester.pump();

    // 底部栏：基础 + 已拥有（无网络数据 → 回退内置 1/3 号包）+ 添加/设置。
    expect(find.byTooltip('基础'), findsOneWidget);
    expect(find.byTooltip('熊孩子'), findsOneWidget);
    expect(find.byTooltip('花小楼'), findsOneWidget);

    // 切到「熊孩子」包 → 网格变成该包的表情。
    await tester.tap(find.byTooltip('熊孩子'));
    await tester.pumpAndSettle();
    expect(find.byType(InkWell), findsWidgets);
  });

  testWidgets('互动页签（骰子/猜拳）点按即回调，不插入输入框', (tester) async {
    useTallSurface(tester);
    ImfcEmoji? picked;
    await tester.pumpWidget(
      host(
        EmojiPickerPanel(
          store: null,
          onPick: (_) {},
          onImfc: (e) => picked = e,
        ),
      ),
    );
    await tester.pump();

    // store 为空时底部栏是「基础 / 互动」。
    expect(find.byTooltip('基础'), findsOneWidget);
    expect(find.byTooltip('互动'), findsOneWidget);

    await tester.tap(find.byTooltip('互动'));
    await tester.pumpAndSettle();

    expect(find.text('骰子'), findsOneWidget);
    expect(find.text('猜拳'), findsOneWidget);

    await tester.tap(find.text('骰子'));
    await tester.pump();
    expect(picked?.index, 1);
    expect(picked?.mod, 6);
  });
}
