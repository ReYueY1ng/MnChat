import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:mnchat/core/crypto/encoding.dart' show lenientBase64Decode;
import 'package:mnchat/core/services/rich_media.dart' show RichMedia;

/// 游戏侧 `extend_data` 是 `url_encode(base64(JSON))`，而且把 base64 的 `=`
/// 补位写成 `_`。尾部 `_` 若被当成 `/`，会多出**恰好一个合法 UTF-8 字节**，
/// 于是错误候选被选中、`jsonDecode` 因尾部多余内容失败 —— 礼物卡退化成
/// 「收到来自「X」的默契礼物」兜底文案。这里锁死这条真实报文。
void main() {
  // 游戏端 → MNChat 真机收到的礼物 extend_data（尾部单个 `_` = 一个 `=` 补位）。
  const giftExt =
      'eyJUeXBlIjoiU2VuZEZyaWVuZEdpZnQiLCJhZGRWYWx1ZSI6MSwiZGVzX3VpbiI6Mjc5NjMwNDUxLCJpdGVtaWQiOjQzMDAwLCJudW0iOjEsInNyY19uYW1lIjoiTW9vblJlbG9hZGVkIiwic3JjX3VpbiI6MjczNjQwNjY1LCJ0b2tlbiI6IjY3ZWE4YTlmODI3MzFiODMzMjM1MjYxODBkNjM3YzE1In0_';

  test('尾部单个 `_` 是补位（不是 `/`），解码后 JSON 无多余字节', () {
    final bytes = lenientBase64Decode(giftExt);
    expect(bytes, isNotNull);
    final text = utf8.decode(bytes!);
    // 关键：正文以 `}` 结尾，不能多出 `?`(0x3F)
    expect(text.endsWith('}'), isTrue);
    expect(jsonDecode(text), isA<Map<String, Object?>>());
  });

  test('礼物 extend_data → RichMedia 识别为 SendFriendGift（走卡片）', () {
    final media = RichMedia.decode(giftExt);
    expect(media, isNotNull);
    expect(media!.isFriendGift, isTrue);
    expect(media.giftItemId, 43000);
    expect(media.giftSrcName, 'MoonReloaded');
  });

  test('尾部 `__` 是两个补位（`==`）', () {
    // json `{"shareType":0}` 的标准 base64 补 `==`，被写成 `__`
    final std = base64Encode(utf8.encode('{"shareType":0}'));
    final variant = std.replaceAll('=', '_');
    expect(utf8.decode(lenientBase64Decode(variant)!), '{"shareType":0}');
  });

  test('常规无尾垫的 base64 仍可解', () {
    final std = base64Encode(utf8.encode('hello world'));
    expect(utf8.decode(lenientBase64Decode(std)!), 'hello world');
  });
}
