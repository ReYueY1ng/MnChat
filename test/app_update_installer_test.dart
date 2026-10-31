// 更新包打开：平台命令映射、缺失文件、失败/不支持都不抛。
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:mnchat/core/services/app_update_installer.dart';

void main() {
  late Directory dir;
  late File file;

  setUp(() {
    dir = Directory.systemTemp.createTempSync('mnchat_installer_');
    file = File('${dir.path}/update.bin')..writeAsBytesSync([1, 2, 3]);
  });
  tearDown(() {
    if (dir.existsSync()) dir.deleteSync(recursive: true);
  });

  test('Linux 用 xdg-open，exe 与参数正确', () async {
    final calls = <(String, List<String>)>[];
    final installer = UpdateInstaller(
      platform: 'linux',
      start: (exe, args) async {
        calls.add((exe, args));
        return ProcessResult(0, 0, '', '');
      },
    );
    expect(installer.supported, isTrue);
    expect(await installer.open(file), isTrue);
    expect(calls.single.$1, 'xdg-open');
    expect(calls.single.$2, [file.path]);
  });

  test('Windows / macOS 命令映射', () async {
    final calls = <String>[];
    Future<ProcessResult> start(String exe, List<String> args) async {
      calls.add(exe);
      return ProcessResult(0, 0, '', '');
    }

    await UpdateInstaller(platform: 'windows', start: start).open(file);
    await UpdateInstaller(platform: 'macos', start: start).open(file);
    expect(calls, ['explorer', 'open']);
  });

  test('空文件 / 不支持的平台返回 false 且不启动进程', () async {
    var started = 0;
    Future<ProcessResult> start(String exe, List<String> args) async {
      started++;
      return ProcessResult(0, 0, '', '');
    }

    expect(
      await UpdateInstaller(platform: 'linux', start: start).open(
        File('${dir.path}/missing.bin'),
      ),
      isFalse,
    );
    expect(started, 0);

    final android = UpdateInstaller(platform: 'android', start: start);
    expect(android.supported, isFalse);
    expect(await android.open(file), isFalse);
    expect(started, 0);
  });

  test('进程启动异常被吞掉并返回 false', () async {
    final installer = UpdateInstaller(
      platform: 'linux',
      start: (exe, args) async => throw StateError('no xdg-open'),
    );
    expect(await installer.open(file), isFalse);
  });
}
