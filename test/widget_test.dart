import 'package:flutter_test/flutter_test.dart';
import 'package:mnchat/core/models/messages.dart';
import 'package:mnchat/core/protocol/lua_table.dart';

void main() {
  test('decodeLuaTable basic', () {
    final r = decodeHttpResponse('{["ret"]=0,["name"]="x"}') as Map;
    expect(r['ret'], 0);
    expect(r['name'], 'x');
  });

  test('ChatMessage from chat_query triple', () {
    final m = ChatMessage.fromChatQueryTriple([10001, 1700000000, 'hello']);
    expect(m.uin, 10001);
    expect(m.text, 'hello');
    expect(m.time, 1700000000);
  });

  test('ChatMessage from group notify (ms -> sec)', () {
    final m = ChatMessage.fromGroupNotify(
      {'uin': 10002, 'text': 'hi', 'send_time': 1700000000000},
      groupId: 55,
    );
    expect(m.uin, 10002);
    expect(m.text, 'hi');
    expect(m.time, 1700000000); // ms converted to sec
    expect(m.groupId, 55);
  });
}