// Headless ChatService 消息流验证：
// 登录 → 发送一条消息给目标号 → 等待接收 → 打印 historyOf 与 eventStream 事件。
// 用法: MNC_UIN=... MNC_PASSWD=... MNC_DES=273640665 fvm dart run tool/headless_chat_flow.dart
import 'dart:async';
import 'dart:io';

import 'package:mnchat/core/models/messages.dart';
import 'package:mnchat/core/services/chat_service.dart';

Future<void> main() async {
  final uin = int.parse(Platform.environment['MNC_UIN']!);
  final passwd = Platform.environment['MNC_PASSWD']!;
  final des = int.parse(Platform.environment['MNC_DES'] ?? '273640665');

  final service = ChatService(db: null); // 纯内存，验证服务层
  final events = <ChatEvent>[];
  service.eventStream.listen(events.add);
  final states = <ChatServiceState>[];
  service.stateStream.listen(states.add);

  print('== 登录 $uin ==');
  final auth = await service.login(uin: uin, password: passwd);
  print('登录 OK: ${auth.name} / s2=${auth.s2.substring(0, 8)}...');

  print('== 等待会话加载 ==');
  await Future.delayed(const Duration(seconds: 2));
  final sessions = service.sessions;
  print('会话数: ${sessions.length}');
  final target = sessions.where((s) => s.id == des && s.type == ChatSessionType.friend).toList();
  print('目标会话存在: ${target.isNotEmpty}');
  final histBefore = service.historyOf(ChatSessionType.friend, des);
  print('发送前 historyOf($des) = ${histBefore.length} 条: $histBefore');

  final msg = 'MnChat-e2e-${DateTime.now().millisecondsSinceEpoch % 100000}';
  print('== 发送: $msg ==');
  final resp = await service.sendFriendMessage(des, msg);
  print('发送响应: $resp');

  // 本地乐观回显
  service.addLocalMessage(ChatSessionType.friend, des, msg);
  final histAfterSend = service.historyOf(ChatSessionType.friend, des);
  print('发送后立即 historyOf($des) = ${histAfterSend.length} 条');
  for (final m in histAfterSend) {
    print('  [${m.uin == service.myUin ? "我" : "对方"}] uin=${m.uin} time=${m.time} "$m"');
  }

  print('== 等待实时推送 (10s) ==');
  final before = events.length;
  await Future.delayed(const Duration(seconds: 10));
  print('新增事件: ${events.length - before}');
  for (final e in events.skip(before)) {
    print('  EVENT ${e.sessionType.name}#${e.sessionId}: ${e.message}');
  }

  print('== 最终 historyOf($des) ==');
  final histFinal = service.historyOf(ChatSessionType.friend, des);
  print('共 ${histFinal.length} 条');
  for (final m in histFinal) {
    print('  [${m.uin == service.myUin ? "我" : "对方"}] uin=${m.uin} time=${m.time} "$m"');
  }

  print('== 状态流 ==');
  print(states.map((s) => s.name).join(' -> '));
  print('== DONE ==');
  exit(0);
}
