/// 共享测试脚手架（`test/support/`）。
///
/// 为什么现在需要它：测试文件已超过 110 个、约 1.9 万行，每个文件重复实现
/// 「内存数据库 + ProviderScope + theme + 尺寸」的挂载代码，fake 也在各文件里
/// 各写一份。这里只收敛**稳定不变的装置**（数据库、App 挂载、时钟），
/// 业务 fake 仍留在使用它的测试文件里 —— 保持单个测试可独立阅读。
library;

import 'package:drift/native.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:mnchat/core/storage/app_database.dart';
import 'package:mnchat/ui/theme/app_theme.dart';

/// 内存 Drift 数据库；调用方负责在 tearDown 里 `close()`。
AppDatabase newTestDb() => AppDatabase(NativeDatabase.memory());

/// 可推进的测试时钟。
///
/// 消息时间只精确到秒：以前测试用 `Future.delayed(1100ms)` 来制造两个不同的
/// 秒数，既慢又不稳定。把时钟注入 [ChatService] 后，直接 `advance(1s)` 即可。
class TestClock {
  TestClock([DateTime? start])
    : _now = start ?? DateTime.fromMillisecondsSinceEpoch(1700000000000);

  DateTime _now;

  DateTime now() => _now;

  void advance(Duration d) => _now = _now.add(d);

  void set(DateTime t) => _now = t;
}

/// 一次测试的挂载容器：ProviderContainer + 统一的 App 外壳。
///
/// 容器由调用方构造（`TestHarness(ProviderContainer(overrides: [...]))`）：
/// `Override` 类型没有从 `flutter_riverpod` 导出，这里不把它写进签名。
class TestHarness {
  TestHarness(this.container);

  TestHarness.empty() : container = ProviderContainer();

  final ProviderContainer container;

  /// 挂载 [home]：主题走 [buildAppTheme]（它负责挂上 `AppSemanticColors`），
  /// 默认尺寸/字号与生产一致；需要窄/宽布局时传 [size]。
  Future<void> pump(
    WidgetTester tester,
    Widget home, {
    Size size = const Size(1024, 768),
    double textScale = 1.0,
    Locale? locale,
    Iterable<Locale>? supportedLocales,
    Iterable<LocalizationsDelegate<dynamic>>? delegates,
  }) async {
    tester.view.physicalSize = size * tester.view.devicePixelRatio;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: MaterialApp(
          theme: buildAppTheme(Brightness.light),
          darkTheme: buildAppTheme(Brightness.dark),
          locale: locale,
          supportedLocales:
              supportedLocales ?? const <Locale>[Locale('en'), Locale('zh')],
          localizationsDelegates: delegates,
          home: Builder(
            builder: (context) => MediaQuery(
              data: MediaQuery.of(
                context,
              ).copyWith(textScaler: TextScaler.linear(textScale)),
              child: home,
            ),
          ),
        ),
      ),
    );
  }

  void dispose() => container.dispose();
}
