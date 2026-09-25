/// 应用锁服务 —— PIN 的设置、校验与清除。
///
/// 存储方案：
///   - **v2（当前）**：`Random.secure()` 生成 16 字节随机盐，用
///     PBKDF2-HMAC-SHA256 派生 256 位摘要，写入
///     `v2$<iterations>$<saltBase64>$<hashBase64>`（见 [SettingsKeys.lockPinHash]），
///     盐的 base64 同时写入 [SettingsKeys.lockPinSalt] 便于旧接口读取。
///   - **legacy**：历史数据为 `sha256(utf8(盐 + PIN))` 的十六进制摘要，盐存
///     [SettingsKeys.lockPinSalt]。成功校验后透明升级为 v2，用户无感。
///
/// PIN 是 6–8 位小数空间，PBKDF2 只能抬高单次离线枚举成本；真正防在线
/// 爆破的是 [verifyPin] 内的失败节流（见 [maxAttempts] / [lockBase]）。
///
/// 与 [credential_cipher] 一致的定位：防止"数据库文件被读取/备份时 PIN
/// 直接可见"，而非防 root/调试器的银行级安全。
library;

import 'dart:convert';
import 'dart:math';

import 'package:crypto/crypto.dart' show sha256;
import 'package:cryptography/cryptography.dart' show Hmac, Pbkdf2, SecretKey;

import '../storage/settings_store.dart';

/// 应用锁服务：以 [SettingsStore] 为底层存储。
class AppLockService {
  AppLockService(this._settings, {DateTime Function()? now, int? iterations})
    : _now = now ?? DateTime.now,
      _iterations = iterations ?? pbkdf2Iterations;

  final SettingsStore _settings;

  /// 可注入时钟，便于节流逻辑的确定性测试；默认 [DateTime.now]。
  final DateTime Function() _now;

  /// 实际使用的 PBKDF2 迭代次数。生产环境恒为 [pbkdf2Iterations]；
  /// 该参数仅为单测注入低工作因子以避免纯 Dart 派生拖慢测试。
  final int _iterations;

  /// 设置新 PIN 时的最短位数（v2 起由 4 提升到 6）。
  static const int minPinLength = 6;

  /// 校验时接受的历史最短位数：4–5 位旧 PIN 仍须能解锁，不锁死存量用户。
  static const int legacyMinPinLength = 4;

  /// PIN 允许的最长位数。
  static const int maxPinLength = 8;

  /// PBKDF2 迭代次数：10 万次在纯 Dart 下单次约百毫秒，远高于单轮
  /// sha256 的离线爆破成本，同时保证解锁与单测延迟可接受。
  static const int pbkdf2Iterations = 100000;

  /// 随机盐字节数。
  static const int _saltBytes = 16;

  /// v2 版本前缀；旧版裸十六进制摘要不含此前缀。
  static const String _v2Prefix = 'v2\$';

  /// 连续失败达到该次数后开始锁定。
  static const int maxAttempts = 5;

  /// 首次锁定时长；之后每次失败翻倍，封顶 [lockCap]。
  static const Duration lockBase = Duration(seconds: 30);

  /// 锁定窗口上限。
  static const Duration lockCap = Duration(minutes: 15);

  /// 是否已设置 PIN（存在非空摘要即视为已设置）。
  Future<bool> isPinSet() async {
    final hash = await _settings.getString(SettingsKeys.lockPinHash);
    return hash != null && hash.isNotEmpty;
  }

  /// 设置 PIN：生成随机盐并用 PBKDF2 派生摘要存储；同时重置节流状态。
  ///
  /// PIN 必须为 [minPinLength]–[maxPinLength] 位纯数字，否则抛 [ArgumentError]。
  Future<void> setPin(String pin) async {
    if (!_isValidNewPin(pin)) {
      throw ArgumentError.value(
        pin,
        'pin',
        'PIN 必须为 $minPinLength–$maxPinLength 位数字',
      );
    }
    await _storePbkdf2(pin);
    await _resetThrottle();
  }

  /// 校验 PIN；未设置、格式非法、被锁定或摘要不符均返回 false。
  Future<bool> verifyPin(String pin) async {
    final stored = await _settings.getString(SettingsKeys.lockPinHash);
    if (stored == null || stored.isEmpty) return false;
    if (!_isValidVerifyPin(pin)) return false;
    // 锁定期间立即失败，不计算哈希（避免被用来压榨 CPU/探测）。
    if (await _isLocked()) return false;

    if (await _matches(pin, stored)) {
      await _resetThrottle();
      return true;
    }
    await _recordFailure();
    return false;
  }

  /// 清除已设置的 PIN（清空盐/摘要）并重置节流状态。
  Future<void> clearPin() async {
    await _settings.setString(SettingsKeys.lockPinSalt, '');
    await _settings.setString(SettingsKeys.lockPinHash, '');
    await _resetThrottle();
  }

  /// 按存储格式分发校验；legacy 成功时透明升级为 v2。
  Future<bool> _matches(String pin, String stored) async {
    if (stored.startsWith(_v2Prefix)) return _verifyPbkdf2(pin, stored);
    return _verifyLegacyAndUpgrade(pin, stored);
  }

  /// v2 校验：格式为 `v2$<iterations>$<saltBase64>$<hashBase64>`。
  ///
  /// 任何解析异常都安全地视为不匹配（返回 false，绝不抛出）。
  Future<bool> _verifyPbkdf2(String pin, String stored) async {
    try {
      final parts = stored.split(r'$');
      if (parts.length != 4 || parts[0] != 'v2') return false;
      final iterations = int.tryParse(parts[1]);
      if (iterations == null || iterations <= 0) return false;
      final salt = base64Decode(parts[2]);
      final derived = await _derive(pin, salt, iterations);
      return _constEq(parts[3], base64Encode(derived));
    } catch (_) {
      return false;
    }
  }

  /// legacy 校验：`sha256(utf8(盐 + PIN))` 十六进制比对。
  ///
  /// 命中后用 PBKDF2 重算并持久化，实现静默升级（不需要用户重新输入）。
  Future<bool> _verifyLegacyAndUpgrade(String pin, String legacyHash) async {
    final salt = await _settings.getString(SettingsKeys.lockPinSalt);
    if (salt == null || salt.isEmpty) return false;
    final digest = sha256.convert(utf8.encode('$salt$pin')).toString();
    if (!_constEq(legacyHash, digest)) return false;
    await _storePbkdf2(pin);
    return true;
  }

  /// 用新随机盐与 PBKDF2 重写 PIN 的盐/摘要（v2 格式）。
  Future<void> _storePbkdf2(String pin) async {
    final salt = _randomSaltBytes();
    final derived = await _derive(pin, salt, _iterations);
    final stored =
        '$_v2Prefix$_iterations\$${base64Encode(salt)}\$${base64Encode(derived)}';
    await _settings.setString(SettingsKeys.lockPinSalt, base64Encode(salt));
    await _settings.setString(SettingsKeys.lockPinHash, stored);
  }

  /// PBKDF2-HMAC-SHA256 派生 256 位密钥。
  Future<List<int>> _derive(String pin, List<int> salt, int iterations) async {
    final pbkdf2 = Pbkdf2(
      macAlgorithm: Hmac.sha256(),
      iterations: iterations,
      bits: 256,
    );
    final key = await pbkdf2.deriveKey(
      secretKey: SecretKey(utf8.encode(pin)),
      nonce: salt,
    );
    return key.extractBytes();
  }

  /// 设置阶段：必须为 6–8 位纯数字。
  bool _isValidNewPin(String pin) =>
      pin.length >= minPinLength &&
      pin.length <= maxPinLength &&
      _isDigits(pin);

  /// 校验阶段：接受 4–8 位纯数字（兼容历史 4–5 位 PIN）。
  bool _isValidVerifyPin(String pin) =>
      pin.length >= legacyMinPinLength &&
      pin.length <= maxPinLength &&
      _isDigits(pin);

  bool _isDigits(String pin) => RegExp(r'^\d+$').hasMatch(pin);

  /// 生成 16 字节随机盐（`Random.secure()`）。
  List<int> _randomSaltBytes() {
    final rng = Random.secure();
    return List<int>.generate(_saltBytes, (_) => rng.nextInt(256));
  }

  /// 常数时间比较摘要字符串，防时序侧信道。
  bool _constEq(String a, String b) {
    if (a.length != b.length) return false;
    var diff = 0;
    for (var i = 0; i < a.length; i++) {
      diff |= a.codeUnitAt(i) ^ b.codeUnitAt(i);
    }
    return diff == 0;
  }

  // ── 失败节流 ────────────────────────────────────────────────────────

  /// 当前是否处于锁定窗口内。
  Future<bool> _isLocked() async {
    final until = await _settings.getInt(SettingsKeys.lockLockedUntil) ?? 0;
    return _now().millisecondsSinceEpoch < until;
  }

  /// 记录一次失败；达到阈值后按失败次数设置指数增长的锁定窗口。
  Future<void> _recordFailure() async {
    final attempts =
        (await _settings.getInt(SettingsKeys.lockAttempts) ?? 0) + 1;
    await _settings.setInt(SettingsKeys.lockAttempts, attempts);
    if (attempts >= maxAttempts) {
      await _settings.setInt(
        SettingsKeys.lockLockedUntil,
        _now().add(_lockWindow(attempts)).millisecondsSinceEpoch,
      );
    }
  }

  /// 第 [maxAttempts] 次失败锁定 [lockBase]；此后每次翻倍，封顶 [lockCap]。
  Duration _lockWindow(int attempts) {
    var seconds = lockBase.inSeconds;
    for (var i = maxAttempts; i < attempts; i++) {
      seconds *= 2;
      if (seconds >= lockCap.inSeconds) return lockCap;
    }
    return Duration(seconds: seconds);
  }

  /// 成功校验/设置/清除后归零节流状态。
  Future<void> _resetThrottle() async {
    await _settings.setInt(SettingsKeys.lockAttempts, 0);
    await _settings.setInt(SettingsKeys.lockLockedUntil, 0);
  }
}
