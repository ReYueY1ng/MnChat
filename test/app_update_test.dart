// 检查更新的版本比较：远端 tag 是自由文本，必须「比较不对就退化成不比当前新」，
// 绝不抛异常（Renderer 里一次异常就是整页红屏）。
import 'package:flutter_test/flutter_test.dart';
import 'package:mnchat/core/services/app_update.dart';

void main() {
  group('compareVersion', () {
    test('按数字段比较，而不是字典序', () {
      expect(compareVersion('1.10.0', '1.9.9'), greaterThan(0));
      expect(compareVersion('1.9.9', '1.10.0'), lessThan(0));
      expect(compareVersion('1.0.0', '1.0.0'), 0);
    });

    test('段数不同时缺位补 0', () {
      expect(compareVersion('1.2', '1.2.0'), 0);
      expect(compareVersion('1.2.1', '1.2'), greaterThan(0));
      expect(compareVersion('2', '1.9.9'), greaterThan(0));
    });

    test('脏 tag 不抛异常（非数字段当 0）', () {
      expect(compareVersion('v-x', '1.0.0'), lessThan(0));
      expect(compareVersion('', '0.0.1'), lessThan(0));
    });

    test('预发布版比同主版本的正式版旧', () {
      expect(compareVersion('1.0.0-beta.2', '1.0.0'), lessThan(0));
      expect(compareVersion('1.0.0', '1.0.0-beta.1'), greaterThan(0));
      expect(compareVersion('1.0.0-beta.1', '1.0.0-beta.2'), lessThan(0));
      expect(compareVersion('1.1.0-beta.1', '1.0.0'), greaterThan(0));
    });
  });

  group('UpdateCheckResult.hasUpdate', () {
    test('远端更新 → true', () {
      const r = UpdateCheckResult(current: '1.0.0', latest: '1.2.0');
      expect(r.ok, isTrue);
      expect(r.hasUpdate, isTrue);
    });

    test('同版本 / 远端更旧 → false', () {
      expect(
        const UpdateCheckResult(current: '1.0.0', latest: '1.0.0').hasUpdate,
        isFalse,
      );
      expect(
        const UpdateCheckResult(current: '1.2.0', latest: '1.0.0').hasUpdate,
        isFalse,
      );
    });

    test('检查失败 → ok/hasUpdate 都是 false，而不是把错误当成新版本', () {
      const r = UpdateCheckResult(current: '1.0.0', error: 'Connection refused');
      expect(r.ok, isFalse);
      expect(r.hasUpdate, isFalse);
    });
  });
}
