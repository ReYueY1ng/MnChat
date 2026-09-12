// 回归测试：切换账号后 myUinProvider 必须返回**新账号**的 uin。
//
// 背景 bug：myUinProvider 原本 `watch(chatServiceProvider).myUin` ——
// chatServiceProvider 是单例 Provider（实例永不变化），Riverpod 认为
// 依赖未变、不 rebuild，切账号后 myUinProvider 缓存旧账号 uin。
// chat_page 用 myUinProvider 作为 Chat 组件的 currentUserId →
// 新账号发出的消息 authorId=新uin ≠ currentUserId(旧uin) 被 flutter_chat_ui
// 判为"对方消息"，表现为"换账号后发消息变成之前账号发的"。
//
// 修复：myUinProvider 改为 watch(authProvider)（Notifier，状态变化会
// 触发下游 rebuild），从 auth.auth.uin 读数。
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:mnchat/core/services/auth.dart' show MiniAuth;
import 'package:mnchat/core/services/chat_service.dart';
import 'package:mnchat/state/providers.dart';

/// 可控 AuthNotifier：手动 push 登录态，模拟"账号 A → 账号 B"切换。
class FakeAuthNotifier extends AuthNotifier {
  FakeAuthNotifier() {
    // AuthState 通过 Notifier 的 state 字段保持 —— AuthNotifier.state 是
    // protected setter 的下标，直接赋值即可触发监听者（正常流程由
    // login()/logout() 内部赋值）。
  }

  /// 模拟登录账号 [uin]。
  void loginAs(int uin) {
    state = AuthState(
      isLoggedIn: true,
      auth: MiniAuth(
        uin: uin,
        apiId: 110,
        name: '账号$uin',
        s2: 's2',
        s2t: 's2t',
        jwt: 'jwt',
      ),
    );
  }

  /// 模拟登出。
  void logoutFake() {
    state = const AuthState();
  }
}

void main() {
  test('myUinProvider 跟随 auth 账号变化（切账号不缓存旧 uin）', () {
    final container = ProviderContainer(
      overrides: [
        chatServiceProvider.overrideWithValue(ChatService(db: null)),
        authProvider.overrideWith(FakeAuthNotifier.new),
      ],
    );
    addTearDown(container.dispose);

    final auth = container.read(authProvider.notifier) as FakeAuthNotifier;

    // 初始未登录 → 0
    expect(container.read(myUinProvider), 0);

    // 登录账号 A（111）
    auth.loginAs(111);
    expect(container.read(myUinProvider), 111);

    // 切换账号 B（222）：此前 bug 会仍返回 111
    auth.logoutFake();
    expect(container.read(myUinProvider), 0);

    auth.loginAs(222);
    expect(container.read(myUinProvider), 222);
  });

  test('myUinProvider 复用同一聊天服务实例仍跟随账号', () {
    // 复现 bug 前提：chatServiceProvider 单例不变（overrideWithValue 同一实例），
    // 仅 authProvider 状态变化 —— 验证 myUinProvider 仍正确刷新。
    final service = ChatService(db: null);
    final container = ProviderContainer(
      overrides: [
        chatServiceProvider.overrideWithValue(service),
        authProvider.overrideWith(FakeAuthNotifier.new),
      ],
    );
    addTearDown(container.dispose);

    final auth = container.read(authProvider.notifier) as FakeAuthNotifier;
    auth.loginAs(333);
    expect(container.read(myUinProvider), 333);
  });
}