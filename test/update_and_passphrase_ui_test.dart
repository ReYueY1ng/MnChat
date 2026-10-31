// i18n 之后的 UI 接线：更新检查弹层的下载入口、备份口令弹层校验。
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:mnchat/core/services/app_update.dart';

import 'package:mnchat/l10n/app_localizations.dart';
import 'package:mnchat/state/providers.dart';
import 'package:mnchat/ui/data_page.dart';
import 'package:mnchat/ui/settings_about_page.dart';

import 'support/harness.dart';

class _FakeUpdateClient extends AppUpdateClient {
  _FakeUpdateClient({required this.assets});

  final List<UpdateAsset> assets;

  @override
  Future<UpdateCheckResult> check(String current) async => UpdateCheckResult(
    current: current,
    latest: '9.9.9',
    url: 'https://example.com/release',
    assets: assets,
  );
}

const _assets = [
  UpdateAsset(name: 'mnchat.apk', url: 'https://example.com/mnchat.apk'),
  UpdateAsset(
    name: 'mnchat-linux.tar.gz',
    url: 'https://example.com/mnchat-linux.tar.gz',
  ),
  UpdateAsset(name: 'mnchat-windows.zip', url: 'https://example.com/m.zip'),
];

void main() {
  Future<TestHarness> pumpAbout(
    WidgetTester tester, {
    required List<UpdateAsset> assets,
  }) async {
    final db = newTestDb();
    addTearDown(db.close);
    final container = ProviderContainer(
      overrides: [databaseProvider.overrideWithValue(db)],
    );
    final harness = TestHarness(container);
    addTearDown(harness.dispose);
    await harness.pump(
      tester,
      SettingsAboutPage(client: _FakeUpdateClient(assets: assets)),
      delegates: [
        AppLocalizations.delegate,
        ...GlobalMaterialLocalizations.delegates,
      ],
      supportedLocales: AppLocalizations.supportedLocales,
      locale: const Locale('zh'),
    );
    await tester.pumpAndSettle();
    return harness;
  }

  testWidgets('有匹配平台产物时，检查更新弹层出现「下载并安装」', (tester) async {
    await pumpAbout(tester, assets: _assets);
    await tester.tap(find.text('检查更新'));
    await tester.pumpAndSettle();
    expect(find.text('发现新版本'), findsOneWidget);
    expect(find.text('下载并安装'), findsOneWidget);
  });

  testWidgets('没有匹配平台产物时只显示「知道了」', (tester) async {
    await pumpAbout(tester, assets: const []);
    await tester.tap(find.text('检查更新'));
    await tester.pumpAndSettle();
    expect(find.text('发现新版本'), findsOneWidget);
    expect(find.text('下载并安装'), findsNothing);
    expect(find.text('知道了'), findsOneWidget);
  });

  group('备份口令弹层', () {
    Future<String? Function()> pumpDialog(
      WidgetTester tester, {
      required bool confirm,
    }) async {
      final harness = TestHarness.empty();
      addTearDown(harness.dispose);
      String? result;
      var done = false;
      await harness.pump(
        tester,
        Builder(
          builder: (context) => Scaffold(
            body: Center(
              child: ElevatedButton(
                onPressed: () async {
                  result = await showPassphraseDialog(
                    context,
                    confirm: confirm,
                  );
                  done = true;
                },
                child: const Text('open'),
              ),
            ),
          ),
        ),
        delegates: [
          AppLocalizations.delegate,
          ...GlobalMaterialLocalizations.delegates,
        ],
        supportedLocales: AppLocalizations.supportedLocales,
        locale: const Locale('zh'),
      );
      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();
      return () => done ? result : null;
    }

    testWidgets('空口令被拒绝', (tester) async {
      await pumpDialog(tester, confirm: false);
      await tester.tap(find.byKey(dataPassphraseOkKey));
      await tester.pumpAndSettle();
      expect(find.text('口令不能为空'), findsOneWidget);
    });

    testWidgets('两次输入不一致被拒绝', (tester) async {
      await pumpDialog(tester, confirm: true);
      await tester.enterText(find.byKey(dataPassphraseFieldKey), 'abc123');
      await tester.enterText(
        find.byKey(dataPassphraseConfirmFieldKey),
        'abc124',
      );
      await tester.tap(find.byKey(dataPassphraseOkKey));
      await tester.pumpAndSettle();
      expect(find.text('两次输入的口令不一致'), findsOneWidget);
    });

    testWidgets('一致时返回口令并关闭', (tester) async {
      final result = await pumpDialog(tester, confirm: true);
      await tester.enterText(find.byKey(dataPassphraseFieldKey), 'abc123');
      await tester.enterText(
        find.byKey(dataPassphraseConfirmFieldKey),
        'abc123',
      );
      await tester.tap(find.byKey(dataPassphraseOkKey));
      await tester.pumpAndSettle();
      expect(find.byType(PassphraseDialog), findsNothing);
      expect(result(), 'abc123');
    });
  });
}
