import 'package:flutter_test/flutter_test.dart';
import 'package:mnchat/core/services/social_sign.dart';

/// 交友宣言标签：文案来自服务端 visual-cfg `FriendShipDeclaration`
/// （`NewFriendCfg:GetRelationConfig` → `VisualCfgMgr:ReqCfg`），
/// 客户端内置表只是兜底 —— 解析必须对齐 `NewFriendMgr:GetDeclaration`
/// 的 `v.id` / `v.tag` 读法。
void main() {
  const config = '''
{
  statusTag = {
    {
      id = 1,
      tag = '一起建房子',
    },
    {
      id = 2,
      tag = '一起打BOSS',
    },
    {
      id = 7,
      tag = '找个师傅',
    },
  },
  likeTag = {
    {
      id = 1,
      tag = '生存模式',
    },
    {
      id = 4,
      tag = '解密地图',
    },
  },
}''';

  group('parseDeclarationTags', () {
    test('按 id/tag 解析 statusTag / likeTag', () {
      final (status, like) = parseDeclarationTags(config);
      expect(status, {1: '一起建房子', 2: '一起打BOSS', 7: '找个师傅'});
      expect(like, {1: '生存模式', 4: '解密地图'});
    });

    test('缺少某一块时返回空表，不抛异常', () {
      final (status, like) = parseDeclarationTags('{ likeTag = { { id = 3, tag = "对战地图" } } }');
      expect(status, isEmpty);
      expect(like, {3: '对战地图'});
      expect(parseDeclarationTags(''), (const <int, String>{}, const <int, String>{}));
    });

    test('单双引号都能解析', () {
      final (_, like) = parseDeclarationTags(
        "{ likeTag = { { id = 2, tag = '单引号' }, { id = 3, tag = \"双引号\" } } }",
      );
      expect(like, {2: '单引号', 3: '双引号'});
    });
  });

  group('DeclarationCatalog', () {
    final catalog = DeclarationCatalog(
      socialTags: const {1: '一起建房子'},
      gameTags: const {4: '解密地图'},
    );

    test('有服务端配置时用配置文案', () {
      expect(formatDeclaration(1, 4, catalog: catalog), '想要一起建房子，喜欢解密地图');
      expect(catalog.socialText(1), '一起建房子');
      expect(catalog.gameText(4), '解密地图');
    });

    test('配置里没有的 id 回退内置表，不显示"标签#id"', () {
      // 内置表 id=1 是「一起建房子」；这里换一个 id 走内置表取值。
      final text = formatDeclaration(2, 0, catalog: catalog);
      expect(text, startsWith('想要'));
      expect(text, isNot(contains('标签#')));
    });

    test('空目录（拉不到配置）时用内置表，选项列表非空', () {
      const empty = DeclarationCatalog.empty;
      expect(empty.isEmpty, isTrue);
      expect(formatDeclaration(1, 1, catalog: empty).contains('标签#'), isFalse);
      expect(empty.socialOptions, isNotEmpty);
      expect(empty.gameOptions, isNotEmpty);
    });

    test('选项列表按 id 升序', () {
      expect(catalog.socialOptions, [(1, '一起建房子')]);
      final many = DeclarationCatalog(
        socialTags: const {7: '七', 2: '二', 5: '五'},
        gameTags: const {},
      );
      expect(many.socialOptions.map((e) => e.$1), [2, 5, 7]);
    });
  });
}
