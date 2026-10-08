/// 头像展示规则回归：`header*` 不是头像、DIY 优先、头像接口必须带 uin。
///
/// 依据（2026-10-08 真实账号探针 + 反编译）：
///   - `header`/`header2` 在服务端放的是**地图截图**（`map<NNN>.mini1.cn/map/...`），
///     不是头像 → [PlayerProfile.fromItem] 不再把它们当头像；
///   - DIY 自定义头像来自 `getPersonCenterHeadInfo` 的 `diy_header.pass_url`
///     （`use_diy == 1` 才用）；否则用角色头像本体（`headinfosysmgr.lua:321-383`）；
///   - 该接口缺 `uin` 时服务端回**空 body**，头像本体 / DIY 一个也取不到。
library;

import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mnchat/core/models/nickname.dart' show topicRef;
import 'package:mnchat/core/services/profile.dart';

/// 按 `act` 回放固定响应体的假 Dio 适配器（离线）。
class _StubAdapter implements HttpClientAdapter {
  _StubAdapter(this._bodies);

  final Map<String, String> _bodies;
  final List<RequestOptions> requests = <RequestOptions>[];

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    requests.add(options);
    final act = options.uri.queryParameters['act'] ?? '';
    return ResponseBody.fromString(
      _bodies[act] ?? '{"ret":0}',
      200,
      headers: <String, List<String>>{
        Headers.contentTypeHeader: <String>['text/plain'],
      },
    );
  }

  @override
  void close({bool force = false}) {}
}

ProfileClient _profileClient(_StubAdapter adapter) => ProfileClient(
  uin: 7,
  s2: 's2',
  s2t: 's2t',
  dio: Dio()..httpClientAdapter = adapter,
  baseUrl: 'https://example.invalid',
);

void main() {
  group('PlayerProfile.fromItem：header* 不是头像', () {
    test('header/header2（地图截图）不再进 avatarUrl', () {
      final p = PlayerProfile.fromItem(<String, Object?>{
        'uin': 7,
        'profile': <String, Object?>{
          'uin': 7,
          'header2': <String, Object?>{
            'url': 'http://map995.mini1.cn/map/995/20240323/41cd.png',
          },
          'header': <String, Object?>{
            'url': 'http://map40.mini1.cn/map/40/20231231/26eb.png',
          },
          'RoleInfo': <String, Object?>{'NickName': '甲', 'SkinID': 211},
        },
      });
      expect(p, isNotNull);
      expect(p!.avatarUrl, isNull);
      expect(p.nickname, '甲');
      expect(p.headSkinId, 211);
    });
  });

  group('fetchAvatarProfiles：DIY > 角色头像本体 > 首字', () {
    String batch3Json(int skinId) =>
        '{"data":[{"uin":7,"profile":{"uin":7,"RoleInfo":'
        '{"NickName":"甲","SkinID":$skinId}}}]}';

    test('use_diy=1 → 用 DIY pass_url，清掉角色头像本体', () async {
      final adapter = _StubAdapter({
        'getProfileBatch3': batch3Json(211),
        'getPersonCenterHeadInfo':
            '{"code":0,"data":{"7":{"type":1,"id":121,"use_diy":1,'
                '"diy_header":{"pass_url":"http://x/y.png"}}}}',
      });
      final out = await _profileClient(adapter).fetchAvatarProfiles([7]);
      expect(out[7]!.avatarUrl, 'http://x/y.png');
      expect(out[7]!.headType, isNull);
      expect(out[7]!.headId, isNull);
    });

    test('未启用 DIY → 角色头像本体（有本地图标时）', () async {
      final adapter = _StubAdapter({
        'getProfileBatch3': batch3Json(211),
        'getPersonCenterHeadInfo':
            '{"code":0,"data":{"7":{"type":1,"id":121,'
                '"diy_header":{"pass_url":"http://x/y.png"}}}}',
      });
      final out = await _profileClient(adapter).fetchAvatarProfiles([7]);
      expect(out[7]!.avatarUrl, isNull, reason: 'pass_url 存在但 use_diy != 1');
      expect(out[7]!.headType, 1);
      expect(out[7]!.headId, 121);
    });

    test('两个接口都空 → 不臆造（退首字）', () async {
      final adapter = _StubAdapter({
        'getProfileBatch3': '{"data":[]}',
        'getPersonCenterHeadInfo': '{"code":0,"data":{}}',
      });
      final out = await _profileClient(adapter).fetchAvatarProfiles([7]);
      expect(out[7]!.avatarUrl, isNull);
      expect(out[7]!.headType, isNull);
      expect(out[7]!.headId, isNull);
    });

    test('请求头带 uin（缺 uin 时服务端回空 body）', () async {
      final adapter = _StubAdapter({
        'getProfileBatch3': batch3Json(211),
        'getPersonCenterHeadInfo': '{"code":0,"data":{}}',
      });
      await _profileClient(adapter).fetchAvatarProfiles([7]);
      final headReq = adapter.requests.firstWhere(
        (r) => r.uri.queryParameters['act'] == 'getPersonCenterHeadInfo',
      );
      expect(headReq.uri.queryParameters['uin'], '7');
      expect(headReq.uri.queryParameters['op_uin_list'], '7');
    });
  });

  group('topicRef', () {
    test('抽出标签与话题 id', () {
      expect(topicRef('#{迷你世界&o:21}'), (label: '迷你世界', id: 'o:21'));
      expect(topicRef('#{福利}'), (label: '福利', id: ''));
      expect(topicRef('普通文本'), isNull);
      expect(topicRef('#{}'), isNull);
    });
  });
}
