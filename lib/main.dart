import 'package:drift_flutter/drift_flutter.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'core/models/messages.dart';
import 'core/storage/app_database.dart';
import 'state/providers.dart';
import 'ui/chat_page.dart';
import 'ui/login_page.dart';
import 'ui/session_list_page.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  final db = AppDatabase(driftDatabase(name: 'mnchat'));
  runApp(ProviderScope(
    overrides: [databaseProvider.overrideWithValue(db)],
    child: const MnChatApp(),
  ));
}

class MnChatApp extends ConsumerWidget {
  const MnChatApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final auth = ref.watch(authProvider);

    return MaterialApp(
      title: 'MnChat · 迷你世界外部聊天',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        useMaterial3: true,
        colorSchemeSeed: const Color(0xFF00BFFF),
      ),
      darkTheme: ThemeData(
        useMaterial3: true,
        colorSchemeSeed: const Color(0xFF00BFFF),
        brightness: Brightness.dark,
      ),
      home: auth.isLoggedIn ? const MainShell() : const LoginPage(),
    );
  }
}

/// 登录后的主界面：左侧会话列表 + 右侧聊天窗口。
class MainShell extends ConsumerWidget {
  const MainShell({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final active = ref.watch(activeSessionProvider);
    final sessions = ref.watch(sessionListProvider);

    final list = sessions.when(
      data: (snap) => snap.sessions,
      loading: () => <ChatSession>[],
      error: (_, _) => <ChatSession>[],
    );

    return Scaffold(
      body: Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          SizedBox(
            width: 300,
            child: SessionListPage(sessions: list),
          ),
          const VerticalDivider(width: 1),
          Expanded(
            child: active == null
                ? const _EmptyChatPlaceholder()
                : ChatPage(
                    key: ValueKey('${active.type.name}_${active.id}'),
                    type: active.type,
                    sessionId: active.id,
                  ),
          ),
        ],
      ),
    );
  }
}

class _EmptyChatPlaceholder extends StatelessWidget {
  const _EmptyChatPlaceholder();

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.forum_outlined, size: 80, color: theme.colorScheme.outline),
          const SizedBox(height: 16),
          Text('选择左侧会话开始聊天', style: theme.textTheme.titleMedium),
          const SizedBox(height: 4),
          Text(
            '好友 / 群聊 · 无需进入房间',
            style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.outline),
          ),
        ],
      ),
    );
  }
}