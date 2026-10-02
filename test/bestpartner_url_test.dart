import 'dart:convert';
import 'dart:typed_data';

import 'package:crypto/crypto.dart' as crypto;
import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mnchat/core/crypto/s7_sign.dart' show kS7Alphabet;
import 'package:mnchat/core/services/partner.dart';
import 'package:mnchat/state/providers.dart'
    show myPartnerListProvider, partnerClientProvider;

/// 记录请求并回放固定响应的 Dio 适配器（离线、无网络）。
class _StubAdapter implements HttpClientAdapter {
  _StubAdapter(this.body) : _bodies = null;

  _StubAdapter.sequence(this._bodies) : body = null;

  final String? body;
  final List<String>? _bodies;
  final List<RequestOptions> requests = <RequestOptions>[];

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    final i = requests.length;
    requests.add(options);
    final text = _bodies == null
        ? body!
        : _bodies[i < _bodies.length ? i : _bodies.length - 1];
    return ResponseBody.fromString(
      text,
      200,
      headers: <String, List<String>>{
        Headers.contentTypeHeader: <String>['text/plain'],
      },
    );
  }

  @override
  void close({bool force = false}) {}
}

PartnerClient _client(
  _StubAdapter adapter, {
  int uin = 279630451,
  Duration listCacheTtl = const Duration(seconds: 5),
}) {
  final dio = Dio()..httpClientAdapter = adapter;
  return PartnerClient(
    uin: uin,
    s2: 'S2SECRET',
    s2t: '1790844333',
    dio: dio,
    baseUrl: 'https://shequ.mini1.cn:8081',
    retryBackoff: const <Duration>[Duration.zero, Duration.zero],
    listCacheTtl: listCacheTtl,
  );
}

const String _std = 'ABCDEFGHIJKLMNOPQRSTUVWXYZ'
    'abcdefghijklmnopqrstuvwxyz'
    '0123456789+/';

/// 游戏 `s7` 的逆变换：自定义字母表 → 标准 base64 → 原文。
String _decodeS7(String s7) {
  final std = StringBuffer();
  for (final ch in s7.split('')) {
    if (ch == '_') {
      std.write('=');
      continue;
    }
    final i = kS7Alphabet.indexOf(ch);
    std.write(i >= 0 ? _std[i] : ch);
  }
  return utf8.decode(base64.decode(std.toString()));
}

String _md5(String s) => crypto.md5.convert(utf8.encode(s)).toString();

void main() {
  group('bestpartnerUrl（游戏 ParamEncode + 全局参数 + s7）', () {
    const time = 1790844345;
    const uin = 279630451;
    const s2 = 'S2SECRET';
    const s2t = '1790844333';

    test('路径是双斜杠 + s7/s7t，payload 与游戏公式逐字一致', () {
      final url = bestpartnerUrl(
        base: 'https://shequ.mini1.cn:8081/',
        act: 'get_list',
        reqParams: const {},
        time: time,
        uin: uin,
        s2: s2,
        s2t: s2t,
        ver: '1.59.0',
      );

      expect(url, startsWith('https://shequ.mini1.cn:8081//miniw/bestpartner?s7='));
      final uri = Uri.parse(url);
      expect(uri.path, '//miniw/bestpartner');
      final s7 = uri.queryParameters['s7']!;
      expect(uri.queryParameters['s7t'], _md5('s7$s7').substring(6, 11));

      final extdata = base64Encode(utf8.encode(jsonEncode(const {})));
      final auth = _md5('${_md5('$time$s2$uin')}get_list$extdata'
          'ad0fd4743357398df92dc58e9c56937e');

      final payload = _decodeS7(s7);
      expect(
        payload,
        'extdata=$extdata&auth=$auth&act=get_list&time=$time&s2t=$s2t'
        '&uin=$uin&ver=1.59.0&apiid=110&lang=0&country=CN&s7e=1',
      );
    });

    test('base 不带尾斜杠也生成同一条双斜杠 URL', () {
      String build(String base) => bestpartnerUrl(
            base: base,
            act: 'get_list',
            reqParams: const {},
            time: time,
            uin: uin,
            s2: s2,
            s2t: s2t,
            ver: '1.59.0',
          );

      expect(
        build('https://shequ.mini1.cn:8081'),
        build('https://shequ.mini1.cn:8081/'),
      );
    });

    test('reqParams 进 extdata（otheruin 查他人）', () {
      final url = bestpartnerUrl(
        base: 'https://e.com/',
        act: 'get_list',
        reqParams: const {'otheruin': 153078116},
        time: time,
        uin: uin,
        s2: s2,
        s2t: s2t,
        ver: '1.59.0',
      );
      final payload =
          _decodeS7(Uri.parse(url).queryParameters['s7']!);
      expect(payload, contains('extdata=${base64Encode(utf8.encode('{"otheruin":153078116}'))}'));
    });
  });

  group('拍档类型（lab）与默契值区分', () {
    test('lab==0 是「只有默契值、未建立关系」，不能叫拍档', () {
      expect(PartnerLab.name(0), PartnerLab.noRelation);
      expect(PartnerLab.name(4), '兄弟');
      expect(PartnerLab.name(100), '最佳拍档');
      expect(PartnerLab.name(99), '拍档'); // 未知类型回退
      expect(PartnerLab.isPartnerLab(0), isFalse);
      expect(PartnerLab.isPartnerLab(4), isTrue);
    });

    test('PartnerDirectory：每个好友都有默契值，但只有 lab>0 才算拍档', () {
      final partners = PartnerInfo.parseList(const [
        {'bestUin': 1, 'lab': 0, 'tacitnum': 7},
        {'bestUin': 2, 'lab': 4, 'tacitnum': 1069},
      ]);
      final dir = PartnerDirectory(
        partners: {for (final p in partners) p.bestUin: p},
      );
      // 没建立关系的好友：有默契值、不是拍档
      expect(dir.tacitOf(1), 7);
      expect(dir.isPartner(1), isFalse);
      expect(partners.first.labName, PartnerLab.noRelation);
      // 已建立关系
      expect(dir.tacitOf(2), 1069);
      expect(dir.isPartner(2), isTrue);
      expect(partners.last.labName, '兄弟');
      // 不在列表里的好友 → 0 / 非拍档
      expect(dir.tacitOf(999), 0);
      expect(dir.isPartner(999), isFalse);
    });

    test('myPartnerListProvider 只保留已建立关系的拍档', () async {
      final adapter = _StubAdapter(
        '{["code"]=0,["data"]={'
        '[1]={["bestUin"]=1,["lab"]=0,["tacitnum"]=7},'
        '[2]={["bestUin"]=2,["lab"]=4,["tacitnum"]=1069}}}',
      );
      final container = ProviderContainer(
        overrides: [
          partnerClientProvider.overrideWithValue(_client(adapter)),
        ],
      );
      addTearDown(container.dispose);

      final list = await container.read(myPartnerListProvider.future);
      expect(list.map((p) => p.bestUin).toList(), <int>[2]);
    });
  });

  group('PartnerClient.getPartnerList', () {
    test('请求走 bestpartner 的 s7 URL，其它接口不受影响', () async {
      final adapter = _StubAdapter('{["code"]=0,["msg"]="",["data"]={}}');
      await _client(adapter).getPartnerList();

      final req = adapter.requests.single;
      expect(req.uri.path, '//miniw/bestpartner');
      final payload = _decodeS7(req.uri.queryParameters['s7']!);
      expect(payload, contains('act=get_list'));
      expect(payload, contains('uin=279630451'));
      expect(payload, contains('s2t=1790844333'));
      expect(payload.contains('otheruin'), isFalse);
    });

    test('otherUin 进 extdata', () async {
      final adapter = _StubAdapter('{["code"]=0,["msg"]="",["data"]={}}');
      await _client(adapter).getPartnerList(otherUin: 153078116);
      final payload =
          _decodeS7(adapter.requests.single.uri.queryParameters['s7']!);
      final ext = RegExp(r'extdata=([^&]+)').firstMatch(payload)!.group(1)!;
      expect(utf8.decode(base64.decode(ext)), '{"otheruin":153078116}');
    });

    test('真实响应形状 → 默契度/类型/结成时间都能解析（含非拍档 lab=0）', () async {
      // 线上抓取（2026-10-01，act=get_list）：
      // {code:0, data:[{bestUin,tacitnum,lab,createtime,daytacittotal,...}]}
      final adapter = _StubAdapter(
        '{["code"]=0,["msg"]="",["data"]={'
        '[1]={["lab"]=0,["createtime"]=0,["bestUin"]=328766693,["labindex"]=0,'
        '["daytacittotal"]=0,["giftdaytacittotal"]=0,["tacitnum"]=0},'
        '[2]={["lab"]=4,["createtime"]=1774764231,["bestUin"]=273640665,'
        '["labindex"]=1,["daytacittotal"]=12,["giftdaytacittotal"]=3,'
        '["tacitnum"]=1069}}}',
      );
      final list = await _client(adapter).getPartnerList();

      expect(list.length, 2);
      expect(list[0].bestUin, 328766693);
      expect(list[0].tacitnum, 0); // 非拍档也在列表里（lab == 0）
      expect(list[0].lab, 0);
      expect(list[1].bestUin, 273640665);
      expect(list[1].tacitnum, 1069);
      expect(list[1].lab, 4);
      expect(list[1].labName, '兄弟');
      expect(list[1].createtime, 1774764231);
      expect(list[1].dayTacitTotal, 12);
      expect(list[1].giftDayTacitTotal, 3);
    });

    test('无好友 / 服务端错误码 → 空列表且不抛', () async {
      for (final body in [
        '{["code"]=0,["msg"]="",["data"]={}}',
        '{["code"]=9,["msg"]=""}',
        '{["code"]=2,["msg"]=""}',
        'not a table',
      ]) {
        final adapter = _StubAdapter(body);
        expect(await _client(adapter).getPartnerList(), isEmpty);
      }
    });

    test('网关排队（code=9）会退避重试，命中后返回数据', () async {
      final adapter = _StubAdapter.sequence([
        '{["code"]=9,["msg"]=""}',
        '{["code"]=23,["msg"]=""}',
        '{["code"]=0,["data"]={[1]={["bestUin"]=273640665,["tacitnum"]=1}}}',
      ]);
      final list = await _client(adapter).getPartnerList();

      expect(adapter.requests.length, 3);
      expect(list.single.bestUin, 273640665);
      expect(list.single.tacitnum, 1);
    });

    test('连续不可恢复 → 重试到上限后返回空列表', () async {
      final adapter = _StubAdapter('{["code"]=9,["msg"]=""}');
      expect(await _client(adapter).getPartnerList(), isEmpty);
      expect(adapter.requests.length, 3); // 1 次 + 2 次退避重试
    });

    test('本人列表：连发两次只打一次网络（单飞 + 短缓存）', () async {
      final adapter = _StubAdapter(
        '{["code"]=0,["data"]={[1]={["bestUin"]=273640665,["tacitnum"]=1}}}',
      );
      final client = _client(adapter);
      final a = await client.getPartnerList();
      final b = await client.getPartnerList();

      expect(adapter.requests.length, 1);
      expect(a.single.bestUin, b.single.bestUin);

      // 并发调用也只打一次
      final client2 = _client(adapter);
      final results = await Future.wait([
        client2.getPartnerList(),
        client2.getPartnerList(),
      ]);
      expect(results.every((r) => r.single.tacitnum == 1), isTrue);
    });

    test('查他人不吃本人缓存', () async {
      final adapter = _StubAdapter(
        '{["code"]=0,["data"]={[1]={["bestUin"]=273640665,["tacitnum"]=1}}}',
      );
      final client = _client(adapter);
      await client.getPartnerList();
      await client.getPartnerList(otherUin: 153078116);
      await client.getPartnerList(otherUin: 153078116);
      expect(adapter.requests.length, 3);
    });

    test('缓存过期后重新拉取', () async {
      final adapter = _StubAdapter(
        '{["code"]=0,["data"]={[1]={["bestUin"]=273640665,["tacitnum"]=1}}}',
      );
      final client = _client(adapter, listCacheTtl: Duration.zero);
      await client.getPartnerList();
      await client.getPartnerList();
      expect(adapter.requests.length, 2);
    });
  });
}
