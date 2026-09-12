/// 我的二维码页 —— 展示本人迷你号（游戏二维码内容即 uin 文本）。
///
/// 外部客户端无 QR 库依赖，以"迷你号大字号 + 复制"等价呈现；
/// 对方可用好友页"按迷你号添加"直接加我。
library;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../state/providers.dart';

class MyQrPage extends ConsumerWidget {
  const MyQrPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final uin = ref.watch(myUinProvider);
    return Scaffold(
      appBar: AppBar(title: const Text('我的二维码')),
      body: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.qr_code_2, size: 160, color: theme.colorScheme.primary),
            const SizedBox(height: 24),
            Text('我的迷你号', style: theme.textTheme.titleMedium),
            const SizedBox(height: 8),
            SelectableText(
              '$uin',
              style: theme.textTheme.headlineMedium?.copyWith(
                fontWeight: FontWeight.bold,
                letterSpacing: 2,
              ),
            ),
            const SizedBox(height: 24),
            FilledButton.icon(
              icon: const Icon(Icons.copy),
              label: const Text('复制迷你号'),
              onPressed: () {
                Clipboard.setData(ClipboardData(text: '$uin'));
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('已复制')),
                );
              },
            ),
            const SizedBox(height: 12),
            Text(
              '让对方在「好友 → 按迷你号添加」中输入此号码',
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.outline,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
