import 'package:flutter_test/flutter_test.dart';
import 'package:mnchat/core/utils/log.dart';

void main() {
  late List<String> lines;
  late LogLevel savedLevel;
  late LogSink? savedSink;

  setUp(() {
    lines = <String>[];
    savedLevel = Log.minLevel;
    savedSink = Log.sink;
    Log.sink = lines.add;
  });

  tearDown(() {
    Log.minLevel = savedLevel;
    Log.sink = savedSink;
  });

  group('Level gating', () {
    test('低于门限的级别不输出，门限及以上按序输出', () {
      Log.minLevel = LogLevel.warn;
      log.trace('t', tag: 'X');
      log.debug('d', tag: 'X');
      log.info('i', tag: 'X');
      log.warn('w', tag: 'X');
      log.error('e', tag: 'X');
      expect(lines, ['[WARN][X] w', '[ERROR][X] e']);
    });

    test('门限为 trace 时全部输出', () {
      Log.minLevel = LogLevel.trace;
      log.trace('t', tag: 'X');
      log.debug('d', tag: 'X');
      log.info('i', tag: 'X');
      expect(lines, ['[TRACE][X] t', '[DEBUG][X] d', '[INFO][X] i']);
    });

    test('测试（debug）环境下默认门限为 trace', () {
      expect(Log.minLevel, LogLevel.trace);
    });

    test('未传 tag 时使用默认标签 app', () {
      Log.minLevel = LogLevel.debug;
      log.debug('hello');
      expect(lines, ['[DEBUG][app] hello']);
    });
  });

  group('redactUrl', () {
    test('s2 / s2t / md5 的值被打码，其余参数原样保留', () {
      const url = 'https://x.example/api?act=get&uin=123'
          '&s2=abcdef&s2t=token&time=1&md5=deadbeef&encrypt_ver=3';
      expect(
        redactUrl(url),
        'https://x.example/api?act=get&uin=123'
        '&s2=***&s2t=***&time=1&md5=***&encrypt_ver=3',
      );
    });

    test('无查询串时原样返回', () {
      expect(redactUrl('https://x.example/api'), 'https://x.example/api');
      expect(redactUrl(''), '');
    });

    test('参数名大小写不敏感', () {
      expect(
        redactUrl('https://x.example/a?S2T=x&TOKEN=y&z=1'),
        'https://x.example/a?S2T=***&TOKEN=***&z=1',
      );
    });

    test('无值参数不破坏结构', () {
      expect(
        redactUrl('https://x.example/a?flag&s2t='),
        'https://x.example/a?flag&s2t=***',
      );
    });

    test('非敏感参数（如 uin）保留', () {
      expect(
        redactUrl('https://x.example/a?uin=42'),
        'https://x.example/a?uin=42',
      );
    });
  });
}
