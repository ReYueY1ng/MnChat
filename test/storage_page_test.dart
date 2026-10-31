// 存储管理页：占用统计、保留期清理（带确认）、按会话清理。
import 'package:drift/drift.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:mnchat/core/storage/app_database.dart';
import 'package:mnchat/state/providers.dart';
import 'package:mnchat/ui/storage_page.dart';

import 'support/harness.dart';

void main() {
  late AppDatabase db;
  const owner = 7;

  setUp(() async {
    db = newTestDb();
    final now = DateTime.now().millisecondsSinceEpoch ~/ 1000;
    Future<void> add(String key, int time, String text) => db.insertMessage(
      ChatMessagesCompanion.insert(
        content: text,
        sessionKey: key,
        uin: 1,
        time: time,
        isSuccess: true,
        isSystemMsg: false,
        isTime: false,
        direction: 'in',
        ownerUin: const Value(owner),
      ),
    );
    await add('friend_1001', now - 100 * 24 * 3600, 'old-a');
    await add('friend_1001', now - 60 * 24 * 3600, 'old-b');
    await add('friend_1001', now - 10, 'recent');
    await add('group_2002', now - 200 * 24 * 3600, 'old-group');
  });

  tearDown(() => db.close());

  Future<void> pump(WidgetTester tester) async {
    final container = ProviderContainer(
      overrides: [
        databaseProvider.overrideWithValue(db),
        myUinProvider.overrideWithValue(owner),
      ],
    );
    final harness = TestHarness(container);
    addTearDown(harness.dispose);
    await harness.pump(tester, const StoragePage());
    await tester.pumpAndSettle();
  }

  testWidgets('显示占用与消息数', (tester) async {
    await pump(tester);
    expect(find.text('存储管理'), findsOneWidget);
    expect(find.textContaining('4 条消息'), findsOneWidget);
    expect(find.textContaining('2 个会话'), findsOneWidget);
  });

  testWidgets('保留 30 天需确认，确认后只留最近记录', (tester) async {
    await pump(tester);
    await tester.tap(find.byKey(storageRetentionKey(30)));
    await tester.pumpAndSettle();
    expect(find.byType(AlertDialog), findsOneWidget);
    expect(
      find.descendant(
        of: find.byType(AlertDialog),
        matching: find.textContaining('只保留最近 30 天'),
      ),
      findsOneWidget,
    );
    await tester.tap(find.text('删除'));
    await tester.pumpAndSettle();

    expect(await db.countMessages(owner), 1);
    expect(find.textContaining('1 条消息'), findsOneWidget);
  });

  testWidgets('取消确认不删除', (tester) async {
    await pump(tester);
    await tester.tap(find.byKey(storageRetentionKey(30)));
    await tester.pumpAndSettle();
    await tester.tap(find.text('取消'));
    await tester.pumpAndSettle();
    expect(await db.countMessages(owner), 4);
  });

  testWidgets('按会话清理只删该会话', (tester) async {
    await pump(tester);
    // 会话行标题为 key（无 sessionList 数据时的回退显示）。
    await tester.tap(find.text('group_2002'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('删除'));
    await tester.pumpAndSettle();
    expect(await db.countMessages(owner), 3);
  });
}
