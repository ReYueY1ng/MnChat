import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:mnchat/core/services/chat_image.dart';
import 'package:mnchat/core/services/rich_media.dart' show RichMedia, ShareType;

/// 聊天发图：上传 token 解析 / CDN URL 拼接 / 分享卡编码。
///
/// URL 形状与真实常量来自 **live 只读读回实测**（2026-10-16，证据
/// `/tmp/ulw-run-mnchat/evidence/upload_url_probe.txt`）：上传一份 226B PNG 后
/// `http://map40.mini1.cn/map/40/20261017/<md5>.png` 回 200 `image/png`，
/// 字节与上传一致，且**没有**调用任何确认接口。下面用的就是那次上传的
/// node/dir/md5 原文，所以这两条断言是"编码对上线上实测"，不是自证。
void main() {
  group('上传 token', () {
    test('解析 token/node/dir', () {
      final t = parsePhotoUploadToken(
        'token=ceac5e9a2b0f315367511c835108ae0b&node=40&dir=20261017',
      );
      expect(t, isNotNull);
      expect(t!.token, 'ceac5e9a2b0f315367511c835108ae0b');
      expect(t.node, '40');
      expect(t.dir, '20261017');
    });

    test('缺任一字段 / 空 / 垃圾串 → null（不抛）', () {
      expect(parsePhotoUploadToken(''), isNull);
      expect(parsePhotoUploadToken('token=abc&node=40'), isNull);
      expect(parsePhotoUploadToken('token=&node=40&dir=20261017'), isNull);
      expect(parsePhotoUploadToken('ok'), isNull);
      expect(parsePhotoUploadToken('   '), isNull);
    });
  });

  group('CDN URL', () {
    test('拼接结果等于线上读回的那个 URL', () {
      expect(
        buildPhotoCdnUrl(
          node: '40',
          dir: '20261017',
          md5: 'b218a001968ea354cd55ce8733ffe5dc',
          ext: 'png',
        ),
        'http://map40.mini1.cn/map/40/20261017/b218a001968ea354cd55ce8733ffe5dc.png',
      );
    });

    test('node 进主机名与路径，dir 只进路径', () {
      final u = buildPhotoCdnUrl(
        node: '34',
        dir: '20260102',
        md5: '226e344ef0aaaaaaaaaaaaaaaaaaaaaaaa',
      );
      expect(u, startsWith('http://map34.mini1.cn/map/34/20260102/'));
      expect(u, endsWith('.png'));
    });

    test('扩展名归一：大写/无扩展/超长 → png', () {
      expect(mediaExtensionOf('a.PNG'), 'png');
      expect(mediaExtensionOf('a.jpeg'), 'jpeg');
      expect(mediaExtensionOf('noext'), 'png');
      expect(mediaExtensionOf('trailing.'), 'png');
      expect(mediaExtensionOf('a.verylongext'), 'png');
    });

    test('音频套图片扩展名上传（CDN 只发布图片扩展名）', () {
      // 这个常量就是协议契约：改它等于改上传协议，必须重测 CDN 的扩展名策略。
      expect(kVoiceCarrierExt, 'png');
      // 文件名带 .wav 时推导结果仍是 wav → 发送侧必须用 forceExt 显式覆盖。
      expect(mediaExtensionOf('clip.wav', fallback: kVoiceCarrierExt), 'wav');
      expect(mediaExtensionOf('a.JpG'), 'jpg');
    });

    test('非图片媒体的扩展名与缺省值', () {
      expect(mediaExtensionOf('voice.m4a'), 'm4a');
      expect(mediaExtensionOf('voice', fallback: 'mp3'), 'mp3');
      expect(mediaExtensionOf('no.ext'), 'ext');
    });
  });

  group('图片分享卡编码', () {
    const url = 'http://map40.mini1.cn/map/40/20261017/'
        'b218a001968ea354cd55ce8733ffe5dc.png';

    Map<String, Object?> decodeExtend(String extend) {
      var s = extend;
      if (s.contains('%')) s = Uri.decodeComponent(s);
      final m = jsonDecode(utf8.decode(base64Decode(s)));
      return (m as Map).cast<String, Object?>();
    }

    test('shareType=22、url 与 pic_list 双写、content 已 url_encode', () {
      final m = decodeExtend(
        buildImageShareExtend(nickname: '顾念', url: url, content: '看这个'),
      );
      expect(m['shareType'], ShareType.customPic);
      expect(m['shareType'], 22);
      expect(m['nickname'], '顾念');
      expect(m['url'], url);
      expect((m['pic_list'] as List).first, {'url': url});
      expect(m['bubble'], 0);
      expect(m['content'], Uri.encodeQueryComponent('看这个'));
      expect(Uri.decodeComponent('${m['content']}'), '看这个');
    });

    test('字段集与动态分享卡模板一致（除 pid 换成 url）', () {
      final m = decodeExtend(buildImageShareExtend(nickname: 'n', url: url));
      final keys = m.keys.toSet();
      expect(keys, {'nickname', 'shareType', 'url', 'pic_list', 'content', 'bubble'});
      // 对照动态分享卡（sendDynamicsShare）的模板字段。
      const dynKeys = {'nickname', 'shareType', 'pid', 'content', 'pic_list', 'bubble'};
      expect(keys.difference(dynKeys), {'url'});
      expect(dynKeys.difference(keys), {'pid'});
    });

    test('闭环：自己的编码能被自家 RichMedia.decode 读成图片卡', () {
      final media = RichMedia.decode(
        buildImageShareExtend(nickname: 'n', url: url, content: 'x'),
      );
      expect(media, isNotNull);
      expect(media!.shareType, ShareType.customPic);
      expect(media.url, url);
      expect(media.picList, contains(url));
      expect(media.content, 'x');
    });

    test('空正文也不产生裸 base64（永远 url_encode 过）', () {
      final raw = buildImageShareExtend(nickname: 'n', url: url);
      expect(raw.contains('%'), isTrue);
      expect(decodeExtend(raw)['content'], '');
    });
  });
}
