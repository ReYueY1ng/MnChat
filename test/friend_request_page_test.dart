// 群邀请 tab 回归：未登录时不能因为 initState 里读 Localizations 而崩。
//
// `_load()` 在 initState 里同步开跑，旧实现在第一个 `await` 之前就取
// `l10nOf(context)`；assert 抛出的异常被 async 函数收进 Future，tab 只剩
// 空白（连「暂无群邀请」都不显示）。
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:mnchat/core/services/chat_service.dart' show ChatService;
import 'package:mnchat/state/providers.dart';
import 'package:mnchat/ui/friend_request_page.dart';
import 'package:mnchat/ui/theme/app_theme.dart';

void main() {
  testWidgets('未登录进入群邀请 tab：显示未登录且不抛异常', (tester) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          chatServiceProvider.overrideWithValue(ChatService(db: null)),
        ],
        child: MaterialApp(
          theme: buildAppTheme(Brightness.light),
          home: const FriendRequestPage(),
        ),
      ),
    );
    await tester.pump();

    await tester.tap(find.text('群邀请'));
    await tester.pumpAndSettle();

    expect(find.text('未登录'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
