import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:mnchat/core/models/friend_tag.dart';

/// 好友标签解析：对齐 `newfriendservice.lua:597-634`
/// （文案 base64、`label_list` 规范化、`uin_list` 反查）。
void main() {
  String b64(String s) => base64Encode(utf8.encode(s));

  group('parseFriendTagPool', () {
    test('解 base64 文案并保留 uin_list', () {
      final tags = parseFriendTagPool({
        'result': 0,
        'label_list': [
          {
            'tag_id': 7,
            'label': b64('同学'),
            'uin_list': [1001, 1002],
          },
          {'tag_id': 9, 'label': b64('死党'), 'uin_list': <int>[]},
        ],
      });
      expect(tags.length, 2);
      expect(tags[0].tagId, 7);
      expect(tags[0].label, '同学');
      expect(tags[0].uins, [1001, 1002]);
      expect(tags[1].label, '死党');
      expect(tags[1].uins, isEmpty);
    });

    test('丢掉没有 tag_id / 文案为空的项', () {
      final tags = parseFriendTagPool({
        'label_list': [
          {'tag_id': 0, 'label': b64('无 id')},
          {'tag_id': 3, 'label': ''},
          {'tag_id': 4, 'label': b64('有效')},
        ],
      });
      expect(tags.map((t) => t.tagId), [4]);
    });

    test('文案不是 base64 时原样返回（游戏 pcall 兜底）', () {
      final tags = parseFriendTagPool({
        'label_list': [
          {'tag_id': 5, 'label': '中文原文'},
        ],
      });
      expect(tags.single.label, '中文原文');
    });

    test('响应形状不对时返回空表，不抛异常', () {
      expect(parseFriendTagPool(null), isEmpty);
      expect(parseFriendTagPool('oops'), isEmpty);
      expect(parseFriendTagPool({'result': 0}), isEmpty);
    });
  });

  group('friendTagIndex', () {
    test('反查 uin → 标签集合', () {
      const tags = [
        FriendTag(tagId: 1, label: '同学', uins: [1001, 1002]),
        FriendTag(tagId: 2, label: '死党', uins: [1002]),
      ];
      final idx = friendTagIndex(tags);
      expect(idx[1001], {1});
      expect(idx[1002], {1, 2});
      expect(idx[9999], isNull);
    });
  });

  test('encodeFriendLabel 与 decodeFriendLabel 往返一致', () {
    for (final s in ['a', '同学', '5字标签啦']) {
      expect(decodeFriendLabel(encodeFriendLabel(s)), s);
    }
  });
}
