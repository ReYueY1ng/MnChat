/// 账号道具背包 —— `baseinfo.update` 响应里的持有道具数量。
///
/// 对齐反编译 `clientex/account.lua` 的 `ItemInfo` getter：账号持有量 =
/// `Account.BillDataSvr.ItemInfo` + `leveldb.ItemInfoNew` + `leveldb.ItemInfo`。
/// 响应里前者的形状是 **`[[道具ID, 数量], ...]` 对列表**（`BillDataSvr.ItemInfo`），
/// 后两者是 `[{ItemID, Num}, ...]`，所以两种形状都要认。
///
/// 这份数据就是游戏道具仓库（`storeitemstorage` 走
/// `AccountManager:getAccountData():getBagSize()/getAccountItem()`）与
/// 礼物面板「已拥有 N」的来源。2026-10-04 用游戏抓包对照实测：
/// 账号 279630451 的 `Account.BillDataSvr.ItemInfo` 有 116 项，含 `[43000, 18]`。
library;

/// 持有道具：道具 id → 数量 + 已拥有的角色皮肤。
class AccountInventory {
  final Map<int, int> counts;

  /// 已拥有的角色皮肤 id（`Account.BillDataSvr.RoleSkinInfo`）。
  ///
  /// 形状（`clientex/account.lua:1043-1085`）：`RoleSkinInfo` 是
  /// **`1..RoleSkinNum` 的数组**，每项 `{SkinID, ExpireTime}`；也兼容
  /// `{<SkinID>: {...}}` 映射。头像编辑的「装扮」页签用它列可选皮肤。
  final Set<int> ownedSkinIds;

  const AccountInventory(this.counts, {this.ownedSkinIds = const <int>{}});

  static const AccountInventory empty = AccountInventory(<int, int>{});

  bool get isEmpty => counts.isEmpty;

  /// 某道具持有数量（没有则 0）。
  int countOf(int itemId) => counts[itemId] ?? 0;

  /// 从 `baseinfo.update` 的 RPC 响应解析（宽松：拿不到就当空，绝不抛）。
  ///
  /// 响应形如 `[1, 'baseinfo', 'update', seq, ts, [code, body]]`；
  /// `code != 0`（例如漏发前置参数时的 4001）直接当空，避免把错误载荷当库存。
  static AccountInventory fromUpdateResponse(Object? response) {
    if (response is! List || response.length < 6) return empty;
    final result = response[5];
    if (result is! List || result.isEmpty) return empty;
    final code = result[0];
    if (code is! num || code.toInt() != 0) return empty;
    if (result.length < 2) return empty;

    final counts = <int, int>{};
    final seen = <Object>{};
    _walk(result[1], counts, seen);
    return AccountInventory(
      counts,
      ownedSkinIds: _collectSkins(result[1]),
    );
  }

  /// 从账号快照里收集 `RoleSkinInfo` 的皮肤 id。
  static Set<int> _collectSkins(Object? node) {
    final out = <int>{};
    void walk(Object? n) {
      if (n is Map) {
        for (final e in n.entries) {
          if ('${e.key}' == 'RoleSkinInfo') _absorbSkins(e.value, out);
          walk(e.value);
        }
      } else if (n is List) {
        for (final c in n) {
          walk(c);
        }
      }
    }

    walk(node);
    return out;
  }

  /// `[{SkinID, ExpireTime}, ...]` 与 `{<SkinID>: {...}}` 两种形状都吃。
  static void _absorbSkins(Object? value, Set<int> out) {
    if (value is List) {
      for (final e in value) {
        if (e is Map) {
          final id = _toInt(e['SkinID'] ?? e['skin_id'] ?? e['id']);
          if (id > 0) out.add(id);
        } else {
          final id = _toInt(e);
          if (id > 0) out.add(id);
        }
      }
    } else if (value is Map) {
      for (final k in value.keys) {
        final id = _toInt(k);
        if (id > 0) out.add(id);
      }
    }
  }

  static void _walk(Object? node, Map<int, int> out, Set<Object> seen) {
    if (node is Map) {
      for (final entry in node.entries) {
        final key = '${entry.key}';
        if (key == 'ItemInfo' || key == 'ItemInfoNew') {
          _absorb(entry.value, out, seen);
        }
        _walk(entry.value, out, seen);
      }
    } else if (node is List) {
      for (final child in node) {
        _walk(child, out, seen);
      }
    }
  }

  /// `[[id, num], ...]` 与 `[{ItemID, Num}, ...]` 两种形状都吃。
  ///
  /// `seen` 按**列表对象身份**去重：同一个 store 在响应里出现两次时不能把数量翻倍
  /// （不同 store 之间才是相加关系，和游戏 `item_num` 的算法一致）。
  static void _absorb(Object? value, Map<int, int> out, Set<Object> seen) {
    if (value is! List || seen.contains(value)) return;
    seen.add(value);
    for (final entry in value) {
      int id;
      int num;
      if (entry is Map) {
        id = _toInt(entry['ItemID'] ?? entry['id']);
        num = _toInt(entry['Num'] ?? entry['num']);
      } else if (entry is List && entry.length >= 2) {
        id = _toInt(entry[0]);
        num = _toInt(entry[1]);
      } else {
        continue;
      }
      if (id > 0 && num > 0) out[id] = (out[id] ?? 0) + num;
    }
  }

  static int _toInt(Object? v) =>
      v is num ? v.toInt() : (int.tryParse('$v') ?? 0);
}
