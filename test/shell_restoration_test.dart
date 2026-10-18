// 状态恢复（RestorationMixin）验证：MainShell 记住"上次打开的会话"，
// 框架重启并回放 restoration 数据后，该会话被重新打开。
//
// 用框架自带的 `tester.restartAndRestore()`（与 Android 跨进程恢复同一套机制），
// 不是自己模拟：它要求 MaterialApp 挂了 restorationScopeId，正是生产的接线。
import 'package:drift/native.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:mnchat/core/models/messages.dart';
import 'package:mnchat/core/services/chat_service.dart';
import 'package:mnchat/core/storage/app_database.dart';
import 'package:mnchat/state/providers.dart';
import 'package:mnchat/ui/home_shell.dart' show MainShell;
import 'package:mnchat/ui/theme/app_theme.dart';

void main() {
  const selfUin = 279630451;
  const peerUin = 273640665;

  testWidgets('重启后恢复上次打开的会话', (tester) async {
    final db = AppDatabase(NativeDatabase.memory());
    addTearDown(db.close);
    final container = ProviderContainer(
      overrides: [
        databaseProvider.overrideWithValue(db),
        chatServiceProvider.overrideWithValue(ChatService(db: null)),
        // 恢复路径要等"账号就绪"（myUin > 0），这里直接给出已登录的 uin。
        myUinProvider.overrideWithValue(selfUin),
      ],
    );
    addTearDown(container.dispose);

    Widget app() => UncontrolledProviderScope(
      container: container,
      child: MaterialApp(
        theme: buildAppTheme(Brightness.light),
        restorationScopeId: 'mnchat',
        home: const MainShell(),
      ),
    );

    await tester.pumpWidget(app());
    await tester.pumpAndSettle();

    // 打开一个会话（模拟用户点开过它）
    container
        .read(activeSessionProvider.notifier)
        .open(ChatSessionType.friend, peerUin);
    await tester.pumpAndSettle();
    expect(container.read(activeSessionProvider)?.id, peerUin);

    // 再关掉：恢复要证明的是"记住上次看的会话"，而不是"当前还开着"。
    container.read(activeSessionProvider.notifier).close();
    await tester.pumpAndSettle();
    expect(container.read(activeSessionProvider), isNull);

    await tester.restartAndRestore();
    await tester.pumpAndSettle();

    final restored = container.read(activeSessionProvider);
    expect(
      restored?.id,
      peerUin,
      reason: '恢复后应重新打开上次的会话（${ChatSessionType.friend.name}_$peerUin）',
    );
  });
}
