// 加密备份：容器往返、错误口令、篡改、以及 BackupService 的加密封装。
import 'dart:convert';

import 'package:drift/drift.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mnchat/core/services/backup.dart';
import 'package:mnchat/core/services/backup_crypto.dart';
import 'package:mnchat/core/storage/app_database.dart';

import 'support/harness.dart';

void main() {
  final plain = utf8.encode('{"app":"mnchat","secret":"hello"}');

  group('容器', () {
    test('往返一致；两次加密的盐/密文不同', () async {
      final a = await encryptBackup(
        plain,
        passphrase: 'correct horse',
        iterations: 1000,
      );
      final b = await encryptBackup(
        plain,
        passphrase: 'correct horse',
        iterations: 1000,
      );
      expect(a, isNot(equals(b)));
      expect(isEncryptedBackup(a), isTrue);
      expect(
        await decryptBackup(a, passphrase: 'correct horse'),
        plain,
      );
    });

    test('错误口令抛 BackupDecryptException', () async {
      final box = await encryptBackup(
        plain,
        passphrase: 'right',
        iterations: 1000,
      );
      await expectLater(
        decryptBackup(box, passphrase: 'wrong'),
        throwsA(isA<BackupDecryptException>()),
      );
    });

    test('篡改密文/标签会被 GCM 拒绝', () async {
      final box = await encryptBackup(
        plain,
        passphrase: 'pw',
        iterations: 1000,
      );
      final map = jsonDecode(utf8.decode(box)) as Map<String, dynamic>;
      final cipher = base64Decode(map['ciphertext'] as String);
      cipher[0] ^= 0xFF;
      map['ciphertext'] = base64Encode(cipher);
      await expectLater(
        decryptBackup(
          utf8.encode(jsonEncode(map)),
          passphrase: 'pw',
        ),
        throwsA(isA<BackupDecryptException>()),
      );
    });

    test('明文 JSON 不会被误判为加密', () {
      expect(isEncryptedBackup(plain), isFalse);
      expect(isEncryptedBackup(utf8.encode('not json')), isFalse);
    });
  });

  group('BackupService 加密封装', () {
    late AppDatabase db;

    setUp(() async {
      db = newTestDb();
      await db.insertMessage(
        ChatMessagesCompanion.insert(
          content: '秘密消息',
          sessionKey: 'friend_1001',
          uin: 1001,
          time: 1700000000,
          isSuccess: true,
          isSystemMsg: false,
          isTime: false,
          direction: 'in',
          ownerUin: const Value(7),
        ),
      );
    });
    tearDown(() => db.close());

    test('加密导出：明文不出现在文件里，正确口令可导入', () async {
      final service = BackupService(db);
      final bytes = await service.exportJson(7, passphrase: 'pw-123');
      expect(isEncryptedBackup(bytes), isTrue);
      expect(utf8.decode(bytes, allowMalformed: true), isNot(contains('秘密消息')));

      final target = newTestDb();
      addTearDown(target.close);
      final result = await BackupService(
        target,
      ).importJson(bytes, passphrase: 'pw-123');
      expect(result.messages, 1);
      final rows = await target.allMessages(7);
      expect(rows.single.content, '秘密消息');
    });

    test('加密备份缺少/错误口令都拒绝，不写入任何数据', () async {
      final bytes = await BackupService(db).exportJson(7, passphrase: 'pw');
      final target = newTestDb();
      addTearDown(target.close);

      await expectLater(
        BackupService(target).importJson(bytes),
        throwsA(isA<BackupDecryptException>()),
      );
      await expectLater(
        BackupService(target).importJson(bytes, passphrase: 'bad'),
        throwsA(isA<BackupDecryptException>()),
      );
      expect(await target.countMessages(7), 0);
    });

    test('不加密导出仍可导入（旧格式回归）', () async {
      final service = BackupService(db);
      final bytes = await service.exportJson(7);
      expect(isEncryptedBackup(bytes), isFalse);

      final target = newTestDb();
      addTearDown(target.close);
      final result = await BackupService(target).importJson(bytes);
      expect(result.messages, 1);
    });
  });
}
