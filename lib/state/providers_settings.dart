part of 'providers.dart';

/// 应用主题模式（跟随系统 / 浅色 / 深色），持久化到设置。
enum AppThemeMode {
  system('system', '跟随系统'),
  light('light', '浅色'),
  dark('dark', '深色');

  const AppThemeMode(this.key, this.label);
  final String key;
  final String label;

  static AppThemeMode fromKey(String? k) => AppThemeMode.values.firstWhere(
    (m) => m.key == k,
    orElse: () => AppThemeMode.system,
  );
}

/// 主题模式（持久化到设置）。
final appThemeModeProvider =
    NotifierProvider<AppThemeModeNotifier, AppThemeMode>(
      AppThemeModeNotifier.new,
    );

class AppThemeModeNotifier extends Notifier<AppThemeMode> {
  @override
  AppThemeMode build() {
    ref
        .read(settingsProvider)
        .getString(SettingsKeys.themeMode)
        .then((k) {
          if (!ref.mounted) return;
          final m = AppThemeMode.fromKey(k);
          if (m != state) state = m;
        })
        .catchError((Object _) {
          // 设置读取失败保持默认值
        });
    return AppThemeMode.system;
  }

  Future<void> setMode(AppThemeMode mode) async {
    state = mode;
    await ref
        .read(settingsProvider)
        .setString(SettingsKeys.themeMode, mode.key);
  }
}

/// 新消息通知开关（运行时即时生效，持久化到设置）。
final notifyEnabledProvider = NotifierProvider<NotifyEnabledNotifier, bool>(
  NotifyEnabledNotifier.new,
);

class NotifyEnabledNotifier extends Notifier<bool> {
  @override
  bool build() {
    ref
        .read(settingsProvider)
        .getBool(SettingsKeys.notifyEnabled, fallback: true)
        .then((v) {
          if (!ref.mounted) return;
          if (v != state) state = v;
        })
        .catchError((Object _) {
          // 设置读取失败保持默认值
        });
    return true;
  }

  Future<void> set(bool value) async {
    state = value;
    await ref.read(settingsProvider).setBool(SettingsKeys.notifyEnabled, value);
  }
}

/// 后台保活开关（前台服务维持长连接，后台也能收推送），持久化到设置。
/// 默认开启：与旧行为一致（进入主界面即启动前台服务）。
final keepAliveProvider = NotifierProvider<KeepAliveNotifier, bool>(
  KeepAliveNotifier.new,
);

class KeepAliveNotifier extends Notifier<bool> {
  @override
  bool build() {
    ref
        .read(settingsProvider)
        .getBool(SettingsKeys.keepAlive, fallback: true)
        .then((v) {
          if (!ref.mounted) return;
          if (v != state) state = v;
        })
        .catchError((Object _) {
          // 设置读取失败保持默认值
        });
    return true;
  }

  Future<void> set(bool value) async {
    state = value;
    await ref.read(settingsProvider).setBool(SettingsKeys.keepAlive, value);
  }
}

/// 已登录用户 uin（供聊天页判断消息方向）。
///
/// 必须从 [authProvider]（Notifier）派生而非直接读 chatServiceProvider：
/// 通知服务：按平台选择实现（Android 原生 / Linux dbus / 其他 Noop）。
///
/// 单元测试环境不会碰到原生通道或 dbus —— Noop 实现什么都不做、也不抛异常。
final notificationServiceProvider = Provider<NotificationService>(
  (ref) => createNotificationService(),
);

// ── 通用设置（显示 / 输入 / 隐私 / 桌面端）────────────────────────────────

/// 安全获取设置存储：测试等环境未注入 databaseProvider 时返回 null，
/// 让设置类 provider 退化为默认值，而不是把异常抛给 UI。
SettingsStore? _trySettings(Ref ref) {
  try {
    return ref.read(settingsProvider);
  } catch (_) {
    return null;
  }
}

/// 布尔类设置的通用基类：读 [key]，默认值 [fallback]，写入即时生效。
abstract class _BoolSettingNotifier extends Notifier<bool> {
  String get key;
  bool get fallback;

  @override
  bool build() {
    _trySettings(ref)
        ?.getBool(key, fallback: fallback)
        .then((v) {
          if (!ref.mounted) return;
          if (v != state) state = v;
        })
        .catchError((Object _) {
          // 读取失败保持默认值
        });
    return fallback;
  }

  Future<void> set(bool value) async {
    state = value;
    await _trySettings(ref)?.setBool(key, value);
  }
}

/// 头像框动画开关：关闭后仅使用静态 PNG（省电 / 省流）。
final animatedFramesProvider = NotifierProvider<AnimatedFramesNotifier, bool>(
  AnimatedFramesNotifier.new,
);

class AnimatedFramesNotifier extends _BoolSettingNotifier {
  @override
  String get key => SettingsKeys.animatedFrames;
  @override
  bool get fallback => true;
}

/// 富文本显示原文本：开启后昵称 / 消息名原样显示标签串
/// （如 `[i][color][b]顾念`），不再解析颜色 / 加粗 / 表情。
/// 默认关闭：与旧行为一致，展示解析后的富文本。
final richTextRawProvider = NotifierProvider<RichTextRawNotifier, bool>(
  RichTextRawNotifier.new,
);

class RichTextRawNotifier extends _BoolSettingNotifier {
  @override
  String get key => SettingsKeys.richTextRaw;
  @override
  bool get fallback => false;
}

/// 回车发送（桌面端）。
final sendOnEnterProvider = NotifierProvider<SendOnEnterNotifier, bool>(
  SendOnEnterNotifier.new,
);

class SendOnEnterNotifier extends _BoolSettingNotifier {
  @override
  String get key => SettingsKeys.sendOnEnter;
  @override
  bool get fallback => true;
}

/// 进入会话自动标记已读。
final autoMarkReadProvider = NotifierProvider<AutoMarkReadNotifier, bool>(
  AutoMarkReadNotifier.new,
);

class AutoMarkReadNotifier extends _BoolSettingNotifier {
  @override
  String get key => SettingsKeys.autoMarkRead;
  @override
  bool get fallback => true;
}

/// 通知隐藏内容（锁屏仅提示"有新消息"，不显示正文）。
final hideNotifyContentProvider =
    NotifierProvider<HideNotifyContentNotifier, bool>(
      HideNotifyContentNotifier.new,
    );

class HideNotifyContentNotifier extends _BoolSettingNotifier {
  @override
  String get key => SettingsKeys.hideNotifyContent;
  @override
  bool get fallback => false;
}

/// 免打扰时段开关。
final dndEnabledProvider = NotifierProvider<DndEnabledNotifier, bool>(
  DndEnabledNotifier.new,
);

class DndEnabledNotifier extends _BoolSettingNotifier {
  @override
  String get key => SettingsKeys.dndEnabled;
  @override
  bool get fallback => false;
}

/// 关闭到托盘（仅桌面端生效）。
final closeToTrayProvider = NotifierProvider<CloseToTrayNotifier, bool>(
  CloseToTrayNotifier.new,
);

class CloseToTrayNotifier extends _BoolSettingNotifier {
  @override
  String get key => SettingsKeys.closeToTray;
  @override
  bool get fallback => true;
}

/// 应用锁开关。
final lockEnabledProvider = NotifierProvider<LockEnabledNotifier, bool>(
  LockEnabledNotifier.new,
);

class LockEnabledNotifier extends _BoolSettingNotifier {
  @override
  String get key => SettingsKeys.lockEnabled;
  @override
  bool get fallback => false;
}

/// 访问主页留下踪迹：关闭后不再向对方发送访问记录。
/// 默认开启 —— 与官方客户端一致（playercenterv2datamanager.lua 中
/// `if layoutInfo.VisitRecord == nil then layoutInfo.VisitRecord = true end`）。
final leaveVisitTraceProvider =
    NotifierProvider<LeaveVisitTraceNotifier, bool>(
      LeaveVisitTraceNotifier.new,
    );

class LeaveVisitTraceNotifier extends _BoolSettingNotifier {
  @override
  String get key => SettingsKeys.leaveVisitTrace;

  // 默认关：这个开关一开，看一眼别人的主页就会在对方访客记录里留一条。
  // 「会通知到第三方」的动作不该默默替用户选上 —— 想留痕的自己打开。
  @override
  bool get fallback => false;
}

/// 允许他人拉我入群（本地镜像 + 服务端 `update_user_groups?join=`）。
///
/// 服务端没有查询接口，故以本地持久化为准，变更时同步一份给服务端。
final allowInvitedToGroupProvider =
    NotifierProvider<AllowInvitedToGroupNotifier, bool>(
      AllowInvitedToGroupNotifier.new,
    );

class AllowInvitedToGroupNotifier extends Notifier<bool> {
  @override
  bool build() {
    _trySettings(ref)
        ?.getBool(SettingsKeys.allowInvitedToGroup, fallback: true)
        .then((v) {
          if (!ref.mounted) return;
          if (v != state) state = v;
        })
        .catchError((Object _) {});
    return true;
  }

  Future<void> set(bool value) async {
    state = value;
    await _trySettings(ref)?.setBool(SettingsKeys.allowInvitedToGroup, value);
    try {
      await ref.read(chatServiceProvider).setAllowInvitedToGroup(allow: value);
    } catch (_) {
      // 服务端同步失败不影响本地记录
    }
  }
}

/// 自动加入被邀请的群（本地镜像 + 服务端 `update_user_groups?auto_join=`）。
final allowAutoJoinGroupProvider =
    NotifierProvider<AllowAutoJoinGroupNotifier, bool>(
      AllowAutoJoinGroupNotifier.new,
    );

class AllowAutoJoinGroupNotifier extends Notifier<bool> {
  @override
  bool build() {
    _trySettings(ref)
        ?.getBool(SettingsKeys.allowAutoJoinGroup, fallback: false)
        .then((v) {
          if (!ref.mounted) return;
          if (v != state) state = v;
        })
        .catchError((Object _) {});
    return false;
  }

  Future<void> set(bool value) async {
    state = value;
    await _trySettings(ref)?.setBool(SettingsKeys.allowAutoJoinGroup, value);
    try {
      await ref.read(chatServiceProvider).setAllowAutoJoinGroup(allow: value);
    } catch (_) {
      // 服务端同步失败不影响本地记录
    }
  }
}

/// 聊天字号缩放（[ChatFontScaleNotifier.min] ~ [ChatFontScaleNotifier.max]）。
final chatFontScaleProvider =
    NotifierProvider<ChatFontScaleNotifier, double>(ChatFontScaleNotifier.new);

class ChatFontScaleNotifier extends Notifier<double> {
  static const double min = 0.8;
  static const double max = 1.6;

  @override
  double build() {
    _trySettings(ref)
        ?.getDouble(SettingsKeys.chatFontScale)
        .then((v) {
          if (!ref.mounted) return;
          if (v != null) {
            final c = v.clamp(min, max);
            if (c != state) state = c;
          }
        })
        .catchError((Object _) {});
    return 1.0;
  }

  Future<void> set(double value) async {
    final v = value.clamp(min, max);
    state = v;
    await _trySettings(ref)?.setDouble(SettingsKeys.chatFontScale, v);
  }
}

/// 主题强调色（seed）。
final accentColorProvider = NotifierProvider<AccentColorNotifier, Color>(
  AccentColorNotifier.new,
);

class AccentColorNotifier extends Notifier<Color> {
  /// 品牌 seed（与 `AppColors.brandSeed` 一致；内联以避免 state→ui 层依赖）。
  static const Color defaultSeed = Color(0xFF108850);

  @override
  Color build() {
    _trySettings(ref)
        ?.getInt(SettingsKeys.seedColor)
        .then((v) {
          if (!ref.mounted || v == null) return;
          final c = Color(v);
          if (c != state) state = c;
        })
        .catchError((Object _) {});
    return defaultSeed;
  }

  Future<void> set(Color c) async {
    state = c;
    await _trySettings(ref)?.setInt(SettingsKeys.seedColor, c.toARGB32());
  }
}

/// 免打扰时段：起止为当天分钟数；[start] > [end] 表示跨午夜。
class DndWindow {
  final int start;
  final int end;
  const DndWindow({this.start = 22 * 60, this.end = 8 * 60});

  /// [now] 是否落在免打扰时段内。
  bool contains(DateTime now) {
    if (start == end) return false;
    final m = now.hour * 60 + now.minute;
    return start < end ? (m >= start && m < end) : (m >= start || m < end);
  }

  String get label => '${_hhmm(start)} - ${_hhmm(end)}';

  static String _hhmm(int m) =>
      '${(m ~/ 60).toString().padLeft(2, '0')}:'
      '${(m % 60).toString().padLeft(2, '0')}';
}

final dndWindowProvider = NotifierProvider<DndWindowNotifier, DndWindow>(
  DndWindowNotifier.new,
);

class DndWindowNotifier extends Notifier<DndWindow> {
  @override
  DndWindow build() {
    final settings = _trySettings(ref);
    settings
        ?.getInt(SettingsKeys.dndStart)
        .then((s) {
          if (!ref.mounted || s == null) return;
          state = DndWindow(start: s, end: state.end);
        })
        .catchError((Object _) {});
    settings
        ?.getInt(SettingsKeys.dndEnd)
        .then((e) {
          if (!ref.mounted || e == null) return;
          state = DndWindow(start: state.start, end: e);
        })
        .catchError((Object _) {});
    return const DndWindow();
  }

  Future<void> set(DndWindow w) async {
    state = w;
    final settings = _trySettings(ref);
    if (settings == null) return;
    await settings.setInt(SettingsKeys.dndStart, w.start);
    await settings.setInt(SettingsKeys.dndEnd, w.end);
  }
}

// ── 通知细化 ────────────────────────────────────────────

/// 通知提示音：关闭后通知静默到达（通知本身照常出现）。默认开启。
final notifySoundProvider = NotifierProvider<NotifySoundNotifier, bool>(
  NotifySoundNotifier.new,
);

class NotifySoundNotifier extends _BoolSettingNotifier {
  @override
  String get key => SettingsKeys.notifySound;
  @override
  bool get fallback => true;
}

/// 通知震动（移动端有意义，桌面端无效果）。默认开启。
final notifyVibrateProvider = NotifierProvider<NotifyVibrateNotifier, bool>(
  NotifyVibrateNotifier.new,
);

class NotifyVibrateNotifier extends _BoolSettingNotifier {
  @override
  String get key => SettingsKeys.notifyVibrate;
  @override
  bool get fallback => true;
}

/// 群里仅 @我 时通知。
///
/// 开启后群消息只有正文提到本人昵称（`@昵称`）才弹通知，私聊不受影响。
/// 默认关闭（所有消息都通知）。
final notifyMentionOnlyProvider =
    NotifierProvider<NotifyMentionOnlyNotifier, bool>(
      NotifyMentionOnlyNotifier.new,
    );

class NotifyMentionOnlyNotifier extends _BoolSettingNotifier {
  @override
  String get key => SettingsKeys.notifyMentionOnly;
  @override
  bool get fallback => false;
}

