// 聊天草稿：SettingsStore 的读写往返、会话隔离与脏数据降解。
//
// 用真实内存 Drift 库承载 SettingsStore（与 test/app_lock_test.dart 一致），
// 不 mock 存储层 —— 草稿是写进 settings 表的 JSON，往返本身就是要验证的东西。
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mnchat/core/storage/app_database.dart';
import 'package:mnchat/core/storage/settings_store.dart';

void main() {
  late AppDatabase db;
  late SettingsStore settings;

  setUp(() {
    db = AppDatabase(NativeDatabase.memory());
    settings = SettingsStore(db);
  });

  tearDown(() async {
    await db.close();
  });

  test('没写过草稿 → null', () async {
    expect(await settings.draft('friend_1'), isNull);
  });

  test('写入后读回，且按会话隔离', () async {
    await settings.setDraft('friend_1', '晚上一起跑图');
    await settings.setDraft('group_9', '收到');
    expect(await settings.draft('friend_1'), '晚上一起跑图');
    expect(await settings.draft('group_9'), '收到');
    expect(await settings.draft('friend_2'), isNull);
  });

  test('空白内容清空该会话草稿，其它会话不受影响', () async {
    await settings.setDraft('friend_1', '草稿');
    await settings.setDraft('group_9', '群草稿');
    await settings.setDraft('friend_1', '   ');
    expect(await settings.draft('friend_1'), isNull);
    expect(await settings.draft('group_9'), '群草稿');
  });

  test('草稿里的换行与首尾空格原样保留（用户敲的空格不该被吃掉）', () async {
    await settings.setDraft('friend_1', '  第一行\n第二行  ');
    expect(await settings.draft('friend_1'), '  第一行\n第二行  ');
  });

  test('库里是脏数据 → 当没有草稿，且不抛异常', () async {
    await settings.setString(SettingsKeys.drafts, '{不是 json');
    expect(await settings.draft('friend_1'), isNull);

    await settings.setString(SettingsKeys.drafts, '["数组","不是映射"]');
    expect(await settings.draft('friend_1'), isNull);

    // 脏数据之后再写一次，应当恢复正常（不能因为一次脏读就永久废掉草稿）
    await settings.setDraft('friend_1', '恢复');
    expect(await settings.draft('friend_1'), '恢复');
  });
}
