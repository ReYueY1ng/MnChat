/// 应用锁服务 —— PIN 的设置、校验与清除。
///
/// 存储方案：`Random.secure()` 生成 16 字节随机盐，十六进制后存入
/// [SettingsKeys.lockPinSalt]；`sha256(盐 + PIN)` 的十六进制摘要存入
/// [SettingsKeys.lockPinHash]。只存盐与摘要，不存明文 PIN。
///
/// 与 [credential_cipher] 一致的定位：防止"数据库文件被读取/备份时 PIN
/// 直接可见"，而非防 root/调试器的银行级安全。
library;

import 'dart:convert';
import 'dart:math';

import 'package:crypto/crypto.dart';

import '../storage/settings_store.dart';

/// 应用锁服务：以 [SettingsStore] 为底层存储。
class AppLockService {
  AppLockService(this._settings);

  final SettingsStore _settings;

  /// PIN 允许的最短位数。
  static const int minPinLength = 4;

  /// PIN 允许的最长位数。
  static const int maxPinLength = 8;

  /// 是否已设置 PIN（存在非空摘要即视为已设置）。
  Future<bool> isPinSet() async {
    final hash = await _settings.getString(SettingsKeys.lockPinHash);
    return hash != null && hash.isNotEmpty;
  }

  /// 设置 PIN：生成随机盐并存储 `sha256(盐 + PIN)` 摘要。
  ///
  /// PIN 必须为 4–8 位纯数字，否则抛 [ArgumentError]。
  Future<void> setPin(String pin) async {
    if (!_isValidPin(pin)) {
      throw ArgumentError.value(pin, 'pin', 'PIN 必须为 4–8 位数字');
    }
    final salt = _randomSaltHex();
    final hash = _hash(salt, pin);
    await _settings.setString(SettingsKeys.lockPinSalt, salt);
    await _settings.setString(SettingsKeys.lockPinHash, hash);
  }

  /// 校验 PIN；未设置或输入非法返回 false。
  Future<bool> verifyPin(String pin) async {
    if (!_isValidPin(pin)) return false;
    final salt = await _settings.getString(SettingsKeys.lockPinSalt);
    final hash = await _settings.getString(SettingsKeys.lockPinHash);
    if (salt == null || salt.isEmpty || hash == null || hash.isEmpty) {
      return false;
    }
    return _constEq(hash, _hash(salt, pin));
  }

  /// 清除已设置的 PIN（同时清空盐与摘要）。
  Future<void> clearPin() async {
    await _settings.setString(SettingsKeys.lockPinSalt, '');
    await _settings.setString(SettingsKeys.lockPinHash, '');
  }

  /// PIN 是否满足 4–8 位纯数字规则。
  bool _isValidPin(String pin) =>
      pin.length >= minPinLength &&
      pin.length <= maxPinLength &&
      RegExp(r'^\d+$').hasMatch(pin);

  /// 计算 `sha256(盐 + PIN)` 的十六进制摘要。
  String _hash(String salt, String pin) =>
      sha256.convert(utf8.encode('$salt$pin')).toString();

  /// 生成 16 字节随机盐（`Random.secure()`），返回 32 位十六进制字符串。
  String _randomSaltHex() {
    final rng = Random.secure();
    final bytes = List<int>.generate(16, (_) => rng.nextInt(256));
    final buf = StringBuffer();
    for (final b in bytes) {
      buf.write(b.toRadixString(16).padLeft(2, '0'));
    }
    return buf.toString();
  }

  /// 常数时间比较十六进制摘要，防时序侧信道。
  bool _constEq(String a, String b) {
    if (a.length != b.length) return false;
    var diff = 0;
    for (var i = 0; i < a.length; i++) {
      diff |= a.codeUnitAt(i) ^ b.codeUnitAt(i);
    }
    return diff == 0;
  }
}
