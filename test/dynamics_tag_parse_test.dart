/// `DynamicsTag.parseList`（动态大厅分类列表，`act=get_posting_tag_list`）
/// 的解析口径回归：三种响应形态都要认，脏数据只跳过、绝不抛。
/// 另含正文话题引用 `topicRef`（`#{名称&o:id}`）的解析。
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:mnchat/core/models/nickname.dart' show topicRef;
import 'package:mnchat/core/services/dynamics.dart';

void main() {
  test('数组形态：[{tag_id,title}]', () {
    final tags = DynamicsTag.parseList([
      {'tag_id': 1, 'title': '推荐'},
      {'tag_id': 12, 'title': '作品评价'},
    ]);
    expect(tags.length, 2);
    expect(tags[0].tagId, 1);
    expect(tags[0].title, '推荐');
    expect(tags[1].tagId, 12);
    expect(tags[1].title, '作品评价');
  });

  test('包裹形态：{list:[...]} / {tag_list:[...]} / {data:[...]}', () {
    for (final key in ['list', 'tag_list', 'data']) {
      final tags = DynamicsTag.parseList({
        key: [
          {'tag_id': 3, 'title': '同城'},
        ],
      });
      expect(tags.length, 1, reason: key);
      expect(tags.single.tagId, 3);
    }
  });

  test('映射形态：{"<id>": {title: ...}} 用键兜底 id', () {
    final tags = DynamicsTag.parseList({
      '7': {'title': '游戏讨论'},
    });
    expect(tags.single.tagId, 7);
    expect(tags.single.title, '游戏讨论');
  });

  test('脏数据只跳过：非 Map 条目 / 无 id / 空载荷', () {
    expect(DynamicsTag.parseList(null), isEmpty);
    expect(DynamicsTag.parseList(<Object>[]), isEmpty);
    expect(DynamicsTag.parseList(['x', 3, {'title': '没有 id'}]), isEmpty);
    // id 冲突/重复不去重（服务端顺序即展示顺序），但不会抛。
    final tags = DynamicsTag.parseList([
      {'tag_id': 5},
      {'tag_id': 5, 'title': '重复'},
    ]);
    expect(tags.length, 2);
    expect(tags[0].title, '');
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
