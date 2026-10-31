// 更新下载：产物解析、仅 https、进度回调、SHA-256 校验与失败清理。
import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart' show sha256;
import 'package:flutter_test/flutter_test.dart';
import 'package:mnchat/core/services/app_update.dart';

void main() {
  group('发布 JSON 解析', () {
    test('解析 tag / 网页 / 资产与 sha256 digest', () {
      final result = AppUpdateClient.parseLatestRelease(
        {
          'tag_name': 'v1.2.3',
          'html_url': 'https://github.com/ReYueY1ng/MnChat/releases/tag/v1.2.3',
          'assets': [
            {
              'name': 'mnchat.apk',
              'browser_download_url': 'https://example.com/mnchat.apk',
              'digest': 'sha256:ABCDEF',
            },
            {
              'name': 'mnchat-linux.tar.gz',
              'browser_download_url': 'https://example.com/linux.tar.gz',
            },
            {'name': 'no-url'},
          ],
        },
        current: '1.0.0',
      );
      expect(result.ok, isTrue);
      expect(result.hasUpdate, isTrue);
      expect(result.assets, hasLength(2));
      expect(result.assetForExtension('.apk')?.sha256, 'abcdef');
      expect(result.assetForExtension('.tar.gz')?.sha256, isNull);
      expect(result.assetForExtension('.zip'), isNull);
    });

    test('缺少 tag 返回错误而不是抛', () {
      final r = AppUpdateClient.parseLatestRelease(
        const <Object?, Object?>{},
        current: '1.0.0',
      );
      expect(r.ok, isFalse);
      expect(r.error, isNotNull);
    });
  });

  test('下载地址只允许 https 与本机回环 http', () {
    expect(
      AppUpdateClient.isAllowedDownloadUrl('https://example.com/a.apk'),
      isTrue,
    );
    expect(
      AppUpdateClient.isAllowedDownloadUrl('http://127.0.0.1:8080/a.apk'),
      isTrue,
    );
    expect(AppUpdateClient.isAllowedDownloadUrl('http://example.com/a'), isFalse);
    expect(AppUpdateClient.isAllowedDownloadUrl('ftp://example.com/a'), isFalse);
    expect(AppUpdateClient.isAllowedDownloadUrl('not a url'), isFalse);
  });

  group('下载与校验', () {
    late HttpServer server;
    late Directory dir;
    late String base;
    final body = utf8.encode('mnchat update payload');
    final goodHash = sha256.convert(body).toString();

    setUp(() async {
      dir = Directory.systemTemp.createTempSync('mnchat_update_');
      server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      server.listen((req) async {
        req.response.add(body);
        await req.response.close();
      });
      base = 'http://127.0.0.1:${server.port}';
    });

    tearDown(() async {
      await server.close(force: true);
      if (dir.existsSync()) dir.deleteSync(recursive: true);
    });

    test('哈希匹配：落盘并回调进度', () async {
      final progress = <int>[];
      final file = await AppUpdateClient().downloadAsset(
        UpdateAsset(
          name: 'mnchat-test.bin',
          url: '$base/mnchat-test.bin',
          sha256: goodHash,
        ),
        directory: dir,
        onProgress: (received, _) => progress.add(received),
      );
      expect(await file.readAsBytes(), body);
      expect(progress, isNotEmpty);
      expect(progress.last, body.length);
    });

    test('哈希不匹配：抛错并删除文件', () async {
      final file = File('${dir.path}/mnchat-test.bin');
      await expectLater(
        AppUpdateClient().downloadAsset(
          UpdateAsset(
            name: 'mnchat-test.bin',
            url: '$base/mnchat-test.bin',
            sha256: sha256.convert(utf8.encode('other')).toString(),
          ),
          directory: dir,
        ),
        throwsA(isA<UpdateDownloadException>()),
      );
      expect(file.existsSync(), isFalse);
    });

    test('非 https 的远端地址直接拒绝', () async {
      await expectLater(
        AppUpdateClient().downloadAsset(
          const UpdateAsset(
            name: 'x.bin',
            url: 'http://example.com/x.bin',
          ),
          directory: dir,
        ),
        throwsA(isA<UpdateDownloadException>()),
      );
    });
  });
}
