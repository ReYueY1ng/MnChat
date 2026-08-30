import 'package:flutter_test/flutter_test.dart';
import 'package:mnchat/core/protocol/lua_table.dart';

void main() {
  group('decodeHttpResponse', () {
    test('strict JSON passes through', () {
      final r = decodeHttpResponse('{"code":0,"msg":"ok"}') as Map;

      expect(r['code'], 0);
      expect(r['msg'], 'ok');
    });

    test('Lua table literal with ["key"]=', () {
      final text = '{["ret"]=0,["profile"]={["RoleInfo"]={["NickName"]="x"}}}';
      final r = decodeHttpResponse(text) as Map;

      expect(r['ret'], 0);
      final profile = r['profile'] as Map;
      final role = profile['RoleInfo'] as Map;
      expect(role['NickName'], 'x');
    });

    test('Lua table bare keys', () {
      final text = '{ret=0, name="abc", flag=true, none=nil}';
      final r = decodeHttpResponse(text) as Map;

      expect(r['ret'], 0);
      expect(r['name'], 'abc');
      expect(r['flag'], true);
      expect(r['none'], null);
    });

    test('implicit-index array becomes list', () {
      final text = '{1,2,3}';
      final r = decodeHttpResponse(text);

      expect(r, [1, 2, 3]);
    });

    test('explicit dense numeric keys become list', () {
      final text = '{[1]="a",[2]="b",[3]="c"}';
      final r = decodeHttpResponse(text);

      expect(r, ['a', 'b', 'c']);
    });

    test('empty body -> empty map', () {
      final r = decodeHttpResponse('   ');

      expect(r, <String, Object?>{});
    });
  });
}