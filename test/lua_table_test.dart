import 'package:flutter_test/flutter_test.dart';
import 'package:mnchat/core/protocol/lua_table.dart';

void main() {
  group('Lua 长括号字符串 [[...]]', () {
    test('作为值：[[中文]]（emoji_system 配置的真实写法）', () {
      final r = decodeLuaTable('{ Access = [[花小楼换装舞会活动获得]], GetType = "4" }')
          as Map;
      expect(r['Access'], '花小楼换装舞会活动获得');
      expect(r['GetType'], '4');
    });

    test('内容里的花括号/引号不干扰解析', () {
      final r = decodeLuaTable('{ a = [[x { y } "z" ]], b = 1 }') as Map;
      expect(r['a'], 'x { y } "z" ');
      expect(r['b'], 1);
    });

    test('带等号的长括号 [=[...]=]（内含 ]] 也不提前结束）', () {
      final r = decodeLuaTable('{ a = [=[has ]] inside]=], b = 2 }') as Map;
      expect(r['a'], 'has ]] inside');
      expect(r['b'], 2);
    });

    test('作为数组元素：{ [[a]], [[b]] }', () {
      final r = decodeLuaTable('{ [[a]], [[b]] }');
      expect(r, ['a', 'b']);
    });

    test('未闭合的长括号报错（而不是静默吞掉）', () {
      expect(() => decodeLuaTable('{ a = [[oops }'), throwsA(isA<LuaTableDecodeError>()));
    });
  });

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