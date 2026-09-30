import 'dart:io';

import 'package:archive/archive.dart';
import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mnchat/core/models/emoji_catalog.dart';
import 'package:mnchat/core/services/emoji_store.dart';
import 'package:mnchat/core/services/miniw_extra.dart';

/// 表情素材下载→解包→缓存 管线的单测（用假 Dio 喂 zip 字节，不触网）。
void main() {
  late Directory tmp;

  setUp(() async {
    tmp = await Directory.systemTemp.createTemp('mnchat_emoji_store_test');
  });

  tearDown(() async {
    if (tmp.existsSync()) await tmp.delete(recursive: true);
  });

  List<int> zipWith(Map<String, List<int>> entries) {
    final archive = Archive();
    entries.forEach((name, data) {
      archive.addFile(ArchiveFile(name, data.length, data));
    });
    return ZipEncoder().encode(archive);
  }

  /// 假 Dio：所有请求直接返回 [bytes]，并记录命中的 URL。
  Dio fakeDio(List<int> bytes, List<String> hits) {
    final dio = Dio();
    dio.interceptors.add(
      InterceptorsWrapper(
        onRequest: (options, handler) {
          hits.add(options.uri.toString());
          handler.resolve(
            Response<List<int>>(
              requestOptions: options,
              data: bytes,
              statusCode: 200,
            ),
          );
        },
      ),
    );
    return dio;
  }

  EmojiStore storeWith(Dio dio) => EmojiStore(
        client: EmojiClient(
          uin: 1,
          s2: 's2',
          s2t: 's2t',
          dio: dio,
          baseUrl: 'http://x',
        ),
        dio: dio,
        cacheRoot: tmp.path,
      );

  const pack = EmojiPack(id: '5', filesUrl: {'01': 'http://x/5/01.zip'});
  const pic = EmojiPic(packId: '5', picId: '01', icon: 'qinqin.png');

  test('下载 zip → 解包出 <icon>.png 并落缓存（二次命中不再请求）', () async {
    final png = List<int>.generate(64, (i) => i % 256);
    final hits = <String>[];
    // zip 内放在子目录，验证 basename 匹配
    final dio = fakeDio(zipWith({'icons/qinqin.png': png}), hits);
    final store = storeWith(dio);

    final path = await store.ensurePicFile(pack, pic);
    expect(path, isNotNull);
    expect(File(path!).readAsBytesSync(), png);

    final again = await store.ensurePicFile(pack, pic);
    expect(again, path);
    expect(hits.length, 1, reason: '第二次应命中磁盘缓存');
  });

  test('同一张图并发请求只下载一次（in-flight 合并）', () async {
    final hits = <String>[];
    final dio = fakeDio(zipWith({'qinqin.png': [1, 2, 3, 4]}), hits);
    final store = storeWith(dio);

    final results = await Future.wait([
      store.ensurePicFile(pack, pic),
      store.ensurePicFile(pack, pic),
      store.ensurePicFile(pack, pic),
    ]);
    expect(results.every((p) => p != null), isTrue);
    expect(hits.length, 1, reason: '并发请求应合并为一次下载');
  });

  test('zip 内没有目标图标 → null（不写成别的表情）', () async {
    final hits = <String>[];
    final dio = fakeDio(zipWith({'other.png': [1, 2, 3]}), hits);
    final store = storeWith(dio);

    expect(await store.ensurePicFile(pack, pic), isNull);
  });

  test('旧包（1/3）不下载，直接返回 null', () async {
    final hits = <String>[];
    final dio = fakeDio(zipWith({'qinqin.png': [1]}), hits);
    final store = storeWith(dio);

    const legacy = EmojiPack(id: '1');
    expect(
      await store.ensurePicFile(
        legacy,
        const EmojiPic(packId: '1', picId: '06', icon: 'qinqin.png'),
      ),
      isNull,
    );
    expect(hits, isEmpty);
  });

  test('素材地址缺失（协议未给 emoji_files_url）→ null', () async {
    final hits = <String>[];
    final dio = fakeDio(zipWith({'qinqin.png': [1]}), hits);
    final store = storeWith(dio);

    expect(
      await store.ensurePicFile(const EmojiPack(id: '9'), pic),
      isNull,
    );
    expect(hits, isEmpty);
  });
}
