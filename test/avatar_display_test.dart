/// 头像展示规则回归：`header*` 不是头像、DIY 优先、头像接口必须带 uin。
///
/// 依据（真实账号探针 + 反编译）：
///   - `header`/`header2` 在服务端放的是**地图截图**（`map<NNN>.mini1.cn/map/...`），
///     不是头像 → [PlayerProfile.fromItem] 不再把它们当头像；
///   - DIY 自定义头像来自 `getPersonCenterHeadInfo` 的 `diy_header.pass_url`
///     （`use_diy == 1` 才用）；否则用角色头像本体（`headinfosysmgr.lua:321-383`）；
///   - 该接口缺 `uin` 时服务端回**空 body**，头像本体 / DIY 一个也取不到；
///   - 该接口**每请求只回前 50 个 uin**（实测 2026-10-09：45/49/50 全回，
///     51/60/100/164 都只回 50 条），所以客户端必须分片。
library;

import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
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

ProfileClient _profileClient(HttpClientAdapter adapter) => ProfileClient(
  uin: 7,
  s2: 's2',
  s2t: 's2t',
  dio: Dio()..httpClientAdapter = adapter,
  baseUrl: 'https://example.invalid',
);

/// 复刻服务端「每请求只回前 50 条」的坏行为（实测：45/49/50 全回，51/60/100/164
/// 都只回 50 条），用来证明客户端确实分了片。这里写死 50 而不引用
/// `ProfileClient.kHeadInfoBatchSize`：常量若被改错，测试才不会跟着一起错。
class _CappedHeadAdapter implements HttpClientAdapter {
  static const int serverCap = 50;

  final List<RequestOptions> requests = <RequestOptions>[];
  int maxAsked = 0;
  bool missingUinParam = false;

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    requests.add(options);
    final q = options.uri.queryParameters;
    if ((q['uin'] ?? '').isEmpty) missingUinParam = true;
    final asked = (q['op_uin_list'] ?? '')
        .split(',')
        .where((s) => s.isNotEmpty)
        .toList();
    if (asked.length > maxAsked) maxAsked = asked.length;
    final entries = asked
        .take(serverCap)
        .map(
          (u) =>
              '"$u":{"type":1,"id":7,"use_diy":1,'
              '"diy_header":{"pre_url":"","pass_url":"https://cdn.invalid/$u.png"}}',
        )
        .join(',');
    return ResponseBody.fromString(
      '{"code":0,"data":{$entries}}',
      200,
      headers: <String, List<String>>{
        Headers.contentTypeHeader: <String>['text/plain'],
      },
    );
  }

  @override
  void close({bool force = false}) {}
}

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

  group('头像接口：服务端每请求只回前 50 条', () {
    List<int> uins(int n) => List<int>.generate(n, (i) => 100000 + i);

    test('getPersonCenterHeadInfos：120 个 uin 分 3 批全部取到', () async {
      final adapter = _CappedHeadAdapter();
      final slots = await _profileClient(adapter).getPersonCenterHeadInfos(uins(120));
      expect(slots.length, 120, reason: '漏人说明没分片');
      expect(adapter.requests.length, 3, reason: '应为 50 + 50 + 20');
      expect(adapter.maxAsked, _CappedHeadAdapter.serverCap);
      expect(adapter.missingUinParam, isFalse, reason: '缺 uin 服务端回空 body');
      expect(slots[100119]?.diyUrl, 'https://cdn.invalid/100119.png');
    });

    test('getPersonCenterHeadInfo：同样分片，DIY url 一条不少', () async {
      final adapter = _CappedHeadAdapter();
      final diy = await _profileClient(adapter).getPersonCenterHeadInfo(uins(120));
      expect(diy.length, 120);
      expect(adapter.requests.length, 3);
      expect(adapter.maxAsked, _CappedHeadAdapter.serverCap);
    });

    test('刚好 50 个只发一次请求', () async {
      final adapter = _CappedHeadAdapter();
      final slots = await _profileClient(adapter).getPersonCenterHeadInfos(uins(50));
      expect(slots.length, 50);
      expect(adapter.requests.length, 1);
    });
  });
}
