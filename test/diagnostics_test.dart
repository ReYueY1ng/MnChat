// 诊断层：日志脱敏、轮转、尾部读取、诊断包内容。
import 'dart:io';

import 'package:drift/drift.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mnchat/core/services/diagnostics.dart';
import 'package:mnchat/core/storage/app_database.dart';
import 'package:mnchat/core/utils/rotating_log.dart';

import 'support/harness.dart';

void main() {
  late Directory dir;

  setUp(() {
    dir = Directory.systemTemp.createTempSync('mnchat_log_');
  });
  tearDown(() {
    if (dir.existsSync()) dir.deleteSync(recursive: true);
  });

  group('脱敏', () {
    test('query 与 JSON 里的令牌/密码都替换为 ***', () {
      final line = redactLogLine(
        'GET /minilb/alloc?s2=SECRET2&s2t=SECRET2T&md5=abc '
        '{"passwd":"p@ss","token":"jwt-xyz"}',
      );
      expect(line, isNot(contains('SECRET2')));
      expect(line, isNot(contains('SECRET2T')));
      expect(line, isNot(contains('p@ss')));
      expect(line, isNot(contains('jwt-xyz')));
      expect(line, contains('s2=***'));
      expect(line, contains('"passwd":"***"'));
      expect(line, contains('"token":"***"'));
    });

    test('普通文本不被误伤', () {
      expect(redactLogLine('message sent to friend 123'), 'message sent to friend 123');
    });
  });

  group('轮转文件', () {
    test('超过上限产生 .1/.2 且总文件数不超过 keep+1', () async {
      final log = RotatingLogFile(
        directory: dir,
        maxBytes: 400,
        keep: 2,
        now: () => DateTime.utc(2026, 10, 31, 12),
      );
      await log.init();
      for (var i = 0; i < 40; i++) {
        log.write('line $i ${'x' * 80}');
        await log.flush();
      }
      final files = dir
          .listSync()
          .whereType<File>()
          .map((f) => f.path)
          .toList();
      expect(files.length, lessThanOrEqualTo(3));
      expect(File('${dir.path}/mnchat.log.1').existsSync(), isTrue);
      expect(await log.totalBytes(), lessThan(400 * 3));

      final tail = await log.tail(lines: 5);
      expect(tail, hasLength(5));
      expect(tail.last, contains('line 39'));
    });

    test('clear 删除全部日志', () async {
      final log = RotatingLogFile(directory: dir, maxBytes: 100, keep: 1);
      await log.init();
      for (var i = 0; i < 10; i++) {
        log.write('y' * 40);
        await log.flush();
      }
      expect(await log.totalBytes(), greaterThan(0));
      await log.clear();
      expect(await log.totalBytes(), 0);
      expect(File('${dir.path}/mnchat.log').existsSync(), isFalse);
    });
  });

  group('诊断包', () {
    test('包含版本/平台/schema/表计数与日志尾部', () async {
      final db = newTestDb();
      addTearDown(db.close);
      await db.insertMessage(
        ChatMessagesCompanion.insert(
          content: 'hello',
          sessionKey: 'friend_1',
          uin: 1,
          time: 1,
          isSuccess: true,
          isSystemMsg: false,
          isTime: false,
          direction: 'in',
          ownerUin: const Value(7),
        ),
      );
      final log = RotatingLogFile(directory: dir);
      await log.init();
      log.write('[WARN][Net] boom');
      await log.flush();

      final report = await DiagnosticsService(
        logFile: log,
        db: db,
      ).buildReport(ownerUin: 7);

      expect(report, contains('schema=11'));
      expect(report, contains('messages=1'));
      expect(report, contains('sessions=0'));
      expect(report, contains('--- log tail ---'));
      expect(report, contains('[WARN][Net] boom'));
      expect(report, contains('db_bytes='));
    });
  });
}
