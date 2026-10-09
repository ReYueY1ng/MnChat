// 「同一份玩家资料 / 主页数据只拉一次」的客户端级缓存测试。
//
// 症状来源（用户报告）：
//   - 进 App 后自己的资料被多次获取（getProfileBatch3 / getPersonCenterHeadInfo）；
//   - 先点开玩家卡片再进玩家主页 → 重复发 get_user_homepage /
//     get_level_info_batch / getPersonCenterHeadInfo；
//   - 动态详情补齐作者资料时又要一遍。
// 断言全部是**请求次数**：并发合并用一个卡住的 Future，没有任何时间等待。
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mnchat/core/services/player_home.dart'
    show PlayerHomeClient, kPlayerHomeCacheTtl;
import 'package:mnchat/core/services/profile.dart'
    show PlayerProfile, ProfileClient, kProfileFetchCacheTtl;

/// 记录请求、按 `act` 回放固定响应体的适配器（离线）。
class _StubAdapter implements HttpClientAdapter {
  _StubAdapter(this.bodyByAct);

  final Map<String, String> bodyByAct;

  final List<RequestOptions> requests = <RequestOptions>[];

  List<RequestOptions> act(String act) => requests
      .where((r) => r.uri.queryParameters['act'] == act)
      .toList(growable: false);

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    requests.add(options);
    final act = options.uri.queryParameters['act'] ?? '';
    return ResponseBody.fromString(
      bodyByAct[act] ?? '{"ret":0}',
      200,
      headers: <String, List<String>>{
        Headers.contentTypeHeader: <String>['text/plain'],
      },
    );
  }

  @override
  void close({bool force = false}) {}
}

const String _batch3Body =
    '{"data":[{"uin":7,"profile":{"uin":7,"RoleInfo":'
    '{"NickName":"甲","SkinID":211}}}]}';
const String _headBody =
    '{"code":0,"data":{"7":{"type":1,"id":121,"use_diy":1,'
    '"diy_header":{"pass_url":"http://x/y.png"}}}}';
const String _homeBody = '{"code":0,"data":{"signature":{"data":1}}}';
const String _levelBody = '{"code":0,"data":[{"uin":7,"level":12}]}';
const String _scoreBody = '{"code":0,"data":{"level":3}}';

ProfileClient _profile(_StubAdapter adapter, {Duration? ttl}) => ProfileClient(
  uin: 7,
  s2: 's2',
  s2t: 's2t',
  dio: Dio()..httpClientAdapter = adapter,
  baseUrl: 'https://example.invalid',
  cacheTtl: ttl ?? kProfileFetchCacheTtl,
);

PlayerHomeClient _home(
  _StubAdapter adapter, {
  Duration? ttl,
}) => PlayerHomeClient(
  uin: 7,
  s2: 's2',
  s2t: 's2t',
  dio: Dio()..httpClientAdapter = adapter,
  baseUrl: 'https://example.invalid',
  cacheTtl: ttl ?? kPlayerHomeCacheTtl,
);

void main() {
  group('ProfileClient：批量资料 / 头像槽位', () {
    test('同一批 uin 连要两次只发一次（顺序无关 → 同一 key）', () async {
      final adapter = _StubAdapter({
        'getProfileBatch3': _batch3Body,
        'getPersonCenterHeadInfo': _headBody,
      });
      final client = _profile(adapter);

      final a = await client.getProfileBatch3(<int>[7, 9]);
      final b = await client.getProfileBatch3(<int>[9, 7]);
      expect(a.single.nickname, '甲');
      expect(b, hasLength(1));
      expect(adapter.act('getProfileBatch3'), hasLength(1));
    });

    test('并发同一批只发一次（单飞）', () async {
      final adapter = _StubAdapter({'getProfileBatch3': _batch3Body});
      final client = _profile(adapter);

      final results = await Future.wait(<Future<List<PlayerProfile>>>[
        client.getProfileBatch3(<int>[7]),
        client.getProfileBatch3(<int>[7]),
      ]);
      expect(results.first, hasLength(1));
      expect(adapter.act('getProfileBatch3'), hasLength(1));
    });

    test('头像槽位同一批只发一次；换一批再发', () async {
      final adapter = _StubAdapter({'getPersonCenterHeadInfo': _headBody});
      final client = _profile(adapter);

      await client.getPersonCenterHeadInfos(<int>[7]);
      await client.getPersonCenterHeadInfos(<int>[7]);
      expect(adapter.act('getPersonCenterHeadInfo'), hasLength(1));

      await client.getPersonCenterHeadInfos(<int>[8]);
      expect(adapter.act('getPersonCenterHeadInfo'), hasLength(2));
    });

    test('空结果（失败/无数据）不缓存，下次真的重试', () async {
      final adapter = _StubAdapter({'getProfileBatch3': '{"data":[]}'});
      final client = _profile(adapter);

      expect(await client.getProfileBatch3(<int>[7]), isEmpty);
      expect(await client.getProfileBatch3(<int>[7]), isEmpty);
      expect(adapter.act('getProfileBatch3'), hasLength(2));
    });

    test('cacheTtl 归零 → 每次都打（需要强制刷新时）', () async {
      final adapter = _StubAdapter({'getProfileBatch3': _batch3Body});
      final client = _profile(adapter, ttl: Duration.zero);

      await client.getProfileBatch3(<int>[7]);
      await client.getProfileBatch3(<int>[7]);
      expect(adapter.act('getProfileBatch3'), hasLength(2));
    });
  });

  group('PlayerHomeClient：主页 / 等级 / 冒险家等级', () {
    test('同一 uin 的主页连要两次只发一次（卡片与主页共享）', () async {
      final adapter = _StubAdapter({'get_user_homepage': _homeBody});
      final client = _home(adapter);

      final a = await client.getUserHomepage(7);
      final b = await client.getUserHomepage(7);
      expect(a, isNotEmpty);
      expect(b, a);
      expect(adapter.act('get_user_homepage'), hasLength(1));
    });

    test('module_list 不同 → 不同 key（不互相污染）', () async {
      final adapter = _StubAdapter({'get_user_homepage': _homeBody});
      final client = _home(adapter);

      await client.getUserHomepage(7, moduleList: 'a');
      await client.getUserHomepage(7, moduleList: 'b');
      expect(adapter.act('get_user_homepage'), hasLength(2));
    });

    test('同一批等级连要两次只发一次；不同 uin 分开', () async {
      final adapter = _StubAdapter({'get_level_info_batch': _levelBody});
      final client = _home(adapter);

      expect(await client.getPlatformLevels(<int>[7]), <int, int>{7: 12});
      await client.getPlatformLevels(<int>[7]);
      expect(adapter.act('get_level_info_batch'), hasLength(1));

      await client.getPlatformLevels(<int>[8]);
      expect(adapter.act('get_level_info_batch'), hasLength(2));
    });

    test('冒险家等级同上', () async {
      final adapter = _StubAdapter({'get_other_player_score': _scoreBody});
      final client = _home(adapter);

      expect(await client.getOtherPlayerScore(7), isNotNull);
      await client.getOtherPlayerScore(7);
      expect(adapter.act('get_other_player_score'), hasLength(1));
    });

    test('cacheTtl 归零 → 每次都打', () async {
      final adapter = _StubAdapter({'get_user_homepage': _homeBody});
      final client = _home(adapter, ttl: Duration.zero);

      await client.getUserHomepage(7);
      await client.getUserHomepage(7);
      expect(adapter.act('get_user_homepage'), hasLength(2));
    });
  });
}
