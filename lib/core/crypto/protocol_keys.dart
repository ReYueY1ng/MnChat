/// 协议密钥集中定义 —— 逆向自迷你世界官方客户端。
///
/// 所有密钥值逐字符保持原样，仅集中管理。
/// 来源：MNClient `crypto/sign.py`、`crypto/xxtea.py`、`crypto/chatpush.py`。
library;

import 'dart:typed_data';

/// 登录消息签名密钥（原 md5_sign.dart）。
const String loginAuthKey = '2ddb7619717147439c83ab022e9d4d38';

/// 房间/好友操作签名密钥（原 md5_sign.dart）。
const String roomAuthKey = 'f5711eb1640712de051e5aedc35329c3';

/// ChatPush 分配密钥（原 md5_sign.dart）。
const String chatpushAuthKey = '#Chat@Push.99#';

/// http_getParamMD5 通用 API 请求密钥（原 md5_sign.dart）。
const String httpGetParamKey = '3dbc5f33add11d1af78ba2af365e0952';

/// XXTEA 16 字节密钥（原 xxtea.dart）。
/// hex: b48e6ef44ed13eee606141750e729cf4
final Uint8List xxteaKey = Uint8List.fromList([
  0xb4,
  0x8e,
  0x6e,
  0xf4,
  0x4e,
  0xd1,
  0x3e,
  0xee,
  0x60,
  0x61,
  0x41,
  0x75,
  0x0e,
  0x72,
  0x9c,
  0xf4,
]);

/// ChatPush rotate-XOR 循环密钥（原 chatpush_cipher.dart）。
const List<int> chatpushXorKey = [18, 35, 52, 69];
