/// MD5 signing helpers for Mini World API authentication.
/// 移植自 MNClient `crypto/sign.py` (11 种签名方案)。
library;

import 'dart:convert';

import 'package:crypto/crypto.dart' as crypto;

import 'encoding.dart' show luaUrlEncode;
import 'protocol_keys.dart';

// Re-export protocol keys for backward compatibility (services import from here).
export 'protocol_keys.dart'
    show loginAuthKey, roomAuthKey, chatpushAuthKey, httpGetParamKey;

/// Keys excluded from `http_getParamMD5` hash.
const Set<String> _paramMd5Exclude = {
  'content',
  'title',
  'nickname',
  'json',
  'test',
  'item_type_ids',
  'md5',
  'log',
  'content_ctx',
  'auth',
};

/// Keys whitelisted in `http_getParamMD5_roomServer` hash.
const Set<String> _roomServerKeys = {
  'country',
  'time',
  'is_empty_night',
  'game_label',
  'page_size',
  'page',
  'count',
  'cmd',
  's2t',
  'map_type',
  'uin',
  'lang',
};

String _md5(String body) => crypto.md5.convert(utf8.encode(body)).toString();

/// Concatenate [parts] as strings and return the MD5 hex digest.
String md5Sign(List<String> parts) => _md5(parts.join());

/// `md5(str(timeVal) + s2 + str(uin))` — room join tokens.
String md5Token(Object timeVal, String s2, Object uin) =>
    _md5('$timeVal$s2$uin');

/// `time=X&md5=MD5(time+s2+uin)&s2t=X` — http_getS1 (http.lua:557-569).
String httpGetS1(int timeVal, String s2, int uin, String s2t) {
  final hash = _md5('$timeVal$s2$uin');
  return 'time=$timeVal&md5=$hash&s2t=$s2t';
}

/// `time=X&auth=MD5(time+s2+uin)&s2t=X` — http_getS1Map (http.lua:579-591).
String httpGetS1Map(int timeVal, String s2, int uin, String s2t) {
  final hash = _md5('$timeVal$s2$uin');
  return 'time=$timeVal&auth=$hash&s2t=$s2t';
}

/// `time=X&auth=MD5(openid+"_wx_"+time)&open_id=Y` — WeChat variant.
String httpGetS1MapWx(Object openId, int timeVal) {
  final hash = _md5('${openId}_wx_$timeVal');
  return 'time=$timeVal&auth=$hash&open_id=$openId';
}

/// `&s2t=X&ts=Y&auth=MD5(s2+ts)` — http_getS2 (http.lua:571-577).
String httpGetS2(String s2, String s2t, int ts) {
  final hash = _md5('$s2$ts');
  return '&s2t=$s2t&ts=$ts&auth=$hash';
}

/// Compute `md5` query parameter for general API requests (http.lua:459-555).
String httpGetParamMd5(
  Map<String, String> params, {
  String key = httpGetParamKey,
  required int timeVal,
  required String s2,
  required String s2t,
  Map<String, String>? extraParams,
}) {
  final combined = <String, String>{...?extraParams};
  combined.addAll(params);

  combined['time'] = '$timeVal';
  combined['s2'] = luaUrlEncode(s2);
  combined['s2t'] = s2t;
  combined['encrypt_ver'] = '3';

  final keys =
      combined.keys.where((k) => !_paramMd5Exclude.contains(k)).toList()
        ..sort();
  final parts = keys.map((k) => '$k=${luaUrlEncode(combined[k]!)}').join('&');
  return _md5('$parts$key');
}

/// Compute md5 for room-server requests using a key whitelist (http.lua:393-457).
String httpGetParamMd5RoomServer(
  Map<String, String> params, {
  required int timeVal,
  required String s2t,
  Map<String, String>? extraParams,
}) {
  final combined = <String, String>{...?extraParams};
  combined.addAll(params);

  combined['time'] = '$timeVal';
  combined['s2t'] = s2t;
  combined['encrypt_ver'] = '2';

  final keys = combined.keys.where((k) => _roomServerKeys.contains(k)).toList()
    ..sort();
  final parts = keys.map((k) => '$k=${combined[k]!}').join('&');
  return _md5('$parts$roomAuthKey');
}

/// `time=X&auth=MD5(time+s2+uin+act)&s2t=Y` — http_getS2Act (http.lua:606-618).
String httpGetS2Act(String act, int timeVal, String s2, int uin, String s2t) {
  final hash = _md5('$timeVal$s2$uin$act');
  return 'time=$timeVal&auth=$hash&s2t=$s2t';
}

/// Per-act branching sign (http.lua:620-646).
String httpGetS1GuardMap(
  String act,
  int timeVal,
  String s2,
  int uin,
  String s2t, {
  String deviceId = '',
}) {
  if (act == 'ab_test_all') {
    final hash = _md5('$timeVal$s2$uin');
    return 'time=$timeVal&uin=$uin&auth=$hash&s2t=$s2t';
  }
  final inner = act == 'ab_test_device_all' ? act : 'ab_test_device_all';
  final innerMd5 = _md5('$deviceId$timeVal');
  final outerMd5 = _md5('$innerMd5$inner$deviceId');
  return 'time=$timeVal&device_id=$deviceId&auth=$outerMd5';
}

/// Compute `mmsum` and optional `cthash` query params (http.lua:649-687).
String httpGetRealNameMobileSum(
  String content, {
  required int uin,
  required String s2t,
  String mmsumData = '',
  required int nowVal,
}) {
  var ret = 'mmsum=nil';

  if (mmsumData.length >= 40) {
    final hashPart = mmsumData.substring(0, 32);
    final suffix = mmsumData.substring(32, 34);
    final tsStr = mmsumData.substring(34);

    if (tsStr.length >= 10) {
      final timestamp = int.tryParse(tsStr) ?? 0;
      final nowInterval = nowVal - timestamp;
      final serverMd5 = _md5('$hashPart$nowInterval').substring(6, 16);
      ret = 'mmsum=$nowInterval$suffix$serverMd5$timestamp';
    }
  }

  if (content.isNotEmpty) {
    final cthash = _md5('$uin$content$s2t').substring(6, 16);
    ret = '$ret&cthash=$cthash';
  }

  return ret;
}

/// `MD5(sortedParams + ROOM_AUTH_KEY)` — CreateFriendRequest.finish.
String createFriendRequestSign(String sortedParams) =>
    _md5('$sortedParams$roomAuthKey');

/// `http_get_s1` signing for group chat requests.
String createGroupChatRequestSign(
  int timeVal,
  String s2,
  int uin,
  String s2t,
) => httpGetS1(timeVal, s2, uin, s2t);
