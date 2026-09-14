import 'package:flutter_test/flutter_test.dart';
import 'package:mnchat/core/services/name_rules.dart';

void main() {
  group('validateNickname', () {
    test('空昵称被拒绝', () {
      expect(validateNickname('   ', current: '旧名'), '昵称不能为空');
    });

    test('与当前昵称相同被拒绝', () {
      expect(validateNickname('小明', current: '小明'), '新昵称与当前昵称相同');
    });

    test('与当前昵称仅空白差异视为相同', () {
      expect(validateNickname('  小明 ', current: '小明'), '新昵称与当前昵称相同');
    });

    test('超长昵称被拒绝', () {
      final long = 'a' * (kNicknameMaxLen + 1);
      expect(validateNickname(long, current: '旧名'), isNotNull);
    });

    test('边界长度通过', () {
      final edge = 'a' * kNicknameMaxLen;
      expect(validateNickname(edge, current: '旧名'), isNull);
    });

    test('合法昵称通过', () {
      expect(validateNickname('新名字', current: '旧名'), isNull);
    });
  });

  group('extractRpcCode', () {
    test('形态 a：直接返回 code', () {
      expect(extractRpcCode(code: 7029, result: null), 7029);
    });

    test('形态 b：result 首元素为数字', () {
      expect(extractRpcCode(code: 0, result: <dynamic>[7009, 'x']), 7009);
    });

    test('形态 b：result 本身为数字', () {
      expect(extractRpcCode(code: 0, result: 0), 0);
    });

    test('result 为 map 的 code 字段', () {
      expect(
        extractRpcCode(code: 0, result: <String, Object?>{'code': 7018}),
        7018,
      );
    });

    test('result 为 map 的 ret 字段', () {
      expect(
        extractRpcCode(code: 0, result: <String, Object?>{'ret': 4065}),
        4065,
      );
    });

    test('无显式错误码视为成功', () {
      expect(extractRpcCode(code: 0, result: null), 0);
      expect(extractRpcCode(code: 0, result: 'ok'), 0);
    });
  });

  group('renameErrorText', () {
    test('成功返回空串', () {
      expect(renameErrorText(0), '');
    });

    test('已知错误码有中文提示', () {
      expect(renameErrorText(7009), contains('迷你币'));
      expect(renameErrorText(7029), contains('审核'));
      expect(renameErrorText(4065), contains('过长'));
      expect(renameErrorText(7018), contains('相同'));
      expect(renameErrorText(20), contains('连接'));
    });

    test('未知错误码带数值', () {
      expect(renameErrorText(9999), contains('9999'));
    });
  });
}
