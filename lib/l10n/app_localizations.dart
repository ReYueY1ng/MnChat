import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:intl/intl.dart' as intl;

import 'app_localizations_zh.dart';

// ignore_for_file: type=lint

/// Callers can lookup localized strings with an instance of AppLocalizations
/// returned by `AppLocalizations.of(context)`.
///
/// Applications need to include `AppLocalizations.delegate()` in their app's
/// `localizationDelegates` list, and the locales they support in the app's
/// `supportedLocales` list. For example:
///
/// ```dart
/// import 'l10n/app_localizations.dart';
///
/// return MaterialApp(
///   localizationsDelegates: AppLocalizations.localizationsDelegates,
///   supportedLocales: AppLocalizations.supportedLocales,
///   home: MyApplicationHome(),
/// );
/// ```
///
/// ## Update pubspec.yaml
///
/// Please make sure to update your pubspec.yaml to include the following
/// packages:
///
/// ```yaml
/// dependencies:
///   # Internationalization support.
///   flutter_localizations:
///     sdk: flutter
///   intl: any # Use the pinned version from flutter_localizations
///
///   # Rest of dependencies
/// ```
///
/// ## iOS Applications
///
/// iOS applications define key application metadata, including supported
/// locales, in an Info.plist file that is built into the application bundle.
/// To configure the locales supported by your app, you’ll need to edit this
/// file.
///
/// First, open your project’s ios/Runner.xcworkspace Xcode workspace file.
/// Then, in the Project Navigator, open the Info.plist file under the Runner
/// project’s Runner folder.
///
/// Next, select the Information Property List item, select Add Item from the
/// Editor menu, then select Localizations from the pop-up menu.
///
/// Select and expand the newly-created Localizations item then, for each
/// locale your application supports, add a new item and select the locale
/// you wish to add from the pop-up menu in the Value field. This list should
/// be consistent with the languages listed in the AppLocalizations.supportedLocales
/// property.
abstract class AppLocalizations {
  AppLocalizations(String locale)
    : localeName = intl.Intl.canonicalizedLocale(locale.toString());

  final String localeName;

  static AppLocalizations of(BuildContext context) {
    return Localizations.of<AppLocalizations>(context, AppLocalizations)!;
  }

  static const LocalizationsDelegate<AppLocalizations> delegate =
      _AppLocalizationsDelegate();

  /// A list of this localizations delegate along with the default localizations
  /// delegates.
  ///
  /// Returns a list of localizations delegates containing this delegate along with
  /// GlobalMaterialLocalizations.delegate, GlobalCupertinoLocalizations.delegate,
  /// and GlobalWidgetsLocalizations.delegate.
  ///
  /// Additional delegates can be added by appending to this list in
  /// MaterialApp. This list does not have to be used at all if a custom list
  /// of delegates is preferred or required.
  static const List<LocalizationsDelegate<dynamic>> localizationsDelegates =
      <LocalizationsDelegate<dynamic>>[
        delegate,
        GlobalMaterialLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
      ];

  /// A list of this localizations delegate's supported locales.
  static const List<Locale> supportedLocales = <Locale>[Locale('zh')];

  /// No description provided for @appTitle.
  ///
  /// In zh, this message translates to:
  /// **'MnChat · 迷你世界外部聊天'**
  String get appTitle;

  /// No description provided for @menuCopy.
  ///
  /// In zh, this message translates to:
  /// **'复制'**
  String get menuCopy;

  /// No description provided for @menuQuote.
  ///
  /// In zh, this message translates to:
  /// **'引用'**
  String get menuQuote;

  /// No description provided for @menuForward.
  ///
  /// In zh, this message translates to:
  /// **'转发'**
  String get menuForward;

  /// No description provided for @menuMultiSelect.
  ///
  /// In zh, this message translates to:
  /// **'多选'**
  String get menuMultiSelect;

  /// No description provided for @menuFavorite.
  ///
  /// In zh, this message translates to:
  /// **'收藏'**
  String get menuFavorite;

  /// No description provided for @menuUnfavorite.
  ///
  /// In zh, this message translates to:
  /// **'取消收藏'**
  String get menuUnfavorite;

  /// No description provided for @menuDeleteLocal.
  ///
  /// In zh, this message translates to:
  /// **'删除（仅本机）'**
  String get menuDeleteLocal;

  /// No description provided for @menuResend.
  ///
  /// In zh, this message translates to:
  /// **'重新发送'**
  String get menuResend;

  /// No description provided for @sheetMessageActions.
  ///
  /// In zh, this message translates to:
  /// **'消息操作'**
  String get sheetMessageActions;

  /// No description provided for @favoritesTitle.
  ///
  /// In zh, this message translates to:
  /// **'收藏'**
  String get favoritesTitle;

  /// No description provided for @favoritesEmpty.
  ///
  /// In zh, this message translates to:
  /// **'还没有收藏的消息'**
  String get favoritesEmpty;

  /// No description provided for @favoritesEmptyHint.
  ///
  /// In zh, this message translates to:
  /// **'长按任意消息即可收藏'**
  String get favoritesEmptyHint;

  /// No description provided for @searchTitle.
  ///
  /// In zh, this message translates to:
  /// **'搜索聊天记录'**
  String get searchTitle;

  /// No description provided for @searchHint.
  ///
  /// In zh, this message translates to:
  /// **'搜索全部会话'**
  String get searchHint;

  /// No description provided for @searchEmpty.
  ///
  /// In zh, this message translates to:
  /// **'没有匹配的消息'**
  String get searchEmpty;

  /// No description provided for @searchEmptyHint.
  ///
  /// In zh, this message translates to:
  /// **'换个关键词试试，支持单字搜索'**
  String get searchEmptyHint;

  /// No description provided for @searchCount.
  ///
  /// In zh, this message translates to:
  /// **'找到 {count} 条'**
  String searchCount(int count);

  /// No description provided for @searchScopeAll.
  ///
  /// In zh, this message translates to:
  /// **'全部会话'**
  String get searchScopeAll;

  /// No description provided for @selectedCount.
  ///
  /// In zh, this message translates to:
  /// **'已选 {count} 条'**
  String selectedCount(int count);

  /// No description provided for @actionForward.
  ///
  /// In zh, this message translates to:
  /// **'转发'**
  String get actionForward;

  /// No description provided for @actionDelete.
  ///
  /// In zh, this message translates to:
  /// **'删除'**
  String get actionDelete;

  /// No description provided for @actionFavorite.
  ///
  /// In zh, this message translates to:
  /// **'收藏'**
  String get actionFavorite;

  /// No description provided for @toastCopied.
  ///
  /// In zh, this message translates to:
  /// **'已复制'**
  String get toastCopied;

  /// No description provided for @toastFavorited.
  ///
  /// In zh, this message translates to:
  /// **'已收藏'**
  String get toastFavorited;

  /// No description provided for @toastUnfavorited.
  ///
  /// In zh, this message translates to:
  /// **'已取消收藏'**
  String get toastUnfavorited;

  /// No description provided for @toastDeletedLocal.
  ///
  /// In zh, this message translates to:
  /// **'已在本机删除'**
  String get toastDeletedLocal;

  /// No description provided for @toastForwarded.
  ///
  /// In zh, this message translates to:
  /// **'已转发'**
  String get toastForwarded;

  /// No description provided for @commonCancel.
  ///
  /// In zh, this message translates to:
  /// **'取消'**
  String get commonCancel;

  /// No description provided for @commonClose.
  ///
  /// In zh, this message translates to:
  /// **'关闭'**
  String get commonClose;

  /// No description provided for @commonConfirm.
  ///
  /// In zh, this message translates to:
  /// **'确定'**
  String get commonConfirm;

  /// No description provided for @commonUndo.
  ///
  /// In zh, this message translates to:
  /// **'撤销'**
  String get commonUndo;

  /// No description provided for @forwardPickSession.
  ///
  /// In zh, this message translates to:
  /// **'选择要转发到的会话'**
  String get forwardPickSession;

  /// No description provided for @forwardNoTarget.
  ///
  /// In zh, this message translates to:
  /// **'没有可转发的好友或群'**
  String get forwardNoTarget;

  /// No description provided for @deleteLocalConfirmTitle.
  ///
  /// In zh, this message translates to:
  /// **'在本机删除消息？'**
  String get deleteLocalConfirmTitle;

  /// No description provided for @deleteLocalConfirmBody.
  ///
  /// In zh, this message translates to:
  /// **'只影响本机记录，对方和其他设备仍能看到这条消息。'**
  String get deleteLocalConfirmBody;

  /// No description provided for @quotePrefix.
  ///
  /// In zh, this message translates to:
  /// **'引用'**
  String get quotePrefix;

  /// No description provided for @voiceMessage.
  ///
  /// In zh, this message translates to:
  /// **'语音'**
  String get voiceMessage;

  /// No description provided for @typingIndicator.
  ///
  /// In zh, this message translates to:
  /// **'对方正在输入…'**
  String get typingIndicator;
}

class _AppLocalizationsDelegate
    extends LocalizationsDelegate<AppLocalizations> {
  const _AppLocalizationsDelegate();

  @override
  Future<AppLocalizations> load(Locale locale) {
    return SynchronousFuture<AppLocalizations>(lookupAppLocalizations(locale));
  }

  @override
  bool isSupported(Locale locale) =>
      <String>['zh'].contains(locale.languageCode);

  @override
  bool shouldReload(_AppLocalizationsDelegate old) => false;
}

AppLocalizations lookupAppLocalizations(Locale locale) {
  // Lookup logic when only language code is specified.
  switch (locale.languageCode) {
    case 'zh':
      return AppLocalizationsZh();
  }

  throw FlutterError(
    'AppLocalizations.delegate failed to load unsupported locale "$locale". This is likely '
    'an issue with the localizations generation tool. Please file an issue '
    'on GitHub with a reproducible sample app and the gen-l10n configuration '
    'that was used.',
  );
}
