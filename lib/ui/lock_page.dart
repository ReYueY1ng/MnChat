import 'dart:math' as math;

import 'package:material_ui/material_ui.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/services/app_lock.dart';
import '../state/providers.dart';

/// 应用锁解锁页：全屏居中，无 AppBar/返回键。
///
/// 使用自绘数字键盘（不依赖系统输入法），可同时用于桌面与移动端。
/// 输入位数达到最小长度后即可自动校验；正确则回调 [onUnlocked]，
/// 错误则震动提示"密码错误"并清空输入。
class LockPage extends ConsumerStatefulWidget {
  const LockPage({super.key, required this.onUnlocked});

  /// 校验通过后的回调（由外部负责跳转/解锁）。
  final VoidCallback onUnlocked;

  @override
  ConsumerState<LockPage> createState() => _LockPageState();
}

class _LockPageState extends ConsumerState<LockPage>
    with SingleTickerProviderStateMixin {
  late final AppLockService _service;
  late final AnimationController _shake;

  String _pin = '';
  String? _error;
  bool _verifying = false;

  @override
  void initState() {
    super.initState();
    _service = AppLockService(ref.read(settingsProvider));
    _shake = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 400),
    );
  }

  @override
  void dispose() {
    _shake.dispose();
    super.dispose();
  }

  /// 点击数字键。
  void _onDigit(String digit) {
    // 不因 _verifying 丢弃按键：校验在后台 isolate 中进行，期间到达的数字
    // 需累积，否则用户在 600ms 校验窗口内快速输完最后几位会丢键。
    if (_pin.length >= AppLockService.maxPinLength) return;
    setState(() {
      _pin += digit;
      _error = null;
    });
    if (_pin.length >= AppLockService.minPinLength) {
      _submit(isConfirm: false);
    }
  }

  /// 删除最后一位。
  void _onDelete() {
    if (_verifying || _pin.isEmpty) return;
    setState(() {
      _pin = _pin.substring(0, _pin.length - 1);
      _error = null;
    });
  }

  /// 校验当前输入。
  ///
  /// [isConfirm] 为 true（确认键）或输入已达最大长度时，失败即报错清空；
  /// 否则静默失败，等待用户继续输入更长的 PIN。
  Future<void> _submit({required bool isConfirm}) async {
    if (_verifying || _pin.isEmpty) return;
    final attempt = _pin;
    setState(() {
      _verifying = true;
      _error = null;
    });
    final ok = await _service.verifyPin(attempt);
    if (!mounted) return;
    if (ok) {
      setState(() => _verifying = false);
      widget.onUnlocked();
      return;
    }
    // 校验期间有新输入 → 用最新输入重试（不再限制长度：最后一位也可能在校验中补上）
    if (!isConfirm && _pin != attempt) {
      setState(() => _verifying = false);
      await _submit(isConfirm: false);
      return;
    }
    setState(() {
      _verifying = false;
      if (isConfirm || _pin.length >= AppLockService.maxPinLength) {
        _error = '密码错误';
        _pin = '';
        _shake.forward(from: 0);
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    return Scaffold(
      backgroundColor: scheme.surface,
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(24),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 360),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.lock_outline, size: 48, color: scheme.primary),
                  const SizedBox(height: 12),
                  Text('MnChat', style: theme.textTheme.headlineSmall),
                  const SizedBox(height: 4),
                  Text(
                    '请输入应用锁密码',
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: scheme.outline,
                    ),
                  ),
                  const SizedBox(height: 28),
                  _buildDots(scheme),
                  const SizedBox(height: 12),
                  SizedBox(
                    height: 20,
                    child: _error == null
                        ? null
                        : Text(
                            _error!,
                            style: theme.textTheme.bodyMedium?.copyWith(
                              color: scheme.error,
                            ),
                          ),
                  ),
                  const SizedBox(height: 16),
                  _buildKeypad(theme, scheme),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  /// 圆点指示器：已输入位数；为空时显示 [AppLockService.minPinLength] 个占位圆点。
  Widget _buildDots(ColorScheme scheme) {
    final count = _pin.isEmpty ? AppLockService.minPinLength : _pin.length;
    return AnimatedBuilder(
      animation: _shake,
      builder: (context, child) {
        final dx = math.sin(_shake.value * math.pi * 6) * 10 * (1 - _shake.value);
        return Transform.translate(offset: Offset(dx, 0), child: child);
      },
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          for (var i = 0; i < count; i++)
            Container(
              width: 14,
              height: 14,
              margin: const EdgeInsets.symmetric(horizontal: 6),
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: i < _pin.length ? scheme.primary : Colors.transparent,
                border: Border.all(color: scheme.outlineVariant, width: 1.5),
              ),
            ),
        ],
      ),
    );
  }

  /// 数字键盘：0-9 + 删除 + 确认。
  Widget _buildKeypad(ThemeData theme, ColorScheme scheme) {
    Widget digitKey(String label) =>
        _keyButton(label: label, onTap: () => _onDigit(label));

    Widget iconKey(IconData icon, VoidCallback onTap, {bool primary = false}) =>
        _keyButton(
          icon: icon,
          onTap: onTap,
          background: primary ? scheme.primary : scheme.surfaceContainerHighest,
          foreground: primary ? scheme.onPrimary : scheme.onSurface,
        );

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        _keyRow([digitKey('1'), digitKey('2'), digitKey('3')]),
        const SizedBox(height: 12),
        _keyRow([digitKey('4'), digitKey('5'), digitKey('6')]),
        const SizedBox(height: 12),
        _keyRow([digitKey('7'), digitKey('8'), digitKey('9')]),
        const SizedBox(height: 12),
        _keyRow([
          iconKey(Icons.check, () => _submit(isConfirm: true), primary: true),
          digitKey('0'),
          iconKey(Icons.backspace_outlined, _onDelete),
        ]),
      ],
    );
  }

  Widget _keyRow(List<Widget> children) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        for (var i = 0; i < children.length; i++) ...[
          if (i > 0) const SizedBox(width: 16),
          children[i],
        ],
      ],
    );
  }

  Widget _keyButton({
    String? label,
    IconData? icon,
    required VoidCallback onTap,
    Color? background,
    Color? foreground,
  }) {
    final scheme = Theme.of(context).colorScheme;
    return SizedBox(
      width: 72,
      height: 72,
      child: Material(
        color: background ?? scheme.surfaceContainerHighest,
        shape: const CircleBorder(),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          customBorder: const CircleBorder(),
          onTap: onTap,
          child: Center(
            child: icon != null
                ? Icon(icon, color: foreground ?? scheme.onSurface)
                : Text(
                    label!,
                    style: TextStyle(
                      fontSize: 26,
                      fontWeight: FontWeight.w500,
                      color: foreground ?? scheme.onSurface,
                    ),
                  ),
          ),
        ),
      ),
    );
  }
}
