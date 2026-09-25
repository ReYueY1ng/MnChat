// 应用锁服务测试：PBKDF2(v2) 存储、旧版 sha256 透明升级、最短位数与失败节流。
//
// 采用真实内存 Drift 库（`AppDatabase(NativeDatabase.memory())`）承载
// [SettingsStore]，与 test/app_database_migration_test.dart 一致；节流逻辑
// 通过注入的时钟（`now:`）驱动，保证确定性，不依赖 `DateTime.now()`。
import 'dart:convert';

import 'package:crypto/crypto.dart' show sha256;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mnchat/core/services/app_lock.dart';
import 'package:mnchat/core/storage/app_database.dart';
import 'package:mnchat/core/storage/settings_store.dart';

void main() {
  late AppDatabase db;
  late SettingsStore settings;
  late DateTime fakeNow;

  setUp(() {
    db = AppDatabase(NativeDatabase.memory());
    settings = SettingsStore(db);
    fakeNow = DateTime(2026, 1, 1, 12);
  });

  tearDown(() async {
    await db.close();
  });

  AppLockService service() =>
      AppLockService(settings, now: () => fakeNow, iterations: 1000);

  /// 生产工作因子（默认 10 万次）实例，用于验证真实存储格式与迭代区间。
  AppLockService defaultService() =>
      AppLockService(settings, now: () => fakeNow);

  /// 按旧版格式（`sha256(salt + pin)` 十六进制）写入设置，模拟历史数据。
  Future<void> seedLegacy(String pin, {String? salt}) async {
    final s = salt ?? 'a1b2c3d4e5f60718293a4b5c6d7e8f90';
    final hash = sha256.convert(utf8.encode('$s$pin')).toString();
    await settings.setString(SettingsKeys.lockPinSalt, s);
    await settings.setString(SettingsKeys.lockPinHash, hash);
  }

  group('PIN 设置与位数规则', () {
    test('minPinLength 提升为 6', () {
      expect(AppLockService.minPinLength, 6);
    });

    test('setPin 拒绝 5 位及更短（ArgumentError）', () async {
      final s = service();
      expect(() => s.setPin('12345'), throwsArgumentError);
      expect(() => s.setPin('1234'), throwsArgumentError);
    });

    test('setPin 接受 6 位与 8 位数字', () async {
      final s = service();
      await s.setPin('123456');
      expect(await s.verifyPin('123456'), isTrue);

      await s.setPin('12345678');
      expect(await s.verifyPin('12345678'), isTrue);
    });

    test('setPin 拒绝非数字', () async {
      expect(() => service().setPin('12345a'), throwsArgumentError);
      expect(() => service().setPin('abcdef'), throwsArgumentError);
    });
  });

  group('PBKDF2(v2) 校验', () {
    test('正确 PIN 通过，错误 PIN 失败', () async {
      final s = service();
      await s.setPin('246810');
      expect(await s.verifyPin('246810'), isTrue);
      expect(await s.verifyPin('000000'), isFalse);
      expect(await s.verifyPin('246811'), isFalse);
    });

    test('存储值使用 v2 版本前缀且含迭代次数与盐', () async {
      final s = defaultService();
      await s.setPin('135790');
      final stored = await settings.getString(SettingsKeys.lockPinHash);
      expect(stored, isNotNull);
      expect(stored, startsWith('v2\$'));
      final parts = stored!.split(r'$');
      expect(parts, hasLength(4));
      expect(int.parse(parts[1]), inInclusiveRange(100000, 210000));
      expect(parts[2], isNotEmpty); // salt base64
      expect(parts[3], isNotEmpty); // hash base64
    });

    test('isPinSet 在设置后为 true，clearPin 后为 false', () async {
      final s = service();
      expect(await s.isPinSet(), isFalse);
      await s.setPin('654321');
      expect(await s.isPinSet(), isTrue);
      await s.clearPin();
      expect(await s.isPinSet(), isFalse);
    });
  });

  group('旧版 sha256 透明升级', () {
    test('4 位旧 PIN 仍可校验，成功后持久化为 v2', () async {
      await seedLegacy('1234');
      final s = service();

      expect(await s.verifyPin('1234'), isTrue, reason: '旧版 4 位 PIN 必须仍能解锁');

      final stored = await settings.getString(SettingsKeys.lockPinHash);
      expect(stored, startsWith('v2\$'), reason: '成功校验后应透明升级为 PBKDF2');
      // 升级后同一 PIN 继续可用（无需用户重新输入/改密）。
      expect(await s.verifyPin('1234'), isTrue);
    });

    test('5 位旧 PIN 也可校验（升级前）', () async {
      await seedLegacy('12345');
      final s = service();
      expect(await s.verifyPin('12345'), isTrue);
      final stored = await settings.getString(SettingsKeys.lockPinHash);
      expect(stored, startsWith('v2\$'));
    });

    test('6 位旧 PIN 校验并升级', () async {
      await seedLegacy('987654');
      final s = service();
      expect(await s.verifyPin('987654'), isTrue);
      expect(
        await settings.getString(SettingsKeys.lockPinHash),
        startsWith('v2\$'),
      );
    });

    test('旧版错误 PIN 不升级', () async {
      await seedLegacy('123456');
      final s = service();
      final before = await settings.getString(SettingsKeys.lockPinHash);
      expect(await s.verifyPin('000000'), isFalse);
      expect(await settings.getString(SettingsKeys.lockPinHash), before);
    });
  });

  group('失败节流', () {
    test('连续 5 次失败后锁定，正确 PIN 也被拒绝', () async {
      final s = service();
      await s.setPin('123456');

      for (var i = 0; i < AppLockService.maxAttempts; i++) {
        expect(await s.verifyPin('000000'), isFalse);
      }
      // 已锁定：正确 PIN 立即被拒绝（不再计算哈希）。
      expect(await s.verifyPin('123456'), isFalse);
    });

    test('越过锁定窗口后正确 PIN 恢复通过', () async {
      final s = service();
      await s.setPin('123456');
      for (var i = 0; i < AppLockService.maxAttempts; i++) {
        await s.verifyPin('000000');
      }
      expect(await s.verifyPin('123456'), isFalse); // 仍在锁定期

      fakeNow = fakeNow.add(
        AppLockService.lockBase + const Duration(seconds: 1),
      );
      expect(await s.verifyPin('123456'), isTrue);
    });

    test('成功校验重置失败计数', () async {
      final s = service();
      await s.setPin('123456');
      await s.verifyPin('000000');
      await s.verifyPin('000000');
      expect(await settings.getInt(SettingsKeys.lockAttempts), 2);

      expect(await s.verifyPin('123456'), isTrue);
      expect(await settings.getInt(SettingsKeys.lockAttempts), 0);
      expect(await settings.getInt(SettingsKeys.lockLockedUntil), 0);
    });

    test('锁定窗口按次数指数翻倍并封顶', () async {
      final s = service();
      await s.setPin('123456');
      // 前 5 次失败触发 30s 锁定。
      for (var i = 0; i < AppLockService.maxAttempts; i++) {
        await s.verifyPin('000000');
      }
      final firstUntil = await settings.getInt(SettingsKeys.lockLockedUntil);
      expect(
        firstUntil,
        fakeNow.add(AppLockService.lockBase).millisecondsSinceEpoch,
      );

      // 越过首个窗口后再错一次 → 窗口翻倍为 60s。
      fakeNow = fakeNow.add(
        AppLockService.lockBase + const Duration(seconds: 1),
      );
      await s.verifyPin('000000');
      final secondUntil = await settings.getInt(SettingsKeys.lockLockedUntil);
      expect(secondUntil! - firstUntil!, greaterThanOrEqualTo(60 * 1000));
    });

    test('未设置 PIN 时校验不触发锁定', () async {
      final s = service();
      expect(await s.verifyPin('123456'), isFalse);
      expect(
        await settings.getInt(SettingsKeys.lockAttempts),
        anyOf(isNull, 0),
      );
    });
  });

  group('clearPin 与容错', () {
    test('clearPin 清空盐/哈希并重置节流状态', () async {
      final s = service();
      await s.setPin('123456');
      await s.verifyPin('000000');
      await s.verifyPin('000000');

      await s.clearPin();

      expect(await settings.getString(SettingsKeys.lockPinSalt), '');
      expect(await settings.getString(SettingsKeys.lockPinHash), '');
      expect(await settings.getInt(SettingsKeys.lockAttempts), 0);
      expect(await settings.getInt(SettingsKeys.lockLockedUntil), 0);
      expect(await s.isPinSet(), isFalse);
    });

    test('损坏/畸形存储值返回 false 且不抛异常', () async {
      final s = service();
      final malformed = <String>[
        'v2\$notanumber\$QUJD\$REVG',
        'v2\$100000\$!!!not-base64!!!\$REVG',
        'v2\$100000\$QUJD', // 段数不足
        'v2\$\$QUJD\$REVG',
        'deadbeef', // 旧版格式但无盐 / 不匹配
        'not-a-hash',
      ];
      for (final bad in malformed) {
        await settings.setString(SettingsKeys.lockPinSalt, 'QUJD');
        await settings.setString(SettingsKeys.lockPinHash, bad);
        expect(
          await s.verifyPin('123456'),
          isFalse,
          reason: '畸形值应安全返回 false: $bad',
        );
      }
    });

    test('合法 v2 格式但哈希错误 → false', () async {
      final s = service();
      await settings.setString(SettingsKeys.lockPinSalt, 'QUJD');
      await settings.setString(
        SettingsKeys.lockPinHash,
        'v2\$100000\$QUJD\$AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA=',
      );
      expect(await s.verifyPin('123456'), isFalse);
    });
  });
}
