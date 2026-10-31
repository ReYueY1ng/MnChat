/// 设置 · 消息与通知子页。
///
/// 内容：通知总开关、通知内容/提示音/震动、群里仅 @我 提醒、免打扰时段、
/// 进会话自动已读、回车发送、后台保持连接，以及快捷短语管理
/// （原独立页面 `message_settings_page.dart` 的内容并到这里）。
///
/// 会话级的免打扰 / 置顶不在这里 —— 它们在会话列表长按菜单里，见本页底部说明。
library;

import 'package:flutter/foundation.dart'
    show TargetPlatform, defaultTargetPlatform;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';

import '../core/services/platform_capabilities.dart' show PlatformCapabilities;
import '../state/providers.dart';
import 'theme/app_tokens.dart';
import 'widgets/settings_tiles.dart';

import 'widgets/app_l10n.dart' show l10nOf;

class SettingsNotificationPage extends ConsumerStatefulWidget {
  const SettingsNotificationPage({super.key});

  @override
  ConsumerState<SettingsNotificationPage> createState() =>
      _SettingsNotificationPageState();
}

class _SettingsNotificationPageState
    extends ConsumerState<SettingsNotificationPage> {
  List<String> _phrases = [];
  bool _phrasesLoading = true;

  /// 震动只有移动端有意义（桌面通知没有震动）。
  static bool get _supportsVibrate =>
      defaultTargetPlatform == TargetPlatform.android;

  @override
  void initState() {
    super.initState();
    _loadPhrases();
  }

  Future<void> _loadPhrases() async {
    final list = await ref.read(settingsProvider).quickPhrases();
    if (!mounted) return;
    setState(() {
      _phrases = list;
      _phrasesLoading = false;
    });
  }

  Future<void> _addPhrase() async {
    final controller = TextEditingController();
    final text = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(l10nOf(context)?.settingsNotificationAddQuickPhrase ?? '新增快捷短语'),
        content: TextField(
          controller: controller,
          autofocus: true,
          maxLength: 20,
          decoration: InputDecoration(hintText: l10nOf(context)?.settingsNotificationEnterPhraseContent ?? '输入短语内容'),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: Text(l10nOf(context)?.commonCancel ?? '取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, controller.text.trim()),
            child: Text(l10nOf(context)?.settingsNotificationAdd ?? '添加'),
          ),
        ],
      ),
    );
    if (text == null || text.isEmpty) return;
    final ok = await ref.read(settingsProvider).addQuickPhrase(text);
    if (!mounted) return;
    if (!ok) showSettingsToast(context, l10nOf(context)?.settingsNotificationPhraseAlreadyExistsInvalid ?? '短语已存在或内容无效');
    await _loadPhrases();
  }

  Future<void> _removePhrase(String text) async {
    await ref.read(settingsProvider).removeQuickPhrase(text);
    await _loadPhrases();
  }

  Future<void> _toggleNotify(bool value) async {
    await ref.read(notifyEnabledProvider.notifier).set(value);
    if (mounted) {
      showSettingsToast(context, value ? l10nOf(context)?.settingsNotificationNewMessageNotificationsEnabled ?? '已开启新消息通知' : l10nOf(context)?.settingsNotificationNewMessageNotificationsDisabled ?? '已关闭新消息通知');
    }
  }

  Future<void> _toggleKeepAlive(bool value) async {
    await ref.read(keepAliveProvider.notifier).set(value);
    if (mounted) {
      showSettingsToast(context, value ? l10nOf(context)?.settingsNotificationBackgroundConnectionEnabled ?? '已开启后台保持连接' : l10nOf(context)?.settingsNotificationBackgroundConnectionDisabled ?? '已关闭后台保持连接');
    }
  }

  /// 选择免打扰时段（起 / 止两次取时）。
  Future<void> _pickDndWindow() async {
    final cur = ref.read(dndWindowProvider);
    final start = await showTimePicker(
      context: context,
      initialTime: TimeOfDay(hour: cur.start ~/ 60, minute: cur.start % 60),
      helpText: l10nOf(context)?.settingsNotificationDoDisturbStarts ?? '免打扰开始',
    );
    if (start == null || !mounted) return;
    final end = await showTimePicker(
      context: context,
      initialTime: TimeOfDay(hour: cur.end ~/ 60, minute: cur.end % 60),
      helpText: l10nOf(context)?.settingsNotificationDoDisturbEnds ?? '免打扰结束',
    );
    if (end == null) return;
    await ref
        .read(dndWindowProvider.notifier)
        .set(
          DndWindow(
            start: start.hour * 60 + start.minute,
            end: end.hour * 60 + end.minute,
          ),
        );
    if (mounted) showSettingsToast(context, l10nOf(context)?.settingsNotificationDoDisturbHoursUpdated ?? '免打扰时段已更新');
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final notifyOn = ref.watch(notifyEnabledProvider);

    return Scaffold(
      appBar: AppBar(title: Text(l10nOf(context)?.settingsNotificationMessagesNotifications ?? '消息与通知')),
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: AppSizes.narrowContent),
          child: ListView(
            padding: const EdgeInsets.all(AppSpacing.md),
            children: [
              SettingsSectionHeader(l10nOf(context)?.settingsNotificationNotifications ?? '通知'),
              if (!PlatformCapabilities.current.backgroundNotifications)
                SettingsInfoTile(
                  icon: Icons.info_outline,
                  title: l10nOf(context)?.settingsNotificationBackgroundNotificationsArentSupported ?? '当前平台不支持后台通知',
                  subtitle:
                      PlatformCapabilities.current.limitation ??
                      l10nOf(context)?.settingsNotificationYouWontReceiveSystem ?? '应用退到后台后不会收到系统通知。',
                ),
              SettingsSwitchTile(
                icon: Icons.notifications_active_outlined,
                title: l10nOf(context)?.settingsNotificationNewMessageNotifications ?? '新消息通知',
                subtitle: l10nOf(context)?.settingsNotificationShowSystemNotificationNew ?? '应用在后台时收到新消息弹出系统通知',
                value: notifyOn,
                onChanged: _toggleNotify,
              ),
              SettingsSwitchTile(
                icon: Icons.visibility_off_outlined,
                title: l10nOf(context)?.settingsNotificationHideNotificationContent ?? '通知隐藏内容',
                subtitle: l10nOf(context)?.settingsNotificationShowNewMessageAlert ?? '锁屏 / 通知栏只提示有新消息，不显示正文',
                value: ref.watch(hideNotifyContentProvider),
                // 通知总开关关掉后，下面这些细化项没有意义，一并置灰。
                onChanged: notifyOn
                    ? (v) =>
                          ref.read(hideNotifyContentProvider.notifier).set(v)
                    : null,
              ),
              SettingsSwitchTile(
                icon: Icons.volume_up_outlined,
                title: l10nOf(context)?.settingsNotificationNotificationSound ?? '通知提示音',
                subtitle: l10nOf(context)?.settingsNotificationWhenOffNotificationsArrive ?? '关闭后通知静默到达（通知本身照常出现）',
                value: ref.watch(notifySoundProvider),
                onChanged: notifyOn
                    ? (v) => ref.read(notifySoundProvider.notifier).set(v)
                    : null,
              ),
              if (_supportsVibrate)
                SettingsSwitchTile(
                  icon: Icons.vibration,
                  title: l10nOf(context)?.settingsNotificationNotificationVibration ?? '通知震动',
                  subtitle: l10nOf(context)?.settingsNotificationVibrateWhenNewMessage ?? '收到新消息时震动提醒',
                  value: ref.watch(notifyVibrateProvider),
                  onChanged: notifyOn
                      ? (v) => ref.read(notifyVibrateProvider.notifier).set(v)
                      : null,
                ),
              SettingsSwitchTile(
                icon: Icons.alternate_email,
                title: l10nOf(context)?.settingsNotificationOnlyAlertMeMentions ?? '群里仅 @我 时提醒',
                subtitle: l10nOf(context)?.settingsNotificationWhenGroupMessagesNotify ?? '开启后群消息只有提到我（正文含 @我的昵称）才弹通知，私聊不受影响',
                value: ref.watch(notifyMentionOnlyProvider),
                onChanged: notifyOn
                    ? (v) => ref.read(notifyMentionOnlyProvider.notifier).set(v)
                    : null,
              ),
              SettingsSwitchTile(
                icon: Icons.nightlight_outlined,
                title: l10nOf(context)?.settingsNotificationDoDisturbHours ?? '免打扰时段',
                subtitle: ref.watch(dndWindowProvider).label,
                value: ref.watch(dndEnabledProvider),
                onChanged: (v) => ref.read(dndEnabledProvider.notifier).set(v),
                // 点标题取时间段，点开关切启用 —— 所以用 ListTile + 尾部 Switch。
                onTap: _pickDndWindow,
              ),

              SettingsSectionHeader(l10nOf(context)?.settingsNotificationMessages ?? '消息'),
              SettingsSwitchTile(
                icon: Icons.mark_chat_read_outlined,
                title: l10nOf(context)?.settingsNotificationMarkReadOpen ?? '进入会话自动已读',
                subtitle: l10nOf(context)?.settingsNotificationClearUnreadMarkerWhen ?? '打开会话即清除未读标记',
                value: ref.watch(autoMarkReadProvider),
                onChanged: (v) => ref.read(autoMarkReadProvider.notifier).set(v),
              ),
              SettingsSwitchTile(
                icon: Icons.keyboard_return_outlined,
                title: l10nOf(context)?.settingsNotificationSendEnter ?? '回车发送',
                subtitle: l10nOf(context)?.settingsNotificationOnDesktopPressEnter ?? '桌面端按 Enter 发送，Shift+Enter 换行',
                value: ref.watch(sendOnEnterProvider),
                onChanged: (v) => ref.read(sendOnEnterProvider.notifier).set(v),
              ),
              SettingsSwitchTile(
                icon: Icons.sync_lock_outlined,
                title: l10nOf(context)?.settingsNotificationKeepConnectionBackground ?? '后台保持连接',
                subtitle: l10nOf(context)?.settingsNotificationTheForegroundServiceKeeps ?? '由前台服务维持长连接，后台也能收到新消息',
                value: ref.watch(keepAliveProvider),
                onChanged: _toggleKeepAlive,
              ),

              SettingsSectionHeader(l10nOf(context)?.settingsNotificationQuickPhrases ?? '快捷短语'),
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(AppSpacing.lg),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        l10nOf(context)?.settingsNotificationInsertQuicklyWhenSending ?? '发送消息时快捷插入（对齐游戏内置 SecretQuickMsg）',
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: theme.colorScheme.outline,
                        ),
                      ),
                      const SizedBox(height: AppSpacing.md),
                      if (_phrasesLoading)
                        const Center(child: CircularProgressIndicator())
                      else if (_phrases.isEmpty)
                        Text(l10nOf(context)?.settingsNotificationNoPhrasesYet ?? '暂无短语', style: theme.textTheme.bodyMedium)
                      else
                        Wrap(
                          spacing: AppSpacing.sm,
                          runSpacing: AppSpacing.sm,
                          children: [
                            for (final p in _phrases)
                              InputChip(
                                label: Text(p),
                                onDeleted: () => _removePhrase(p),
                              ),
                          ],
                        ),
                      const SizedBox(height: AppSpacing.md),
                      Align(
                        alignment: Alignment.centerLeft,
                        child: TextButton.icon(
                          onPressed: _addPhrase,
                          icon: const Icon(Icons.add, size: 18),
                          label: Text(l10nOf(context)?.settingsNotificationAddPhrase ?? '新增短语'),
                        ),
                      ),
                    ],
                  ),
                ),
              ),

              SettingsSectionHeader(l10nOf(context)?.commonConversations ?? '会话'),
              Card(
                child: ListTile(
                  leading: const Icon(Icons.chat_outlined),
                  title: Text(l10nOf(context)?.settingsNotificationPerConversationMutePin ?? '会话级免打扰 / 置顶'),
                  subtitle: Text(l10nOf(context)?.settingsNotificationLongPressConversationList ?? '在会话列表长按某条会话设置'),
                ),
              ),
              const SizedBox(height: AppSpacing.xl),
            ],
          ),
        ),
      ),
    );
  }
}
