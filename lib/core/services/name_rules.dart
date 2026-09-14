/// 昵称规则与改名错误码映射。
///
/// 对齐反编译源码：
/// - `nickModifyCtrl` 输入框上限 21 字符；
/// - `accountcs.lua` rename 预检：必须为字符串、与当前昵称不同、
///   长度 < NAME_LEN、审核中(rename_review==3)拒绝、迷你币/改名卡校验。
library;

/// 昵称最大字符数（对齐 nickModifyCtrl.nicklength = 21）。
const int kNicknameMaxLen = 21;

/// 校验新昵称。合法返回 null，否则返回可直接展示的中文错误提示。
String? validateNickname(String input, {required String current}) {
  final name = input.trim();
  if (name.isEmpty) return '昵称不能为空';
  if (name == current.trim()) return '新昵称与当前昵称相同';
  // 按 Unicode 码点计数（近似反编译对多字节字符的 #str 长度判定）
  if (name.runes.length > kNicknameMaxLen) {
    return '昵称最多 $kNicknameMaxLen 个字符';
  }
  return null;
}

/// 从 chatpush RPC 响应提取业务返回码（兼容两种响应形态）：
/// a) `[1, seq, code, result, ...]` → code 在 index 2，直接使用；
/// b) `[1, svc, method, seq, ts, result, ...]` → 无独立 code，业务码在 result。
int extractRpcCode({required int code, Object? result}) {
  if (code != 0) return code;
  if (result is num) return result.toInt();
  if (result is List && result.isNotEmpty && result.first is num) {
    return (result.first as num).toInt();
  }
  if (result is Map) {
    for (final k in ['code', 'ret', 'result']) {
      final v = result[k];
      if (v is num) return v.toInt();
    }
  }
  return 0; // 无显式错误码 → 视为成功
}

/// 改名返回码 → 中文提示（`0` 成功返回空串）。
///
/// 错误码取自反编译 `errorcode.lua`：4001 类型错误 / 4065 昵称过长 /
/// 7009 迷你币不足 / 7012 密码错误 / 7018 无需修改 / 7029 审核中。
String renameErrorText(int code) {
  switch (code) {
    case 0:
      return '';
    case 20:
      return '尚未连接服务器，请稍后重试';
    case 4001:
      return '昵称包含非法字符';
    case 4065:
      return '昵称过长';
    case 7009:
      return '迷你币不足，无法改为付费昵称';
    case 7012:
      return '账号校验失败，请重新登录';
    case 7018:
      return '新昵称与当前昵称相同';
    case 7029:
      return '昵称正在审核中，暂时无法改名';
    default:
      return '改名失败（错误码 $code）';
  }
}
