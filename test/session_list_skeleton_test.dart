// 会话列表首屏骨架屏：加载中显示骨架，快照到达后消失（不再把"加载中"和
// "没有会话"混成同一个空态）。
import 'dart:async';

import 'package:drift/native.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:mnchat/core/models/messages.dart';
import 'package:mnchat/core/services/chat_service.dart';
import 'package:mnchat/core/storage/app_database.dart';
import 'package:mnchat/state/providers.dart';
import 'package:mnchat/ui/home_shell.dart' show MainShell;
import 'package:mnchat/ui/session_list_page.dart' show sessionsSkeletonKey;
import 'package:mnchat/ui/theme/app_theme.dart';

void main() {
  testWidgets('首屏加载显示骨架屏，快照到达后消失', (tester) async {
    final db = AppDatabase(NativeDatabase.memory());
    addTearDown(db.close);
    final controller = StreamController<SessionSnapshot>();
    addTearDown(controller.close);
    final container = ProviderContainer(
      overrides: [
        databaseProvider.overrideWithValue(db),
        chatServiceProvider.overrideWithValue(ChatService(db: null)),
        myUinProvider.overrideWithValue(279630451),
        // 会话流由测试控制：先一直挂着（首屏 loading），再推一个空快照。
        sessionListProvider.overrideWith((ref) => controller.stream),
      ],
    );
    addTearDown(container.dispose);

    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: MaterialApp(
          theme: buildAppTheme(Brightness.light),
          home: const MainShell(),
        ),
      ),
    );
    await tester.pump();

    expect(
      find.byKey(sessionsSkeletonKey),
      findsOneWidget,
      reason: '还没有任何快照时应显示骨架屏',
    );

    controller.add(
      SessionSnapshot(const <ChatSession>[], const <Contact>[]),
    );
    await tester.pumpAndSettle();

    expect(
      find.byKey(sessionsSkeletonKey),
      findsNothing,
      reason: '快照到达后骨架屏应消失',
    );
  });
}
