// ignore: unused_import
import 'package:intl/intl.dart' as intl;

import 'app_localizations.dart';

// ignore_for_file: type=lint

/// The translations for Chinese (`zh`).
class AppLocalizationsZh extends AppLocalizations {
  AppLocalizationsZh([String locale = 'zh']) : super(locale);

  @override
  String get appTitle => 'MnChat · 迷你世界外部聊天';

  @override
  String get menuCopy => '复制';

  @override
  String get menuQuote => '引用';

  @override
  String get menuForward => '转发';

  @override
  String get menuMultiSelect => '多选';

  @override
  String get menuFavorite => '收藏';

  @override
  String get menuUnfavorite => '取消收藏';

  @override
  String get menuDeleteLocal => '删除（仅本机）';

  @override
  String get menuResend => '重新发送';

  @override
  String get sheetMessageActions => '消息操作';

  @override
  String get favoritesTitle => '收藏';

  @override
  String get favoritesEmpty => '还没有收藏的消息';

  @override
  String get favoritesEmptyHint => '长按任意消息即可收藏';

  @override
  String get searchTitle => '搜索聊天记录';

  @override
  String get searchHint => '搜索全部会话';

  @override
  String get searchEmpty => '没有匹配的消息';

  @override
  String get searchEmptyHint => '换个关键词试试，支持单字搜索';

  @override
  String searchCount(int count) {
    return '找到 $count 条';
  }

  @override
  String get searchScopeAll => '全部会话';

  @override
  String selectedCount(int count) {
    return '已选 $count 条';
  }

  @override
  String get actionForward => '转发';

  @override
  String get actionDelete => '删除';

  @override
  String get actionFavorite => '收藏';

  @override
  String get toastCopied => '已复制';

  @override
  String get toastFavorited => '已收藏';

  @override
  String get toastUnfavorited => '已取消收藏';

  @override
  String get toastDeletedLocal => '已在本机删除';

  @override
  String get toastForwarded => '已转发';

  @override
  String get commonCancel => '取消';

  @override
  String get commonClose => '关闭';

  @override
  String get commonConfirm => '确定';

  @override
  String get commonUndo => '撤销';

  @override
  String get forwardPickSession => '选择要转发到的会话';

  @override
  String get forwardNoTarget => '没有可转发的好友或群';

  @override
  String get deleteLocalConfirmTitle => '在本机删除消息？';

  @override
  String get deleteLocalConfirmBody => '只影响本机记录，对方和其他设备仍能看到这条消息。';

  @override
  String get quotePrefix => '引用';

  @override
  String get voiceMessage => '语音';

  @override
  String get typingIndicator => '对方正在输入…';
}
