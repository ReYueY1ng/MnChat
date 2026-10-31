import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:intl/intl.dart' as intl;

import 'app_localizations_en.dart';
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
  static const List<Locale> supportedLocales = <Locale>[
    Locale('en'),
    Locale('zh'),
  ];

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

  /// No description provided for @accountMenuChooseMembersOptional.
  ///
  /// In zh, this message translates to:
  /// **'选择成员（可选）'**
  String get accountMenuChooseMembersOptional;

  /// No description provided for @accountMenuCreate.
  ///
  /// In zh, this message translates to:
  /// **'创建'**
  String get accountMenuCreate;

  /// No description provided for @accountMenuCreateGroup.
  ///
  /// In zh, this message translates to:
  /// **'创建群'**
  String get accountMenuCreateGroup;

  /// No description provided for @accountMenuEnterGroupName.
  ///
  /// In zh, this message translates to:
  /// **'输入群名称'**
  String get accountMenuEnterGroupName;

  /// No description provided for @accountMenuEnterGroupName2.
  ///
  /// In zh, this message translates to:
  /// **'请输入群名称'**
  String get accountMenuEnterGroupName2;

  /// No description provided for @accountMenuFailedCreate.
  ///
  /// In zh, this message translates to:
  /// **'创建失败: {e}'**
  String accountMenuFailedCreate(Object e);

  /// No description provided for @accountMenuFailedCreateRet.
  ///
  /// In zh, this message translates to:
  /// **'创建失败: ret={ret}'**
  String accountMenuFailedCreateRet(Object ret);

  /// No description provided for @accountMenuGroupCreated.
  ///
  /// In zh, this message translates to:
  /// **'群已创建'**
  String get accountMenuGroupCreated;

  /// No description provided for @accountMenuMenu.
  ///
  /// In zh, this message translates to:
  /// **'菜单'**
  String get accountMenuMenu;

  /// No description provided for @accountMenuMyProfile.
  ///
  /// In zh, this message translates to:
  /// **'我的资料'**
  String get accountMenuMyProfile;

  /// No description provided for @accountMenuRefreshConversations.
  ///
  /// In zh, this message translates to:
  /// **'刷新会话'**
  String get accountMenuRefreshConversations;

  /// No description provided for @accountMenuSwitchAccount.
  ///
  /// In zh, this message translates to:
  /// **'切换账号'**
  String get accountMenuSwitchAccount;

  /// No description provided for @avatarEditAvatar.
  ///
  /// In zh, this message translates to:
  /// **'头像'**
  String get avatarEditAvatar;

  /// No description provided for @avatarEditAvatarInfoMissingTry.
  ///
  /// In zh, this message translates to:
  /// **'头像信息缺失，请稍后重试'**
  String get avatarEditAvatarInfoMissingTry;

  /// No description provided for @avatarEditAvatarUpdated.
  ///
  /// In zh, this message translates to:
  /// **'头像已更新'**
  String get avatarEditAvatarUpdated;

  /// No description provided for @avatarEditChooseCustomAvatar.
  ///
  /// In zh, this message translates to:
  /// **'选择自定义头像'**
  String get avatarEditChooseCustomAvatar;

  /// No description provided for @avatarEditConfirmChange.
  ///
  /// In zh, this message translates to:
  /// **'确认修改'**
  String get avatarEditConfirmChange;

  /// No description provided for @avatarEditCost.
  ///
  /// In zh, this message translates to:
  /// **'消耗'**
  String get avatarEditCost;

  /// No description provided for @avatarEditCustom.
  ///
  /// In zh, this message translates to:
  /// **'自定义'**
  String get avatarEditCustom;

  /// No description provided for @avatarEditDeveloper.
  ///
  /// In zh, this message translates to:
  /// **'开发者'**
  String get avatarEditDeveloper;

  /// No description provided for @avatarEditDisplayedFamilyUpdated.
  ///
  /// In zh, this message translates to:
  /// **'展示家族已更新'**
  String get avatarEditDisplayedFamilyUpdated;

  /// No description provided for @avatarEditEnterNewName.
  ///
  /// In zh, this message translates to:
  /// **'输入修改的名字'**
  String get avatarEditEnterNewName;

  /// No description provided for @avatarEditFailedChangeName.
  ///
  /// In zh, this message translates to:
  /// **'改名失败：{e}'**
  String avatarEditFailedChangeName(Object e);

  /// No description provided for @avatarEditFailedEquip.
  ///
  /// In zh, this message translates to:
  /// **'佩戴失败：{e}'**
  String avatarEditFailedEquip(Object e);

  /// No description provided for @avatarEditFailedEquipTryAgain.
  ///
  /// In zh, this message translates to:
  /// **'佩戴失败，请稍后重试'**
  String get avatarEditFailedEquipTryAgain;

  /// No description provided for @avatarEditFailedLoadFamilyList.
  ///
  /// In zh, this message translates to:
  /// **'家族列表加载失败'**
  String get avatarEditFailedLoadFamilyList;

  /// No description provided for @avatarEditFailedLoadTitleList.
  ///
  /// In zh, this message translates to:
  /// **'称号列表加载失败'**
  String get avatarEditFailedLoadTitleList;

  /// No description provided for @avatarEditFailedPinTryAgain.
  ///
  /// In zh, this message translates to:
  /// **'置顶失败，请稍后重试'**
  String get avatarEditFailedPinTryAgain;

  /// No description provided for @avatarEditFailedSet.
  ///
  /// In zh, this message translates to:
  /// **'设置失败：{e}'**
  String avatarEditFailedSet(Object e);

  /// No description provided for @avatarEditFailedSetTryAgain.
  ///
  /// In zh, this message translates to:
  /// **'设置失败，请稍后重试'**
  String get avatarEditFailedSetTryAgain;

  /// No description provided for @avatarEditFailedSwitch.
  ///
  /// In zh, this message translates to:
  /// **'切换失败：{e}'**
  String avatarEditFailedSwitch(Object e);

  /// No description provided for @avatarEditFailedSwitchTryAgain.
  ///
  /// In zh, this message translates to:
  /// **'切换失败，请稍后重试'**
  String get avatarEditFailedSwitchTryAgain;

  /// No description provided for @avatarEditFailedUnpinTryAgain.
  ///
  /// In zh, this message translates to:
  /// **'取消置顶失败，请稍后重试'**
  String get avatarEditFailedUnpinTryAgain;

  /// No description provided for @avatarEditFreeMembers.
  ///
  /// In zh, this message translates to:
  /// **'会员免费'**
  String get avatarEditFreeMembers;

  /// No description provided for @avatarEditInUse.
  ///
  /// In zh, this message translates to:
  /// **'使用中'**
  String get avatarEditInUse;

  /// No description provided for @avatarEditMiniSeason.
  ///
  /// In zh, this message translates to:
  /// **'迷你季'**
  String get avatarEditMiniSeason;

  /// No description provided for @avatarEditMount.
  ///
  /// In zh, this message translates to:
  /// **'坐骑'**
  String get avatarEditMount;

  /// No description provided for @avatarEditNameChanged.
  ///
  /// In zh, this message translates to:
  /// **'改名成功'**
  String get avatarEditNameChanged;

  /// No description provided for @avatarEditNickname.
  ///
  /// In zh, this message translates to:
  /// **'昵称'**
  String get avatarEditNickname;

  /// No description provided for @avatarEditNoTitlesCategory.
  ///
  /// In zh, this message translates to:
  /// **'该分类下暂无称号'**
  String get avatarEditNoTitlesCategory;

  /// No description provided for @avatarEditOperationFailed.
  ///
  /// In zh, this message translates to:
  /// **'操作失败：{e}'**
  String avatarEditOperationFailed(Object e);

  /// No description provided for @avatarEditOutfit.
  ///
  /// In zh, this message translates to:
  /// **'装扮'**
  String get avatarEditOutfit;

  /// No description provided for @avatarEditPersonality.
  ///
  /// In zh, this message translates to:
  /// **'个性'**
  String get avatarEditPersonality;

  /// No description provided for @avatarEditPleaseDontUploadImages.
  ///
  /// In zh, this message translates to:
  /// **'请勿上传包含恐怖、反动等不良元素的图片哦'**
  String get avatarEditPleaseDontUploadImages;

  /// No description provided for @avatarEditRenameCostReviewDecided.
  ///
  /// In zh, this message translates to:
  /// **'改名消耗与审核由服务端裁决'**
  String get avatarEditRenameCostReviewDecided;

  /// No description provided for @avatarEditReviewFailed.
  ///
  /// In zh, this message translates to:
  /// **'审核失败'**
  String get avatarEditReviewFailed;

  /// No description provided for @avatarEditSelectedSwitchAutomaticallyAfter.
  ///
  /// In zh, this message translates to:
  /// **'已使用，审核通过后自动替换'**
  String get avatarEditSelectedSwitchAutomaticallyAfter;

  /// No description provided for @avatarEditThisExternalClientHasnt.
  ///
  /// In zh, this message translates to:
  /// **'外部客户端暂未获取坐骑头像列表'**
  String get avatarEditThisExternalClientHasnt;

  /// No description provided for @avatarEditThisImageViolatesRules.
  ///
  /// In zh, this message translates to:
  /// **'当前图片违规无法使用'**
  String get avatarEditThisImageViolatesRules;

  /// No description provided for @avatarEditTitleCategoryConfigFetched.
  ///
  /// In zh, this message translates to:
  /// **'称号分类配置未获取，暂无法按分类筛选'**
  String get avatarEditTitleCategoryConfigFetched;

  /// No description provided for @avatarEditTitleEquipped.
  ///
  /// In zh, this message translates to:
  /// **'称号已佩戴'**
  String get avatarEditTitleEquipped;

  /// No description provided for @avatarEditUnderReview.
  ///
  /// In zh, this message translates to:
  /// **'审核中'**
  String get avatarEditUnderReview;

  /// No description provided for @avatarEditUploadFailed.
  ///
  /// In zh, this message translates to:
  /// **'上传失败：{e}'**
  String avatarEditUploadFailed(Object e);

  /// No description provided for @avatarEditUploadFailedTryAgain.
  ///
  /// In zh, this message translates to:
  /// **'上传失败，请稍后重试'**
  String get avatarEditUploadFailedTryAgain;

  /// No description provided for @avatarEditUploadedPendingReview.
  ///
  /// In zh, this message translates to:
  /// **'上传成功，等待审核'**
  String get avatarEditUploadedPendingReview;

  /// No description provided for @avatarEditValidUntil.
  ///
  /// In zh, this message translates to:
  /// **'有效期'**
  String get avatarEditValidUntil;

  /// No description provided for @badgesPremiumMember.
  ///
  /// In zh, this message translates to:
  /// **'大会员'**
  String get badgesPremiumMember;

  /// No description provided for @badgesRapport.
  ///
  /// In zh, this message translates to:
  /// **'默契度 · {p1}'**
  String badgesRapport(Object p1);

  /// No description provided for @badgesRapport2.
  ///
  /// In zh, this message translates to:
  /// **'默契度 · {p1}（{tacitnum}/{next}）'**
  String badgesRapport2(Object next, Object p1, Object tacitnum);

  /// No description provided for @blocklistAdd.
  ///
  /// In zh, this message translates to:
  /// **'加入黑名单'**
  String get blocklistAdd;

  /// No description provided for @blocklistAdded.
  ///
  /// In zh, this message translates to:
  /// **'已加入黑名单'**
  String get blocklistAdded;

  /// No description provided for @blocklistClear.
  ///
  /// In zh, this message translates to:
  /// **'清空'**
  String get blocklistClear;

  /// No description provided for @blocklistClearAll.
  ///
  /// In zh, this message translates to:
  /// **'清空黑名单'**
  String get blocklistClearAll;

  /// No description provided for @blocklistCleared.
  ///
  /// In zh, this message translates to:
  /// **'已清空'**
  String get blocklistCleared;

  /// No description provided for @blocklistEmpty.
  ///
  /// In zh, this message translates to:
  /// **'暂无黑名单好友'**
  String get blocklistEmpty;

  /// No description provided for @blocklistEnterMiniIdToBlock.
  ///
  /// In zh, this message translates to:
  /// **'输入要拉黑的迷你号'**
  String get blocklistEnterMiniIdToBlock;

  /// No description provided for @blocklistFailedClear.
  ///
  /// In zh, this message translates to:
  /// **'清空失败: {e}'**
  String blocklistFailedClear(Object e);

  /// No description provided for @blocklistMiniId.
  ///
  /// In zh, this message translates to:
  /// **'迷你号 {p1}'**
  String blocklistMiniId(Object p1);

  /// No description provided for @blocklistMiniIdUin.
  ///
  /// In zh, this message translates to:
  /// **'迷你号 (Uin)'**
  String get blocklistMiniIdUin;

  /// No description provided for @blocklistRemove.
  ///
  /// In zh, this message translates to:
  /// **'移出黑名单'**
  String get blocklistRemove;

  /// No description provided for @blocklistRemoveAllFriends.
  ///
  /// In zh, this message translates to:
  /// **'确定移出黑名单中的全部好友吗？'**
  String get blocklistRemoveAllFriends;

  /// No description provided for @blocklistRemoved.
  ///
  /// In zh, this message translates to:
  /// **'已移出黑名单'**
  String get blocklistRemoved;

  /// No description provided for @bubbleBubble.
  ///
  /// In zh, this message translates to:
  /// **'气泡 #{p1}'**
  String bubbleBubble(Object p1);

  /// No description provided for @bubbleBubbleEquipped.
  ///
  /// In zh, this message translates to:
  /// **'已佩戴气泡 #{id}'**
  String bubbleBubbleEquipped(Object id);

  /// No description provided for @bubbleBubbleNamesStylesDefined.
  ///
  /// In zh, this message translates to:
  /// **'气泡名称/样式由游戏内置配置决定，外部客户端无法显示，'**
  String get bubbleBubbleNamesStylesDefined;

  /// No description provided for @bubbleBubbleUnequipped.
  ///
  /// In zh, this message translates to:
  /// **'已取消佩戴气泡'**
  String get bubbleBubbleUnequipped;

  /// No description provided for @bubbleChatBubble.
  ///
  /// In zh, this message translates to:
  /// **'聊天气泡'**
  String get bubbleChatBubble;

  /// No description provided for @bubbleExpired.
  ///
  /// In zh, this message translates to:
  /// **'已过期'**
  String get bubbleExpired;

  /// No description provided for @bubbleNoBubblesAvailableYet.
  ///
  /// In zh, this message translates to:
  /// **'还没有可用气泡'**
  String get bubbleNoBubblesAvailableYet;

  /// No description provided for @bubbleOnlyEquipSwitchingAvailable.
  ///
  /// In zh, this message translates to:
  /// **'仅能切换佩戴。'**
  String get bubbleOnlyEquipSwitchingAvailable;

  /// No description provided for @bubblePermanent.
  ///
  /// In zh, this message translates to:
  /// **'永久'**
  String get bubblePermanent;

  /// No description provided for @bubbleUnequip.
  ///
  /// In zh, this message translates to:
  /// **'取消佩戴'**
  String get bubbleUnequip;

  /// No description provided for @bubbleValidUntil.
  ///
  /// In zh, this message translates to:
  /// **'有效期至 {mo}-{dd}'**
  String bubbleValidUntil(Object dd, Object mo);

  /// No description provided for @chatAnimatedEmoji.
  ///
  /// In zh, this message translates to:
  /// **'动态表情'**
  String get chatAnimatedEmoji;

  /// No description provided for @chatAuthor.
  ///
  /// In zh, this message translates to:
  /// **'作者: {p1}'**
  String chatAuthor(Object p1);

  /// No description provided for @chatBack.
  ///
  /// In zh, this message translates to:
  /// **'返回'**
  String get chatBack;

  /// No description provided for @chatBackLatest.
  ///
  /// In zh, this message translates to:
  /// **'回到最新'**
  String get chatBackLatest;

  /// No description provided for @chatChooseAudioFile.
  ///
  /// In zh, this message translates to:
  /// **'选择音频文件'**
  String get chatChooseAudioFile;

  /// No description provided for @chatChooseImageSend.
  ///
  /// In zh, this message translates to:
  /// **'选择要发送的图片'**
  String get chatChooseImageSend;

  /// No description provided for @chatChooseVoiceFileSend.
  ///
  /// In zh, this message translates to:
  /// **'选择要发送的语音文件'**
  String get chatChooseVoiceFileSend;

  /// No description provided for @chatCopied.
  ///
  /// In zh, this message translates to:
  /// **'已复制 {p1} 条'**
  String chatCopied(Object p1);

  /// No description provided for @chatCopySelected.
  ///
  /// In zh, this message translates to:
  /// **'复制选中'**
  String get chatCopySelected;

  /// No description provided for @chatCouldntFetchGroupMember.
  ///
  /// In zh, this message translates to:
  /// **'还没拉到群成员名单，稍后再试'**
  String get chatCouldntFetchGroupMember;

  /// No description provided for @chatEmoji.
  ///
  /// In zh, this message translates to:
  /// **'表情'**
  String get chatEmoji;

  /// No description provided for @chatEnterKeywordsSearchChat.
  ///
  /// In zh, this message translates to:
  /// **'输入关键词搜索本会话消息'**
  String get chatEnterKeywordsSearchChat;

  /// No description provided for @chatExitSearch.
  ///
  /// In zh, this message translates to:
  /// **'退出搜索'**
  String get chatExitSearch;

  /// No description provided for @chatExportSelected.
  ///
  /// In zh, this message translates to:
  /// **'导出选中'**
  String get chatExportSelected;

  /// No description provided for @chatExportSelectedMessages.
  ///
  /// In zh, this message translates to:
  /// **'导出选中消息'**
  String get chatExportSelectedMessages;

  /// No description provided for @chatExported.
  ///
  /// In zh, this message translates to:
  /// **'已导出到 {path}'**
  String chatExported(Object path);

  /// No description provided for @chatFailedExport.
  ///
  /// In zh, this message translates to:
  /// **'导出失败：{e}'**
  String chatFailedExport(Object e);

  /// No description provided for @chatFailedForward.
  ///
  /// In zh, this message translates to:
  /// **'转发失败: {e}'**
  String chatFailedForward(Object e);

  /// No description provided for @chatFailedLoadMoments.
  ///
  /// In zh, this message translates to:
  /// **'动态加载失败: {e}'**
  String chatFailedLoadMoments(Object e);

  /// No description provided for @chatFailedReadImage.
  ///
  /// In zh, this message translates to:
  /// **'读取图片失败：{e}'**
  String chatFailedReadImage(Object e);

  /// No description provided for @chatFailedSend.
  ///
  /// In zh, this message translates to:
  /// **'发送失败: {e}'**
  String chatFailedSend(Object e);

  /// No description provided for @chatForwardChatHistory.
  ///
  /// In zh, this message translates to:
  /// **'转发聊天记录：\n{text}'**
  String chatForwardChatHistory(Object text);

  /// No description provided for @chatGift.
  ///
  /// In zh, this message translates to:
  /// **'礼物'**
  String get chatGift;

  /// No description provided for @chatGiftsSentFriendChats.
  ///
  /// In zh, this message translates to:
  /// **'礼物只能送给好友会话'**
  String get chatGiftsSentFriendChats;

  /// No description provided for @chatGreetingHi.
  ///
  /// In zh, this message translates to:
  /// **'嗨~'**
  String get chatGreetingHi;

  /// No description provided for @chatGroup.
  ///
  /// In zh, this message translates to:
  /// **'群'**
  String get chatGroup;

  /// No description provided for @chatGroupChat.
  ///
  /// In zh, this message translates to:
  /// **'群聊'**
  String get chatGroupChat;

  /// No description provided for @chatGroupDetails.
  ///
  /// In zh, this message translates to:
  /// **'群详情'**
  String get chatGroupDetails;

  /// No description provided for @chatGroupMembers.
  ///
  /// In zh, this message translates to:
  /// **'@群成员'**
  String get chatGroupMembers;

  /// No description provided for @chatImage.
  ///
  /// In zh, this message translates to:
  /// **'图片'**
  String get chatImage;

  /// No description provided for @chatImageUploadFailedTry.
  ///
  /// In zh, this message translates to:
  /// **'图片上传失败，请稍后重试'**
  String get chatImageUploadFailedTry;

  /// No description provided for @chatInteractiveEmojiCurrentlyWork.
  ///
  /// In zh, this message translates to:
  /// **'互动表情暂仅支持好友会话'**
  String get chatInteractiveEmojiCurrentlyWork;

  /// No description provided for @chatInvitesYouPlayFound.
  ///
  /// In zh, this message translates to:
  /// **'邀请你一起玩 · 发现一个好玩的地图，快来一起吧'**
  String get chatInvitesYouPlayFound;

  /// No description provided for @chatInvitesYouPlayJoin.
  ///
  /// In zh, this message translates to:
  /// **'邀请你一起玩 · 需在游戏内加入房间'**
  String get chatInvitesYouPlayJoin;

  /// No description provided for @chatJoinGame.
  ///
  /// In zh, this message translates to:
  /// **'（需在游戏内加入）'**
  String get chatJoinGame;

  /// No description provided for @chatJoinRoomGame.
  ///
  /// In zh, this message translates to:
  /// **'房间需在游戏内加入'**
  String get chatJoinRoomGame;

  /// No description provided for @chatJumpDate.
  ///
  /// In zh, this message translates to:
  /// **'跳到某一天'**
  String get chatJumpDate;

  /// No description provided for @chatLetsPlayTogether.
  ///
  /// In zh, this message translates to:
  /// **'一起来玩呀'**
  String get chatLetsPlayTogether;

  /// No description provided for @chatLoadEarlier.
  ///
  /// In zh, this message translates to:
  /// **'加载更早'**
  String get chatLoadEarlier;

  /// No description provided for @chatLoading.
  ///
  /// In zh, this message translates to:
  /// **'加载中…'**
  String get chatLoading;

  /// No description provided for @chatMap.
  ///
  /// In zh, this message translates to:
  /// **'地图'**
  String get chatMap;

  /// No description provided for @chatMapShare.
  ///
  /// In zh, this message translates to:
  /// **'地图分享'**
  String get chatMapShare;

  /// No description provided for @chatMe.
  ///
  /// In zh, this message translates to:
  /// **'我'**
  String get chatMe;

  /// No description provided for @chatMessagesISent.
  ///
  /// In zh, this message translates to:
  /// **'我发出的消息'**
  String get chatMessagesISent;

  /// No description provided for @chatMessagesNotSent.
  ///
  /// In zh, this message translates to:
  /// **'{count} 条消息未发送'**
  String chatMessagesNotSent(Object count);

  /// No description provided for @chatMiniID.
  ///
  /// In zh, this message translates to:
  /// **'迷你号 {p1}'**
  String chatMiniID(Object p1);

  /// No description provided for @chatNewMessagesBelow.
  ///
  /// In zh, this message translates to:
  /// **'以下为新消息'**
  String get chatNewMessagesBelow;

  /// No description provided for @chatNoEarlierChatHistory.
  ///
  /// In zh, this message translates to:
  /// **'没有更早的聊天记录了'**
  String get chatNoEarlierChatHistory;

  /// No description provided for @chatNoImageFilePath.
  ///
  /// In zh, this message translates to:
  /// **'剪贴板里没有图片文件路径'**
  String get chatNoImageFilePath;

  /// No description provided for @chatNoMatchingMembers.
  ///
  /// In zh, this message translates to:
  /// **'没有匹配的成员'**
  String get chatNoMatchingMembers;

  /// No description provided for @chatNoMessagesAroundDate.
  ///
  /// In zh, this message translates to:
  /// **'这一天附近没有消息'**
  String get chatNoMessagesAroundDate;

  /// No description provided for @chatNoMessagesYetSay.
  ///
  /// In zh, this message translates to:
  /// **'暂无消息，打个招呼吧 👋'**
  String get chatNoMessagesYetSay;

  /// No description provided for @chatNoTextContent.
  ///
  /// In zh, this message translates to:
  /// **'（无文本内容）'**
  String get chatNoTextContent;

  /// No description provided for @chatOlderChatHistoryStored.
  ///
  /// In zh, this message translates to:
  /// **'本地还存有更早的聊天记录'**
  String get chatOlderChatHistoryStored;

  /// No description provided for @chatOpenMapGame.
  ///
  /// In zh, this message translates to:
  /// **'地图需在游戏内打开'**
  String get chatOpenMapGame;

  /// No description provided for @chatPasteImage.
  ///
  /// In zh, this message translates to:
  /// **'粘贴图片'**
  String get chatPasteImage;

  /// No description provided for @chatRapport.
  ///
  /// In zh, this message translates to:
  /// **'默契度 +{p1}'**
  String chatRapport(Object p1);

  /// No description provided for @chatRapportGift.
  ///
  /// In zh, this message translates to:
  /// **'默契礼物'**
  String get chatRapportGift;

  /// No description provided for @chatRecord.
  ///
  /// In zh, this message translates to:
  /// **'录音'**
  String get chatRecord;

  /// No description provided for @chatRecordMicrophoneNow.
  ///
  /// In zh, this message translates to:
  /// **'现在用麦克风录一段'**
  String get chatRecordMicrophoneNow;

  /// No description provided for @chatRedPacketsMustClaimed.
  ///
  /// In zh, this message translates to:
  /// **'红包需在游戏内领取'**
  String get chatRedPacketsMustClaimed;

  /// No description provided for @chatResent.
  ///
  /// In zh, this message translates to:
  /// **'已重发 {sent} 条'**
  String chatResent(Object sent);

  /// No description provided for @chatRoom.
  ///
  /// In zh, this message translates to:
  /// **'房间'**
  String get chatRoom;

  /// No description provided for @chatRoomInvite.
  ///
  /// In zh, this message translates to:
  /// **'房间邀请'**
  String get chatRoomInvite;

  /// No description provided for @chatRoomWithName.
  ///
  /// In zh, this message translates to:
  /// **'房间: {p1}'**
  String chatRoomWithName(Object p1);

  /// No description provided for @chatSayHello.
  ///
  /// In zh, this message translates to:
  /// **'打个招呼'**
  String get chatSayHello;

  /// No description provided for @chatSearchChat.
  ///
  /// In zh, this message translates to:
  /// **'搜索本会话消息'**
  String get chatSearchChat;

  /// No description provided for @chatSearchGroupMembers.
  ///
  /// In zh, this message translates to:
  /// **'搜索群成员'**
  String get chatSearchGroupMembers;

  /// No description provided for @chatSearchMessages.
  ///
  /// In zh, this message translates to:
  /// **'搜索消息'**
  String get chatSearchMessages;

  /// No description provided for @chatSelected.
  ///
  /// In zh, this message translates to:
  /// **'已选 {p1} 条'**
  String chatSelected(Object p1);

  /// No description provided for @chatSendFirstMessageStart.
  ///
  /// In zh, this message translates to:
  /// **'发送第一条消息，开启你们的冒险'**
  String get chatSendFirstMessageStart;

  /// No description provided for @chatStillSentTryAgain.
  ///
  /// In zh, this message translates to:
  /// **'仍未发送成功，稍后再试'**
  String get chatStillSentTryAgain;

  /// No description provided for @chatTheirMessages.
  ///
  /// In zh, this message translates to:
  /// **'对方的消息'**
  String get chatTheirMessages;

  /// No description provided for @chatThem.
  ///
  /// In zh, this message translates to:
  /// **'对方'**
  String get chatThem;

  /// No description provided for @chatThisMessageTextForward.
  ///
  /// In zh, this message translates to:
  /// **'这条消息没有可转发的文本'**
  String get chatThisMessageTextForward;

  /// No description provided for @chatThisMessageTextResend.
  ///
  /// In zh, this message translates to:
  /// **'这条消息没有可重发的文本'**
  String get chatThisMessageTextResend;

  /// No description provided for @chatTypeMessage.
  ///
  /// In zh, this message translates to:
  /// **'输入消息…'**
  String get chatTypeMessage;

  /// No description provided for @chatViewingHistory.
  ///
  /// In zh, this message translates to:
  /// **'正在查看 {p1}-{p2}-{p3} 的历史'**
  String chatViewingHistory(Object p1, Object p2, Object p3);

  /// No description provided for @chatVoice.
  ///
  /// In zh, this message translates to:
  /// **'[语音] {p1}'**
  String chatVoice(Object p1);

  /// No description provided for @chatVoiceShort.
  ///
  /// In zh, this message translates to:
  /// **'[语音]'**
  String get chatVoiceShort;

  /// No description provided for @chatVoiceUploadFailedTry.
  ///
  /// In zh, this message translates to:
  /// **'语音上传失败，请稍后重试'**
  String get chatVoiceUploadFailedTry;

  /// No description provided for @chatWhatYouUp.
  ///
  /// In zh, this message translates to:
  /// **'在干嘛'**
  String get chatWhatYouUp;

  /// No description provided for @commonBestPartners.
  ///
  /// In zh, this message translates to:
  /// **'最佳拍档'**
  String get commonBestPartners;

  /// No description provided for @commonConversations.
  ///
  /// In zh, this message translates to:
  /// **'会话'**
  String get commonConversations;

  /// No description provided for @commonFailedLoad.
  ///
  /// In zh, this message translates to:
  /// **'加载失败：{_error}'**
  String commonFailedLoad(Object _error);

  /// No description provided for @commonFailedLoad2.
  ///
  /// In zh, this message translates to:
  /// **'加载失败: {e}'**
  String commonFailedLoad2(Object e);

  /// No description provided for @commonFamily.
  ///
  /// In zh, this message translates to:
  /// **'家族'**
  String get commonFamily;

  /// No description provided for @commonFollowed.
  ///
  /// In zh, this message translates to:
  /// **'已关注'**
  String get commonFollowed;

  /// No description provided for @commonFollowing.
  ///
  /// In zh, this message translates to:
  /// **'关注'**
  String get commonFollowing;

  /// No description provided for @commonFriend.
  ///
  /// In zh, this message translates to:
  /// **'好友'**
  String get commonFriend;

  /// No description provided for @commonMiniID.
  ///
  /// In zh, this message translates to:
  /// **'迷你号 {p1}'**
  String commonMiniID(Object p1);

  /// No description provided for @commonMiniID2.
  ///
  /// In zh, this message translates to:
  /// **'迷你号 {uin}'**
  String commonMiniID2(Object uin);

  /// No description provided for @commonNotSignedIn.
  ///
  /// In zh, this message translates to:
  /// **'未登录'**
  String get commonNotSignedIn;

  /// No description provided for @commonOperationFailed.
  ///
  /// In zh, this message translates to:
  /// **'操作失败: {e}'**
  String commonOperationFailed(Object e);

  /// No description provided for @commonPin.
  ///
  /// In zh, this message translates to:
  /// **'置顶'**
  String get commonPin;

  /// No description provided for @commonPinned.
  ///
  /// In zh, this message translates to:
  /// **'已置顶'**
  String get commonPinned;

  /// No description provided for @commonRefresh.
  ///
  /// In zh, this message translates to:
  /// **'刷新'**
  String get commonRefresh;

  /// No description provided for @commonRetry.
  ///
  /// In zh, this message translates to:
  /// **'重试'**
  String get commonRetry;

  /// No description provided for @commonUnpin.
  ///
  /// In zh, this message translates to:
  /// **'取消置顶'**
  String get commonUnpin;

  /// No description provided for @commonUnpinned.
  ///
  /// In zh, this message translates to:
  /// **'已取消置顶'**
  String get commonUnpinned;

  /// No description provided for @dataCanceled.
  ///
  /// In zh, this message translates to:
  /// **'已取消'**
  String get dataCanceled;

  /// No description provided for @dataChatHistory.
  ///
  /// In zh, this message translates to:
  /// **'聊天记录'**
  String get dataChatHistory;

  /// No description provided for @dataChatsFriends.
  ///
  /// In zh, this message translates to:
  /// **'会话 {p1} 个，好友 {p2} 个'**
  String dataChatsFriends(Object p1, Object p2);

  /// No description provided for @dataChooseChatHistoryBackup.
  ///
  /// In zh, this message translates to:
  /// **'选择聊天记录备份文件'**
  String get dataChooseChatHistoryBackup;

  /// No description provided for @dataCounting.
  ///
  /// In zh, this message translates to:
  /// **'统计中…'**
  String get dataCounting;

  /// No description provided for @dataExistingRecordsSkippedAutomatically.
  ///
  /// In zh, this message translates to:
  /// **'已存在的记录会自动跳过，不会删除或覆盖本地数据。是否继续？'**
  String get dataExistingRecordsSkippedAutomatically;

  /// No description provided for @dataExportChatHistory.
  ///
  /// In zh, this message translates to:
  /// **'导出聊天记录'**
  String get dataExportChatHistory;

  /// No description provided for @dataExportCurrentAccountsMessages.
  ///
  /// In zh, this message translates to:
  /// **'把当前账号的消息 / 会话 / 好友导出为 JSON 文件'**
  String get dataExportCurrentAccountsMessages;

  /// No description provided for @dataImport.
  ///
  /// In zh, this message translates to:
  /// **'导入'**
  String get dataImport;

  /// No description provided for @dataImportChatHistory.
  ///
  /// In zh, this message translates to:
  /// **'导入聊天记录'**
  String get dataImportChatHistory;

  /// No description provided for @dataImportCompleteMessages.
  ///
  /// In zh, this message translates to:
  /// **'导入完成：消息 {p1} 条，'**
  String dataImportCompleteMessages(Object p1);

  /// No description provided for @dataImportFailed.
  ///
  /// In zh, this message translates to:
  /// **'导入失败：{e}'**
  String dataImportFailed(Object e);

  /// No description provided for @dataLocalData.
  ///
  /// In zh, this message translates to:
  /// **'本地数据'**
  String get dataLocalData;

  /// No description provided for @dataMergeImportJSONBackup.
  ///
  /// In zh, this message translates to:
  /// **'从 JSON 备份文件合并导入（自动跳过已存在的记录）'**
  String get dataMergeImportJSONBackup;

  /// No description provided for @dataMessagesChats.
  ///
  /// In zh, this message translates to:
  /// **'共 {_messageCount} 条消息 · {_sessionCount} 个会话'**
  String dataMessagesChats(Object _messageCount, Object _sessionCount);

  /// No description provided for @dataMessagesChatsFriendsBackup.
  ///
  /// In zh, this message translates to:
  /// **'将把备份文件中的消息 / 会话 / 好友合并到当前账号，'**
  String get dataMessagesChatsFriendsBackup;

  /// No description provided for @dataSignBeforeExporting.
  ///
  /// In zh, this message translates to:
  /// **'请先登录后再导出'**
  String get dataSignBeforeExporting;

  /// No description provided for @dynamicsAuthorMoments.
  ///
  /// In zh, this message translates to:
  /// **'{p1} 的动态'**
  String dynamicsAuthorMoments(Object p1);

  /// No description provided for @dynamicsCardAuthor.
  ///
  /// In zh, this message translates to:
  /// **'作者 {p1}'**
  String dynamicsCardAuthor(Object p1);

  /// No description provided for @dynamicsCardEnded.
  ///
  /// In zh, this message translates to:
  /// **'已结束'**
  String get dynamicsCardEnded;

  /// No description provided for @dynamicsCardFailedForward.
  ///
  /// In zh, this message translates to:
  /// **'转发失败'**
  String get dynamicsCardFailedForward;

  /// No description provided for @dynamicsCardForwardedFriend.
  ///
  /// In zh, this message translates to:
  /// **'已转发给好友'**
  String get dynamicsCardForwardedFriend;

  /// No description provided for @dynamicsCardGiveaway.
  ///
  /// In zh, this message translates to:
  /// **'抽奖'**
  String get dynamicsCardGiveaway;

  /// No description provided for @dynamicsCardGiveawayLoading.
  ///
  /// In zh, this message translates to:
  /// **'抽奖（加载中）'**
  String get dynamicsCardGiveawayLoading;

  /// No description provided for @dynamicsCardNoFriendsShare.
  ///
  /// In zh, this message translates to:
  /// **'还没有好友可以分享'**
  String get dynamicsCardNoFriendsShare;

  /// No description provided for @dynamicsCardOngoing.
  ///
  /// In zh, this message translates to:
  /// **'进行中'**
  String get dynamicsCardOngoing;

  /// No description provided for @dynamicsCardOpenWorkMap.
  ///
  /// In zh, this message translates to:
  /// **'打开作品/地图：{p1}'**
  String dynamicsCardOpenWorkMap(Object p1);

  /// No description provided for @dynamicsCardOperationFailedTryAgain.
  ///
  /// In zh, this message translates to:
  /// **'操作失败，请稍后重试'**
  String get dynamicsCardOperationFailedTryAgain;

  /// No description provided for @dynamicsCardParticipants.
  ///
  /// In zh, this message translates to:
  /// **'参与 {p1} 人'**
  String dynamicsCardParticipants(Object p1);

  /// No description provided for @dynamicsCardPrizeX.
  ///
  /// In zh, this message translates to:
  /// **'奖品 ×{p1}'**
  String dynamicsCardPrizeX(Object p1);

  /// No description provided for @dynamicsCardViewFullText.
  ///
  /// In zh, this message translates to:
  /// **'查看全文'**
  String get dynamicsCardViewFullText;

  /// No description provided for @dynamicsCardVoteLoading.
  ///
  /// In zh, this message translates to:
  /// **'投票（加载中）'**
  String get dynamicsCardVoteLoading;

  /// No description provided for @dynamicsCardWinners.
  ///
  /// In zh, this message translates to:
  /// **'开奖 {p1} 人'**
  String dynamicsCardWinners(Object p1);

  /// No description provided for @dynamicsCategory.
  ///
  /// In zh, this message translates to:
  /// **'分类{p1}'**
  String dynamicsCategory(Object p1);

  /// No description provided for @dynamicsDetailChangeVisibility.
  ///
  /// In zh, this message translates to:
  /// **'改可见范围'**
  String get dynamicsDetailChangeVisibility;

  /// No description provided for @dynamicsDetailChanged.
  ///
  /// In zh, this message translates to:
  /// **'已改为「{p1}」'**
  String dynamicsDetailChanged(Object p1);

  /// No description provided for @dynamicsDetailCollapseReplies.
  ///
  /// In zh, this message translates to:
  /// **'收起回复'**
  String get dynamicsDetailCollapseReplies;

  /// No description provided for @dynamicsDetailCommentActions.
  ///
  /// In zh, this message translates to:
  /// **'评论操作'**
  String get dynamicsDetailCommentActions;

  /// No description provided for @dynamicsDetailCommentPosted.
  ///
  /// In zh, this message translates to:
  /// **'评论已发布'**
  String get dynamicsDetailCommentPosted;

  /// No description provided for @dynamicsDetailComments.
  ///
  /// In zh, this message translates to:
  /// **'共{p1}条评论'**
  String dynamicsDetailComments(Object p1);

  /// No description provided for @dynamicsDetailDAgo.
  ///
  /// In zh, this message translates to:
  /// **'{p1}天前'**
  String dynamicsDetailDAgo(Object p1);

  /// No description provided for @dynamicsDetailDefault.
  ///
  /// In zh, this message translates to:
  /// **'默认'**
  String get dynamicsDetailDefault;

  /// No description provided for @dynamicsDetailDeleteComment.
  ///
  /// In zh, this message translates to:
  /// **'删除评论'**
  String get dynamicsDetailDeleteComment;

  /// No description provided for @dynamicsDetailDeleteComment2.
  ///
  /// In zh, this message translates to:
  /// **'确定删除这条评论吗？'**
  String get dynamicsDetailDeleteComment2;

  /// No description provided for @dynamicsDetailDeleteFailed.
  ///
  /// In zh, this message translates to:
  /// **'删除失败'**
  String get dynamicsDetailDeleteFailed;

  /// No description provided for @dynamicsDetailDeleteFailed2.
  ///
  /// In zh, this message translates to:
  /// **'删除失败: {e}'**
  String dynamicsDetailDeleteFailed2(Object e);

  /// No description provided for @dynamicsDetailDeleteMoment.
  ///
  /// In zh, this message translates to:
  /// **'删除动态'**
  String get dynamicsDetailDeleteMoment;

  /// No description provided for @dynamicsDetailDeleteReply.
  ///
  /// In zh, this message translates to:
  /// **'删除回复'**
  String get dynamicsDetailDeleteReply;

  /// No description provided for @dynamicsDetailDeleteReply2.
  ///
  /// In zh, this message translates to:
  /// **'确定删除这条回复吗？'**
  String get dynamicsDetailDeleteReply2;

  /// No description provided for @dynamicsDetailDeleted.
  ///
  /// In zh, this message translates to:
  /// **'已删除'**
  String get dynamicsDetailDeleted;

  /// No description provided for @dynamicsDetailFailedLoadVoteInfo.
  ///
  /// In zh, this message translates to:
  /// **'投票信息加载失败'**
  String get dynamicsDetailFailedLoadVoteInfo;

  /// No description provided for @dynamicsDetailFailedPublish.
  ///
  /// In zh, this message translates to:
  /// **'发布失败'**
  String get dynamicsDetailFailedPublish;

  /// No description provided for @dynamicsDetailFailedPublish2.
  ///
  /// In zh, this message translates to:
  /// **'发布失败: {e}'**
  String dynamicsDetailFailedPublish2(Object e);

  /// No description provided for @dynamicsDetailFailedShare.
  ///
  /// In zh, this message translates to:
  /// **'分享失败: {e}'**
  String dynamicsDetailFailedShare(Object e);

  /// No description provided for @dynamicsDetailGiveawayDetailsOngoing.
  ///
  /// In zh, this message translates to:
  /// **'抽奖详情（进行中）'**
  String get dynamicsDetailGiveawayDetailsOngoing;

  /// No description provided for @dynamicsDetailHrAgo.
  ///
  /// In zh, this message translates to:
  /// **'{p1}小时前'**
  String dynamicsDetailHrAgo(Object p1);

  /// No description provided for @dynamicsDetailJustNow.
  ///
  /// In zh, this message translates to:
  /// **'刚刚'**
  String get dynamicsDetailJustNow;

  /// No description provided for @dynamicsDetailLatest.
  ///
  /// In zh, this message translates to:
  /// **'最新'**
  String get dynamicsDetailLatest;

  /// No description provided for @dynamicsDetailLike.
  ///
  /// In zh, this message translates to:
  /// **'点赞'**
  String get dynamicsDetailLike;

  /// No description provided for @dynamicsDetailLoadMoreComments.
  ///
  /// In zh, this message translates to:
  /// **'加载更多评论'**
  String get dynamicsDetailLoadMoreComments;

  /// No description provided for @dynamicsDetailMinAgo.
  ///
  /// In zh, this message translates to:
  /// **'{p1}分钟前'**
  String dynamicsDetailMinAgo(Object p1);

  /// No description provided for @dynamicsDetailMoAgo.
  ///
  /// In zh, this message translates to:
  /// **'{p1}个月前'**
  String dynamicsDetailMoAgo(Object p1);

  /// No description provided for @dynamicsDetailMomentDeleted.
  ///
  /// In zh, this message translates to:
  /// **'动态已删除'**
  String get dynamicsDetailMomentDeleted;

  /// No description provided for @dynamicsDetailMomentDetails.
  ///
  /// In zh, this message translates to:
  /// **'动态详情'**
  String get dynamicsDetailMomentDetails;

  /// No description provided for @dynamicsDetailMomentManagement.
  ///
  /// In zh, this message translates to:
  /// **'动态管理'**
  String get dynamicsDetailMomentManagement;

  /// No description provided for @dynamicsDetailMultipleChoiceSubmitAfter.
  ///
  /// In zh, this message translates to:
  /// **'可多选，选好后提交'**
  String get dynamicsDetailMultipleChoiceSubmitAfter;

  /// No description provided for @dynamicsDetailNoCommentsYet.
  ///
  /// In zh, this message translates to:
  /// **'暂无评论'**
  String get dynamicsDetailNoCommentsYet;

  /// No description provided for @dynamicsDetailNoFriendsShare.
  ///
  /// In zh, this message translates to:
  /// **'暂无好友可分享'**
  String get dynamicsDetailNoFriendsShare;

  /// No description provided for @dynamicsDetailNoRepliesYet.
  ///
  /// In zh, this message translates to:
  /// **'暂无回复'**
  String get dynamicsDetailNoRepliesYet;

  /// No description provided for @dynamicsDetailOperationFailed.
  ///
  /// In zh, this message translates to:
  /// **'操作失败'**
  String get dynamicsDetailOperationFailed;

  /// No description provided for @dynamicsDetailOption.
  ///
  /// In zh, this message translates to:
  /// **'选项 {p1}'**
  String dynamicsDetailOption(Object p1);

  /// No description provided for @dynamicsDetailPublish.
  ///
  /// In zh, this message translates to:
  /// **'发布'**
  String get dynamicsDetailPublish;

  /// No description provided for @dynamicsDetailReplies.
  ///
  /// In zh, this message translates to:
  /// **'共{p1}条回复'**
  String dynamicsDetailReplies(Object p1);

  /// No description provided for @dynamicsDetailReply.
  ///
  /// In zh, this message translates to:
  /// **'回复'**
  String get dynamicsDetailReply;

  /// No description provided for @dynamicsDetailReply2.
  ///
  /// In zh, this message translates to:
  /// **'回复 {name}'**
  String dynamicsDetailReply2(Object name);

  /// No description provided for @dynamicsDetailReply3.
  ///
  /// In zh, this message translates to:
  /// **'回复 @{name}'**
  String dynamicsDetailReply3(Object name);

  /// No description provided for @dynamicsDetailReplyActions.
  ///
  /// In zh, this message translates to:
  /// **'回复操作'**
  String get dynamicsDetailReplyActions;

  /// No description provided for @dynamicsDetailReplyPosted.
  ///
  /// In zh, this message translates to:
  /// **'回复已发布'**
  String get dynamicsDetailReplyPosted;

  /// No description provided for @dynamicsDetailShareChat.
  ///
  /// In zh, this message translates to:
  /// **'分享到聊天'**
  String get dynamicsDetailShareChat;

  /// No description provided for @dynamicsDetailShareMoment.
  ///
  /// In zh, this message translates to:
  /// **'分享动态到…'**
  String get dynamicsDetailShareMoment;

  /// No description provided for @dynamicsDetailShared.
  ///
  /// In zh, this message translates to:
  /// **'已分享给 {picked}'**
  String dynamicsDetailShared(Object picked);

  /// No description provided for @dynamicsDetailSignVote.
  ///
  /// In zh, this message translates to:
  /// **'登录后可参与投票'**
  String get dynamicsDetailSignVote;

  /// No description provided for @dynamicsDetailSingleChoiceTapSubmit.
  ///
  /// In zh, this message translates to:
  /// **'单选，点选后提交'**
  String get dynamicsDetailSingleChoiceTapSubmit;

  /// No description provided for @dynamicsDetailSubmitting.
  ///
  /// In zh, this message translates to:
  /// **'提交中…'**
  String get dynamicsDetailSubmitting;

  /// No description provided for @dynamicsDetailTapWriteComment.
  ///
  /// In zh, this message translates to:
  /// **'点击写评论'**
  String get dynamicsDetailTapWriteComment;

  /// No description provided for @dynamicsDetailThisCannotUndoneDelete.
  ///
  /// In zh, this message translates to:
  /// **'删除后不可恢复，确定删除这条动态吗？'**
  String get dynamicsDetailThisCannotUndoneDelete;

  /// No description provided for @dynamicsDetailUnlike.
  ///
  /// In zh, this message translates to:
  /// **'取消点赞'**
  String get dynamicsDetailUnlike;

  /// No description provided for @dynamicsDetailVote.
  ///
  /// In zh, this message translates to:
  /// **'投票'**
  String get dynamicsDetailVote;

  /// No description provided for @dynamicsDetailVoteFailed.
  ///
  /// In zh, this message translates to:
  /// **'投票失败'**
  String get dynamicsDetailVoteFailed;

  /// No description provided for @dynamicsDetailVoteFailed2.
  ///
  /// In zh, this message translates to:
  /// **'投票失败: {e}'**
  String dynamicsDetailVoteFailed2(Object e);

  /// No description provided for @dynamicsDetailVotes.
  ///
  /// In zh, this message translates to:
  /// **'{p1}票'**
  String dynamicsDetailVotes(Object p1);

  /// No description provided for @dynamicsDetailWriteComment.
  ///
  /// In zh, this message translates to:
  /// **'写评论'**
  String get dynamicsDetailWriteComment;

  /// No description provided for @dynamicsDetailYrAgo.
  ///
  /// In zh, this message translates to:
  /// **'{p1}年前'**
  String dynamicsDetailYrAgo(Object p1);

  /// No description provided for @dynamicsLocal.
  ///
  /// In zh, this message translates to:
  /// **'同城'**
  String get dynamicsLocal;

  /// No description provided for @dynamicsMine.
  ///
  /// In zh, this message translates to:
  /// **'我的'**
  String get dynamicsMine;

  /// No description provided for @dynamicsMomentNotifications.
  ///
  /// In zh, this message translates to:
  /// **'动态通知'**
  String get dynamicsMomentNotifications;

  /// No description provided for @dynamicsNoMomentsYetPull.
  ///
  /// In zh, this message translates to:
  /// **'暂无动态，下拉刷新'**
  String get dynamicsNoMomentsYetPull;

  /// No description provided for @dynamicsOfficial.
  ///
  /// In zh, this message translates to:
  /// **'官方'**
  String get dynamicsOfficial;

  /// No description provided for @dynamicsPopular.
  ///
  /// In zh, this message translates to:
  /// **'热门'**
  String get dynamicsPopular;

  /// No description provided for @dynamicsPostMoment.
  ///
  /// In zh, this message translates to:
  /// **'发布动态'**
  String get dynamicsPostMoment;

  /// No description provided for @dynamicsTopicNoMomentsTopicYet.
  ///
  /// In zh, this message translates to:
  /// **'该话题暂无动态，下拉刷新'**
  String get dynamicsTopicNoMomentsTopicYet;

  /// No description provided for @dynamicsTopicNoTopicsYetPull.
  ///
  /// In zh, this message translates to:
  /// **'暂无话题，下拉刷新'**
  String get dynamicsTopicNoTopicsYetPull;

  /// No description provided for @dynamicsTopicTopic.
  ///
  /// In zh, this message translates to:
  /// **'话题 {p1}'**
  String dynamicsTopicTopic(Object p1);

  /// No description provided for @dynamicsTopicTopics.
  ///
  /// In zh, this message translates to:
  /// **'话题'**
  String get dynamicsTopicTopics;

  /// No description provided for @emojiAddEmojiPack.
  ///
  /// In zh, this message translates to:
  /// **'添加表情包'**
  String get emojiAddEmojiPack;

  /// No description provided for @emojiBasics.
  ///
  /// In zh, this message translates to:
  /// **'基础'**
  String get emojiBasics;

  /// No description provided for @emojiEmojiPackManagementIsnt.
  ///
  /// In zh, this message translates to:
  /// **'表情包管理暂未开放'**
  String get emojiEmojiPackManagementIsnt;

  /// No description provided for @emojiEmojiPackStoreIsnt.
  ///
  /// In zh, this message translates to:
  /// **'表情包商城暂未开放'**
  String get emojiEmojiPackStoreIsnt;

  /// No description provided for @emojiEmojiSettings.
  ///
  /// In zh, this message translates to:
  /// **'表情设置'**
  String get emojiEmojiSettings;

  /// No description provided for @emojiInteractive.
  ///
  /// In zh, this message translates to:
  /// **'互动'**
  String get emojiInteractive;

  /// No description provided for @emojiMember.
  ///
  /// In zh, this message translates to:
  /// **'会员'**
  String get emojiMember;

  /// No description provided for @emojiNoEmojiPacksAvailable.
  ///
  /// In zh, this message translates to:
  /// **'暂无可用的表情包'**
  String get emojiNoEmojiPacksAvailable;

  /// No description provided for @familyAnnouncement.
  ///
  /// In zh, this message translates to:
  /// **'公告'**
  String get familyAnnouncement;

  /// No description provided for @familyApprove.
  ///
  /// In zh, this message translates to:
  /// **'通过'**
  String get familyApprove;

  /// No description provided for @familyApproved.
  ///
  /// In zh, this message translates to:
  /// **'已通过'**
  String get familyApproved;

  /// No description provided for @familyFailedLeave.
  ///
  /// In zh, this message translates to:
  /// **'退出失败: {e}'**
  String familyFailedLeave(Object e);

  /// No description provided for @familyFamilyJoinRequests.
  ///
  /// In zh, this message translates to:
  /// **'入族申请'**
  String get familyFamilyJoinRequests;

  /// No description provided for @familyFamilyMessages.
  ///
  /// In zh, this message translates to:
  /// **'家族消息'**
  String get familyFamilyMessages;

  /// No description provided for @familyJoinedFamilies.
  ///
  /// In zh, this message translates to:
  /// **'已加入 {p1} 个家族'**
  String familyJoinedFamilies(Object p1);

  /// No description provided for @familyLeader.
  ///
  /// In zh, this message translates to:
  /// **'族长'**
  String get familyLeader;

  /// No description provided for @familyLeave.
  ///
  /// In zh, this message translates to:
  /// **'确定退出「{p1}」吗？'**
  String familyLeave(Object p1);

  /// No description provided for @familyLeaveFamily.
  ///
  /// In zh, this message translates to:
  /// **'退出家族'**
  String get familyLeaveFamily;

  /// No description provided for @familyMembers.
  ///
  /// In zh, this message translates to:
  /// **'成员数'**
  String get familyMembers;

  /// No description provided for @familyMembers2.
  ///
  /// In zh, this message translates to:
  /// **'成员'**
  String get familyMembers2;

  /// No description provided for @familyMessageFamily.
  ///
  /// In zh, this message translates to:
  /// **'发家族消息…'**
  String get familyMessageFamily;

  /// No description provided for @familyNoFamilyJoinRequests.
  ///
  /// In zh, this message translates to:
  /// **'暂无入族申请'**
  String get familyNoFamilyJoinRequests;

  /// No description provided for @familyNoFamilyMessages.
  ///
  /// In zh, this message translates to:
  /// **'暂无家族消息'**
  String get familyNoFamilyMessages;

  /// No description provided for @familyRefreshHint.
  ///
  /// In zh, this message translates to:
  /// **'{_error}\n\n点击右上角刷新'**
  String familyRefreshHint(Object _error);

  /// No description provided for @familyRejected.
  ///
  /// In zh, this message translates to:
  /// **'已拒绝'**
  String get familyRejected;

  /// No description provided for @familyTransferLeadership.
  ///
  /// In zh, this message translates to:
  /// **'转让族长'**
  String get familyTransferLeadership;

  /// No description provided for @familyYouHaventJoinedAny.
  ///
  /// In zh, this message translates to:
  /// **'你尚未加入任何家族'**
  String get familyYouHaventJoinedAny;

  /// No description provided for @favoritesContentGone.
  ///
  /// In zh, this message translates to:
  /// **'（内容已不在本机）'**
  String get favoritesContentGone;

  /// No description provided for @friendFilterFilter.
  ///
  /// In zh, this message translates to:
  /// **'筛选'**
  String get friendFilterFilter;

  /// No description provided for @friendFilterFriendsInvite.
  ///
  /// In zh, this message translates to:
  /// **'邀请一起玩的好友'**
  String get friendFilterFriendsInvite;

  /// No description provided for @friendFilterGeneral.
  ///
  /// In zh, this message translates to:
  /// **'通用'**
  String get friendFilterGeneral;

  /// No description provided for @friendFilterNewTag.
  ///
  /// In zh, this message translates to:
  /// **'新建标签'**
  String get friendFilterNewTag;

  /// No description provided for @friendFilterOnlineFriends.
  ///
  /// In zh, this message translates to:
  /// **'在线好友'**
  String get friendFilterOnlineFriends;

  /// No description provided for @friendFilterReset.
  ///
  /// In zh, this message translates to:
  /// **'重置'**
  String get friendFilterReset;

  /// No description provided for @friendFilterTagNameMax5.
  ///
  /// In zh, this message translates to:
  /// **'标签名（最多 5 个字）'**
  String get friendFilterTagNameMax5;

  /// No description provided for @friendFilterTags.
  ///
  /// In zh, this message translates to:
  /// **'标签'**
  String get friendFilterTags;

  /// No description provided for @friendFilterYouHaventCreatedAny.
  ///
  /// In zh, this message translates to:
  /// **'你还未创建标签'**
  String get friendFilterYouHaventCreatedAny;

  /// No description provided for @friendRequestAccept.
  ///
  /// In zh, this message translates to:
  /// **'同意'**
  String get friendRequestAccept;

  /// No description provided for @friendRequestAddFriend.
  ///
  /// In zh, this message translates to:
  /// **'添加好友'**
  String get friendRequestAddFriend;

  /// No description provided for @friendRequestEnterTheirMiniID.
  ///
  /// In zh, this message translates to:
  /// **'输入对方的迷你号'**
  String get friendRequestEnterTheirMiniID;

  /// No description provided for @friendRequestEnterValidMiniID.
  ///
  /// In zh, this message translates to:
  /// **'请输入有效的迷你号'**
  String get friendRequestEnterValidMiniID;

  /// No description provided for @friendRequestFailedApprove.
  ///
  /// In zh, this message translates to:
  /// **'通过失败: {e}'**
  String friendRequestFailedApprove(Object e);

  /// No description provided for @friendRequestFailedReject.
  ///
  /// In zh, this message translates to:
  /// **'拒绝失败: {e}'**
  String friendRequestFailedReject(Object e);

  /// No description provided for @friendRequestFailedSendRequest.
  ///
  /// In zh, this message translates to:
  /// **'发送申请失败: {e}'**
  String friendRequestFailedSendRequest(Object e);

  /// No description provided for @friendRequestFriendAdded.
  ///
  /// In zh, this message translates to:
  /// **'已添加好友'**
  String get friendRequestFriendAdded;

  /// No description provided for @friendRequestFriendRequestSent.
  ///
  /// In zh, this message translates to:
  /// **'已向 {uin} 发送好友申请'**
  String friendRequestFriendRequestSent(Object uin);

  /// No description provided for @friendRequestFriendRequests.
  ///
  /// In zh, this message translates to:
  /// **'好友申请'**
  String get friendRequestFriendRequests;

  /// No description provided for @friendRequestGroup.
  ///
  /// In zh, this message translates to:
  /// **'群 {p1}'**
  String friendRequestGroup(Object p1);

  /// No description provided for @friendRequestGroupInvites.
  ///
  /// In zh, this message translates to:
  /// **'群邀请'**
  String get friendRequestGroupInvites;

  /// No description provided for @friendRequestInvitedMembers.
  ///
  /// In zh, this message translates to:
  /// **'邀请人 {p1} · 成员 {p2}'**
  String friendRequestInvitedMembers(Object p1, Object p2);

  /// No description provided for @friendRequestNoGroupInvites.
  ///
  /// In zh, this message translates to:
  /// **'暂无群邀请'**
  String get friendRequestNoGroupInvites;

  /// No description provided for @friendRequestNoPendingFriendRequests.
  ///
  /// In zh, this message translates to:
  /// **'暂无待处理的好友申请'**
  String get friendRequestNoPendingFriendRequests;

  /// No description provided for @friendRequestOperationFailedRet.
  ///
  /// In zh, this message translates to:
  /// **'操作失败: ret={ret}'**
  String friendRequestOperationFailedRet(Object ret);

  /// No description provided for @friendRequestReject.
  ///
  /// In zh, this message translates to:
  /// **'拒绝'**
  String get friendRequestReject;

  /// No description provided for @friendRequestReject2.
  ///
  /// In zh, this message translates to:
  /// **'全部拒绝'**
  String get friendRequestReject2;

  /// No description provided for @friendRequestRejectedFriendRequests.
  ///
  /// In zh, this message translates to:
  /// **'已拒绝全部好友申请'**
  String get friendRequestRejectedFriendRequests;

  /// No description provided for @friendRequestRequestList.
  ///
  /// In zh, this message translates to:
  /// **'申请列表'**
  String get friendRequestRequestList;

  /// No description provided for @friendRequestSendRequest.
  ///
  /// In zh, this message translates to:
  /// **'发送申请'**
  String get friendRequestSendRequest;

  /// No description provided for @friendTagAfterDeletionTagRemoved.
  ///
  /// In zh, this message translates to:
  /// **'删除后该标签会从所有好友身上移除。'**
  String get friendTagAfterDeletionTagRemoved;

  /// No description provided for @friendTagClearTagsTheseFriends.
  ///
  /// In zh, this message translates to:
  /// **'清除这些好友的标签'**
  String get friendTagClearTagsTheseFriends;

  /// No description provided for @friendTagCreated.
  ///
  /// In zh, this message translates to:
  /// **'已创建「{label}」'**
  String friendTagCreated(Object label);

  /// No description provided for @friendTagDeleteTag.
  ///
  /// In zh, this message translates to:
  /// **'删除标签'**
  String get friendTagDeleteTag;

  /// No description provided for @friendTagDeleteTag2.
  ///
  /// In zh, this message translates to:
  /// **'删除标签「{p1}」'**
  String friendTagDeleteTag2(Object p1);

  /// No description provided for @friendTagDone.
  ///
  /// In zh, this message translates to:
  /// **'完成'**
  String get friendTagDone;

  /// No description provided for @friendTagFriends.
  ///
  /// In zh, this message translates to:
  /// **'{p1} 位好友'**
  String friendTagFriends(Object p1);

  /// No description provided for @friendTagServerDidntAcceptResult.
  ///
  /// In zh, this message translates to:
  /// **'服务端未受理（result={code}）'**
  String friendTagServerDidntAcceptResult(Object code);

  /// No description provided for @friendTagTagDeleted.
  ///
  /// In zh, this message translates to:
  /// **'已删除标签'**
  String get friendTagTagDeleted;

  /// No description provided for @friendTagTagFriends.
  ///
  /// In zh, this message translates to:
  /// **'给 {p1} 位好友打标签'**
  String friendTagTagFriends(Object p1);

  /// No description provided for @friendTagTagsApplied.
  ///
  /// In zh, this message translates to:
  /// **'已打标签'**
  String get friendTagTagsApplied;

  /// No description provided for @friendTagTagsRemoved.
  ///
  /// In zh, this message translates to:
  /// **'已取消标签'**
  String get friendTagTagsRemoved;

  /// No description provided for @friendsAddMiniID.
  ///
  /// In zh, this message translates to:
  /// **'按迷你号添加'**
  String get friendsAddMiniID;

  /// No description provided for @friendsAddTags.
  ///
  /// In zh, this message translates to:
  /// **'打标签'**
  String get friendsAddTags;

  /// No description provided for @friendsBlocklist.
  ///
  /// In zh, this message translates to:
  /// **'黑名单'**
  String get friendsBlocklist;

  /// No description provided for @friendsBulkManagement.
  ///
  /// In zh, this message translates to:
  /// **'批量管理'**
  String get friendsBulkManagement;

  /// No description provided for @friendsClearTags.
  ///
  /// In zh, this message translates to:
  /// **'清除标签'**
  String get friendsClearTags;

  /// No description provided for @friendsCloseSearch.
  ///
  /// In zh, this message translates to:
  /// **'关闭搜索'**
  String get friendsCloseSearch;

  /// No description provided for @friendsDefaultFriendOrder.
  ///
  /// In zh, this message translates to:
  /// **'好友默认排序'**
  String get friendsDefaultFriendOrder;

  /// No description provided for @friendsExitBulkManagement.
  ///
  /// In zh, this message translates to:
  /// **'退出批量管理'**
  String get friendsExitBulkManagement;

  /// No description provided for @friendsFollowingFollowers.
  ///
  /// In zh, this message translates to:
  /// **'关注与粉丝'**
  String get friendsFollowingFollowers;

  /// No description provided for @friendsGroupLeaveHistory.
  ///
  /// In zh, this message translates to:
  /// **'退群记录'**
  String get friendsGroupLeaveHistory;

  /// No description provided for @friendsGroups.
  ///
  /// In zh, this message translates to:
  /// **'群组'**
  String get friendsGroups;

  /// No description provided for @friendsHighestRapportFirst.
  ///
  /// In zh, this message translates to:
  /// **'默契度从高到低'**
  String get friendsHighestRapportFirst;

  /// No description provided for @friendsMiniID.
  ///
  /// In zh, this message translates to:
  /// **'{gameText} · 迷你号 {p1}'**
  String friendsMiniID(Object gameText, Object p1);

  /// No description provided for @friendsMore.
  ///
  /// In zh, this message translates to:
  /// **'更多'**
  String get friendsMore;

  /// No description provided for @friendsMostRecentLoginFirst.
  ///
  /// In zh, this message translates to:
  /// **'登录从近到远'**
  String get friendsMostRecentLoginFirst;

  /// No description provided for @friendsMyFriends.
  ///
  /// In zh, this message translates to:
  /// **'我的好友'**
  String get friendsMyFriends;

  /// No description provided for @friendsMyQRCode.
  ///
  /// In zh, this message translates to:
  /// **'我的二维码'**
  String get friendsMyQRCode;

  /// No description provided for @friendsNoFriendsMatchFilters.
  ///
  /// In zh, this message translates to:
  /// **'没有符合条件的好友'**
  String get friendsNoFriendsMatchFilters;

  /// No description provided for @friendsNoFriendsYetPull.
  ///
  /// In zh, this message translates to:
  /// **'暂无好友\n下拉刷新或点击右上角添加'**
  String get friendsNoFriendsYetPull;

  /// No description provided for @friendsNoGroupChats.
  ///
  /// In zh, this message translates to:
  /// **'暂无群聊'**
  String get friendsNoGroupChats;

  /// No description provided for @friendsNoGroupsYetPull.
  ///
  /// In zh, this message translates to:
  /// **'暂无群聊\n下拉刷新或点击右上角创建群'**
  String get friendsNoGroupsYetPull;

  /// No description provided for @friendsOffline.
  ///
  /// In zh, this message translates to:
  /// **'离线'**
  String get friendsOffline;

  /// No description provided for @friendsOldestLoginFirst.
  ///
  /// In zh, this message translates to:
  /// **'登录从远到近'**
  String get friendsOldestLoginFirst;

  /// No description provided for @friendsOnline.
  ///
  /// In zh, this message translates to:
  /// **'在线'**
  String get friendsOnline;

  /// No description provided for @friendsOnlineFriends.
  ///
  /// In zh, this message translates to:
  /// **'在线好友 {online}/{total}'**
  String friendsOnlineFriends(Object online, Object total);

  /// No description provided for @friendsOnlineNotifications.
  ///
  /// In zh, this message translates to:
  /// **'上线通知'**
  String get friendsOnlineNotifications;

  /// No description provided for @friendsOnlineNotificationsSetPeople.
  ///
  /// In zh, this message translates to:
  /// **'已设置上线通知（{p1} 人）'**
  String friendsOnlineNotificationsSetPeople(Object p1);

  /// No description provided for @friendsPeopleNearby.
  ///
  /// In zh, this message translates to:
  /// **'附近的人'**
  String get friendsPeopleNearby;

  /// No description provided for @friendsSearch.
  ///
  /// In zh, this message translates to:
  /// **'搜索'**
  String get friendsSearch;

  /// No description provided for @friendsSearch2.
  ///
  /// In zh, this message translates to:
  /// **'搜索：{_search}'**
  String friendsSearch2(Object _search);

  /// No description provided for @friendsSearchFriendNicknameMini.
  ///
  /// In zh, this message translates to:
  /// **'搜索好友昵称 / 迷你号…'**
  String get friendsSearchFriendNicknameMini;

  /// No description provided for @friendsSelected.
  ///
  /// In zh, this message translates to:
  /// **'已选 {count} 人'**
  String friendsSelected(Object count);

  /// No description provided for @friendsSort.
  ///
  /// In zh, this message translates to:
  /// **'排序方式：{p1}'**
  String friendsSort(Object p1);

  /// No description provided for @friendsSort2.
  ///
  /// In zh, this message translates to:
  /// **'排序方式'**
  String get friendsSort2;

  /// No description provided for @friendsTagsCleared.
  ///
  /// In zh, this message translates to:
  /// **'已清除标签'**
  String get friendsTagsCleared;

  /// No description provided for @friendsTapOpenGroupChat.
  ///
  /// In zh, this message translates to:
  /// **'点击进入群聊'**
  String get friendsTapOpenGroupChat;

  /// No description provided for @friendsViewProfile.
  ///
  /// In zh, this message translates to:
  /// **'查看主页'**
  String get friendsViewProfile;

  /// No description provided for @giftBuyIntoInventoryFirst.
  ///
  /// In zh, this message translates to:
  /// **'先买进仓库再送，扣 {p1} {p2}'**
  String giftBuyIntoInventoryFirst(Object p1, Object p2);

  /// No description provided for @giftBuySend.
  ///
  /// In zh, this message translates to:
  /// **'扣费购买赠送'**
  String get giftBuySend;

  /// No description provided for @giftBuyThenSend.
  ///
  /// In zh, this message translates to:
  /// **'购买 {_num} 份后赠送'**
  String giftBuyThenSend(Object _num);

  /// No description provided for @giftCouldntLoadGiftConfig.
  ///
  /// In zh, this message translates to:
  /// **'取不到礼物配置（或当前无可赠送礼物）'**
  String get giftCouldntLoadGiftConfig;

  /// No description provided for @giftDailyRapportCap.
  ///
  /// In zh, this message translates to:
  /// **'每日默契度上限 {p1}'**
  String giftDailyRapportCap(Object p1);

  /// No description provided for @giftDeductsInventoryFreeInventory.
  ///
  /// In zh, this message translates to:
  /// **'扣仓库库存，免费；仓库 ×{p1}'**
  String giftDeductsInventoryFreeInventory(Object p1);

  /// No description provided for @giftFailedSendGift.
  ///
  /// In zh, this message translates to:
  /// **'赠送失败: {e}'**
  String giftFailedSendGift(Object e);

  /// No description provided for @giftFree.
  ///
  /// In zh, this message translates to:
  /// **'免费'**
  String get giftFree;

  /// No description provided for @giftGiftSent.
  ///
  /// In zh, this message translates to:
  /// **'赠送成功'**
  String get giftGiftSent;

  /// No description provided for @giftInventoryX.
  ///
  /// In zh, this message translates to:
  /// **'仓库 ×{owned}'**
  String giftInventoryX(Object owned);

  /// No description provided for @giftQuantity.
  ///
  /// In zh, this message translates to:
  /// **'数量'**
  String get giftQuantity;

  /// No description provided for @giftRapport.
  ///
  /// In zh, this message translates to:
  /// **'默契度 +{p1}'**
  String giftRapport(Object p1);

  /// No description provided for @giftRapport2.
  ///
  /// In zh, this message translates to:
  /// **'默契度 +{p1}'**
  String giftRapport2(Object p1);

  /// No description provided for @giftSendAfterWatchingAd.
  ///
  /// In zh, this message translates to:
  /// **'看完广告后送出'**
  String get giftSendAfterWatchingAd;

  /// No description provided for @giftSendFree.
  ///
  /// In zh, this message translates to:
  /// **'免费赠送 {_num} 份'**
  String giftSendFree(Object _num);

  /// No description provided for @giftSendFree2.
  ///
  /// In zh, this message translates to:
  /// **'免费赠送'**
  String get giftSendFree2;

  /// No description provided for @giftSendGift.
  ///
  /// In zh, this message translates to:
  /// **'赠送礼物给 {_displayName}'**
  String giftSendGift(Object _displayName);

  /// No description provided for @giftSendGiftInventory.
  ///
  /// In zh, this message translates to:
  /// **'从礼物仓库赠送'**
  String get giftSendGiftInventory;

  /// No description provided for @giftSendInventoryFree.
  ///
  /// In zh, this message translates to:
  /// **'从仓库赠送 {_num} 份（免费）'**
  String giftSendInventoryFree(Object _num);

  /// No description provided for @giftSendInventoryInventoryFail.
  ///
  /// In zh, this message translates to:
  /// **'从仓库赠送 {_num} 份（仓库只有 {p1} 份，会失败）'**
  String giftSendInventoryInventoryFail(Object _num, Object p1);

  /// No description provided for @giftUseTodaysFreeSend.
  ///
  /// In zh, this message translates to:
  /// **'用当日的免费赠送次数'**
  String get giftUseTodaysFreeSend;

  /// No description provided for @giftWatchAd.
  ///
  /// In zh, this message translates to:
  /// **'看广告'**
  String get giftWatchAd;

  /// No description provided for @giftWatchAdSend.
  ///
  /// In zh, this message translates to:
  /// **'看广告赠送 {_num} 份'**
  String giftWatchAdSend(Object _num);

  /// No description provided for @giftWatchAdSend2.
  ///
  /// In zh, this message translates to:
  /// **'看广告赠送'**
  String get giftWatchAdSend2;

  /// No description provided for @groupDetailAllRejected.
  ///
  /// In zh, this message translates to:
  /// **'已全部拒绝'**
  String get groupDetailAllRejected;

  /// No description provided for @groupDetailBlockMembersMessages.
  ///
  /// In zh, this message translates to:
  /// **'屏蔽该成员消息'**
  String get groupDetailBlockMembersMessages;

  /// No description provided for @groupDetailChooseFriendsInvite.
  ///
  /// In zh, this message translates to:
  /// **'选择要邀请的好友'**
  String get groupDetailChooseFriendsInvite;

  /// No description provided for @groupDetailChooseNewGroupOwner.
  ///
  /// In zh, this message translates to:
  /// **'选择新群主'**
  String get groupDetailChooseNewGroupOwner;

  /// No description provided for @groupDetailClear.
  ///
  /// In zh, this message translates to:
  /// **'清除'**
  String get groupDetailClear;

  /// No description provided for @groupDetailDisbandGroup.
  ///
  /// In zh, this message translates to:
  /// **'解散群'**
  String get groupDetailDisbandGroup;

  /// No description provided for @groupDetailEditGroupName.
  ///
  /// In zh, this message translates to:
  /// **'修改群名'**
  String get groupDetailEditGroupName;

  /// No description provided for @groupDetailFailedClear.
  ///
  /// In zh, this message translates to:
  /// **'清除失败: {e}'**
  String groupDetailFailedClear(Object e);

  /// No description provided for @groupDetailFailedDisband.
  ///
  /// In zh, this message translates to:
  /// **'解散失败: {e}'**
  String groupDetailFailedDisband(Object e);

  /// No description provided for @groupDetailFailedInvite.
  ///
  /// In zh, this message translates to:
  /// **'邀请失败: {e}'**
  String groupDetailFailedInvite(Object e);

  /// No description provided for @groupDetailFailedPin.
  ///
  /// In zh, this message translates to:
  /// **'置顶失败: {e}'**
  String groupDetailFailedPin(Object e);

  /// No description provided for @groupDetailFailedTransfer.
  ///
  /// In zh, this message translates to:
  /// **'转让失败: {e}'**
  String groupDetailFailedTransfer(Object e);

  /// No description provided for @groupDetailFailedUpdate.
  ///
  /// In zh, this message translates to:
  /// **'更新失败: {e}'**
  String groupDetailFailedUpdate(Object e);

  /// No description provided for @groupDetailGroup.
  ///
  /// In zh, this message translates to:
  /// **'群 {gid}'**
  String groupDetailGroup(Object gid);

  /// No description provided for @groupDetailGroup2.
  ///
  /// In zh, this message translates to:
  /// **'群 {p1}'**
  String groupDetailGroup2(Object p1);

  /// No description provided for @groupDetailGroupDataCannotRecovered.
  ///
  /// In zh, this message translates to:
  /// **'解散后群内数据将不可恢复，确定解散？'**
  String get groupDetailGroupDataCannotRecovered;

  /// No description provided for @groupDetailGroupDisbanded.
  ///
  /// In zh, this message translates to:
  /// **'群已解散'**
  String get groupDetailGroupDisbanded;

  /// No description provided for @groupDetailGroupID.
  ///
  /// In zh, this message translates to:
  /// **'群号'**
  String get groupDetailGroupID;

  /// No description provided for @groupDetailGroupName.
  ///
  /// In zh, this message translates to:
  /// **'群名称'**
  String get groupDetailGroupName;

  /// No description provided for @groupDetailGroupNameUpdated.
  ///
  /// In zh, this message translates to:
  /// **'已更新群名'**
  String get groupDetailGroupNameUpdated;

  /// No description provided for @groupDetailGroupNotificationsMuted.
  ///
  /// In zh, this message translates to:
  /// **'已开启群免打扰'**
  String get groupDetailGroupNotificationsMuted;

  /// No description provided for @groupDetailGroupNotificationsUnmuted.
  ///
  /// In zh, this message translates to:
  /// **'已关闭群免打扰'**
  String get groupDetailGroupNotificationsUnmuted;

  /// No description provided for @groupDetailGroupOwner.
  ///
  /// In zh, this message translates to:
  /// **'群主'**
  String get groupDetailGroupOwner;

  /// No description provided for @groupDetailGroupPinned.
  ///
  /// In zh, this message translates to:
  /// **'已置顶群'**
  String get groupDetailGroupPinned;

  /// No description provided for @groupDetailInvitationSent.
  ///
  /// In zh, this message translates to:
  /// **'已发送邀请'**
  String get groupDetailInvitationSent;

  /// No description provided for @groupDetailInvite.
  ///
  /// In zh, this message translates to:
  /// **'邀请'**
  String get groupDetailInvite;

  /// No description provided for @groupDetailInviteFriendsGroup.
  ///
  /// In zh, this message translates to:
  /// **'邀请好友入群'**
  String get groupDetailInviteFriendsGroup;

  /// No description provided for @groupDetailLeaveGroup.
  ///
  /// In zh, this message translates to:
  /// **'退出群'**
  String get groupDetailLeaveGroup;

  /// No description provided for @groupDetailLeaveGroup2.
  ///
  /// In zh, this message translates to:
  /// **'确定退出该群吗？'**
  String get groupDetailLeaveGroup2;

  /// No description provided for @groupDetailLeftGroup.
  ///
  /// In zh, this message translates to:
  /// **'已退出群'**
  String get groupDetailLeftGroup;

  /// No description provided for @groupDetailMemberRemoved.
  ///
  /// In zh, this message translates to:
  /// **'已移出该成员'**
  String get groupDetailMemberRemoved;

  /// No description provided for @groupDetailMembersMessagesBlocked.
  ///
  /// In zh, this message translates to:
  /// **'已屏蔽该成员消息'**
  String get groupDetailMembersMessagesBlocked;

  /// No description provided for @groupDetailMuteGroupNotifications.
  ///
  /// In zh, this message translates to:
  /// **'群消息免打扰'**
  String get groupDetailMuteGroupNotifications;

  /// No description provided for @groupDetailMuteMember.
  ///
  /// In zh, this message translates to:
  /// **'禁言该成员'**
  String get groupDetailMuteMember;

  /// No description provided for @groupDetailMuted.
  ///
  /// In zh, this message translates to:
  /// **'已禁言'**
  String get groupDetailMuted;

  /// No description provided for @groupDetailNameWithMe.
  ///
  /// In zh, this message translates to:
  /// **'{name}（我）'**
  String groupDetailNameWithMe(Object name);

  /// No description provided for @groupDetailNoFriendsInvite.
  ///
  /// In zh, this message translates to:
  /// **'暂无好友可邀请'**
  String get groupDetailNoFriendsInvite;

  /// No description provided for @groupDetailNoGroupLeaveHistory.
  ///
  /// In zh, this message translates to:
  /// **'没有退群记录'**
  String get groupDetailNoGroupLeaveHistory;

  /// No description provided for @groupDetailNoMemberInfoYet.
  ///
  /// In zh, this message translates to:
  /// **'暂无成员信息（可能未拉取到）'**
  String get groupDetailNoMemberInfoYet;

  /// No description provided for @groupDetailNoMembersTransfer.
  ///
  /// In zh, this message translates to:
  /// **'没有可转让的成员'**
  String get groupDetailNoMembersTransfer;

  /// No description provided for @groupDetailPinGroup.
  ///
  /// In zh, this message translates to:
  /// **'群置顶'**
  String get groupDetailPinGroup;

  /// No description provided for @groupDetailRecordsCleared.
  ///
  /// In zh, this message translates to:
  /// **'已清除记录'**
  String get groupDetailRecordsCleared;

  /// No description provided for @groupDetailReject.
  ///
  /// In zh, this message translates to:
  /// **'一键拒绝'**
  String get groupDetailReject;

  /// No description provided for @groupDetailRejectJoinRequests.
  ///
  /// In zh, this message translates to:
  /// **'一键拒绝入群申请'**
  String get groupDetailRejectJoinRequests;

  /// No description provided for @groupDetailRejectPendingJoinRequests.
  ///
  /// In zh, this message translates to:
  /// **'拒绝本群全部待处理的入群申请？'**
  String get groupDetailRejectPendingJoinRequests;

  /// No description provided for @groupDetailRemoveGroup.
  ///
  /// In zh, this message translates to:
  /// **'移出该群'**
  String get groupDetailRemoveGroup;

  /// No description provided for @groupDetailRemoveGroup2.
  ///
  /// In zh, this message translates to:
  /// **'确定将 {p1} 移出本群？'**
  String groupDetailRemoveGroup2(Object p1);

  /// No description provided for @groupDetailRemoveGroupMember.
  ///
  /// In zh, this message translates to:
  /// **'移出群成员'**
  String get groupDetailRemoveGroupMember;

  /// No description provided for @groupDetailReportMember.
  ///
  /// In zh, this message translates to:
  /// **'举报该成员'**
  String get groupDetailReportMember;

  /// No description provided for @groupDetailReportSubmitted.
  ///
  /// In zh, this message translates to:
  /// **'已提交举报'**
  String get groupDetailReportSubmitted;

  /// No description provided for @groupDetailSave.
  ///
  /// In zh, this message translates to:
  /// **'保存'**
  String get groupDetailSave;

  /// No description provided for @groupDetailSelected.
  ///
  /// In zh, this message translates to:
  /// **'已选 {p1} 人'**
  String groupDetailSelected(Object p1);

  /// No description provided for @groupDetailTransferGroupOwnership.
  ///
  /// In zh, this message translates to:
  /// **'转让群主'**
  String get groupDetailTransferGroupOwnership;

  /// No description provided for @groupDetailTransferGroupOwnership2.
  ///
  /// In zh, this message translates to:
  /// **'确认将群主转给 {p1}？'**
  String groupDetailTransferGroupOwnership2(Object p1);

  /// No description provided for @groupDetailTransferred.
  ///
  /// In zh, this message translates to:
  /// **'已转让'**
  String get groupDetailTransferred;

  /// No description provided for @groupDetailUnblockMember.
  ///
  /// In zh, this message translates to:
  /// **'解除屏蔽该成员'**
  String get groupDetailUnblockMember;

  /// No description provided for @groupDetailUnblocked.
  ///
  /// In zh, this message translates to:
  /// **'已解除屏蔽'**
  String get groupDetailUnblocked;

  /// No description provided for @groupDetailUnmuteGroup.
  ///
  /// In zh, this message translates to:
  /// **'取消群免打扰'**
  String get groupDetailUnmuteGroup;

  /// No description provided for @groupDetailUnmuteMember.
  ///
  /// In zh, this message translates to:
  /// **'解除该成员禁言'**
  String get groupDetailUnmuteMember;

  /// No description provided for @groupDetailUnmuted.
  ///
  /// In zh, this message translates to:
  /// **'已解除禁言'**
  String get groupDetailUnmuted;

  /// No description provided for @groupDetailUnpinGroup.
  ///
  /// In zh, this message translates to:
  /// **'取消群置顶'**
  String get groupDetailUnpinGroup;

  /// No description provided for @groupDetailYouLeftGroup.
  ///
  /// In zh, this message translates to:
  /// **'你已退出该群'**
  String get groupDetailYouLeftGroup;

  /// No description provided for @groupDetailYouWereRemovedGroup.
  ///
  /// In zh, this message translates to:
  /// **'你被移出该群'**
  String get groupDetailYouWereRemovedGroup;

  /// No description provided for @homeLayoutUnknownModule.
  ///
  /// In zh, this message translates to:
  /// **'未知模块'**
  String get homeLayoutUnknownModule;

  /// No description provided for @lockEnterAppLockPassword.
  ///
  /// In zh, this message translates to:
  /// **'请输入应用锁密码'**
  String get lockEnterAppLockPassword;

  /// No description provided for @lockWrongPassword.
  ///
  /// In zh, this message translates to:
  /// **'密码错误'**
  String get lockWrongPassword;

  /// No description provided for @loginAddAccount.
  ///
  /// In zh, this message translates to:
  /// **'添加账号'**
  String get loginAddAccount;

  /// No description provided for @loginBackAccountList.
  ///
  /// In zh, this message translates to:
  /// **'返回账号列表'**
  String get loginBackAccountList;

  /// No description provided for @loginChooseAccount.
  ///
  /// In zh, this message translates to:
  /// **'选择账号'**
  String get loginChooseAccount;

  /// No description provided for @loginEnterPassword.
  ///
  /// In zh, this message translates to:
  /// **'请输入密码'**
  String get loginEnterPassword;

  /// No description provided for @loginMiniID.
  ///
  /// In zh, this message translates to:
  /// **'迷你号 {p1}'**
  String loginMiniID(Object p1);

  /// No description provided for @loginMiniWorldExternalChat.
  ///
  /// In zh, this message translates to:
  /// **'迷你世界外部聊天 · 选择账号登录'**
  String get loginMiniWorldExternalChat;

  /// No description provided for @loginNoSavedAccountsYet.
  ///
  /// In zh, this message translates to:
  /// **'还没有保存的账号'**
  String get loginNoSavedAccountsYet;

  /// No description provided for @loginPassword.
  ///
  /// In zh, this message translates to:
  /// **'密码'**
  String get loginPassword;

  /// No description provided for @loginRemove.
  ///
  /// In zh, this message translates to:
  /// **'移除'**
  String get loginRemove;

  /// No description provided for @loginRemoveAccount.
  ///
  /// In zh, this message translates to:
  /// **'移除账号'**
  String get loginRemoveAccount;

  /// No description provided for @loginSign.
  ///
  /// In zh, this message translates to:
  /// **'登录'**
  String get loginSign;

  /// No description provided for @loginSignAdd.
  ///
  /// In zh, this message translates to:
  /// **'登录并添加'**
  String get loginSignAdd;

  /// No description provided for @loginSignAutomaticallyNextTime.
  ///
  /// In zh, this message translates to:
  /// **'下次自动登录'**
  String get loginSignAutomaticallyNextTime;

  /// No description provided for @loginSigning.
  ///
  /// In zh, this message translates to:
  /// **'登录中…'**
  String get loginSigning;

  /// No description provided for @loginUinMiniID.
  ///
  /// In zh, this message translates to:
  /// **'Uin / 迷你号'**
  String get loginUinMiniID;

  /// No description provided for @mailAll.
  ///
  /// In zh, this message translates to:
  /// **'全部'**
  String get mailAll;

  /// No description provided for @mailAttachments.
  ///
  /// In zh, this message translates to:
  /// **'附件'**
  String get mailAttachments;

  /// No description provided for @mailClaimAttachments.
  ///
  /// In zh, this message translates to:
  /// **'领取附件'**
  String get mailClaimAttachments;

  /// No description provided for @mailClaimed.
  ///
  /// In zh, this message translates to:
  /// **'已领取'**
  String get mailClaimed;

  /// No description provided for @mailDAgo.
  ///
  /// In zh, this message translates to:
  /// **'{p1}天前'**
  String mailDAgo(Object p1);

  /// No description provided for @mailDeleteRead.
  ///
  /// In zh, this message translates to:
  /// **'删除已读'**
  String get mailDeleteRead;

  /// No description provided for @mailDetails.
  ///
  /// In zh, this message translates to:
  /// **'详情'**
  String get mailDetails;

  /// No description provided for @mailFailedFollow.
  ///
  /// In zh, this message translates to:
  /// **'关注失败'**
  String get mailFailedFollow;

  /// No description provided for @mailFailedMarkRead.
  ///
  /// In zh, this message translates to:
  /// **'标记已读失败'**
  String get mailFailedMarkRead;

  /// No description provided for @mailFilterType.
  ///
  /// In zh, this message translates to:
  /// **'筛选类型'**
  String get mailFilterType;

  /// No description provided for @mailFrom.
  ///
  /// In zh, this message translates to:
  /// **'来自{p1}'**
  String mailFrom(Object p1);

  /// No description provided for @mailFromMiniWorldOfficial.
  ///
  /// In zh, this message translates to:
  /// **'来自迷你官方'**
  String get mailFromMiniWorldOfficial;

  /// No description provided for @mailGo.
  ///
  /// In zh, this message translates to:
  /// **'前往'**
  String get mailGo;

  /// No description provided for @mailHrAgo.
  ///
  /// In zh, this message translates to:
  /// **'{p1}小时前'**
  String mailHrAgo(Object p1);

  /// No description provided for @mailItem.
  ///
  /// In zh, this message translates to:
  /// **'物品 {p1}'**
  String mailItem(Object p1);

  /// No description provided for @mailLink.
  ///
  /// In zh, this message translates to:
  /// **'链接'**
  String get mailLink;

  /// No description provided for @mailMarkRead.
  ///
  /// In zh, this message translates to:
  /// **'一键已读'**
  String get mailMarkRead;

  /// No description provided for @mailMessageCenter.
  ///
  /// In zh, this message translates to:
  /// **'消息中心'**
  String get mailMessageCenter;

  /// No description provided for @mailMessageDetails.
  ///
  /// In zh, this message translates to:
  /// **'消息详情'**
  String get mailMessageDetails;

  /// No description provided for @mailMinAgo.
  ///
  /// In zh, this message translates to:
  /// **'{p1}分钟前'**
  String mailMinAgo(Object p1);

  /// No description provided for @mailNoContent.
  ///
  /// In zh, this message translates to:
  /// **'（无内容）'**
  String get mailNoContent;

  /// No description provided for @mailNoMessages.
  ///
  /// In zh, this message translates to:
  /// **'暂无消息'**
  String get mailNoMessages;

  /// No description provided for @mailThisLinkTypeIsnt.
  ///
  /// In zh, this message translates to:
  /// **'该跳转类型暂不支持'**
  String get mailThisLinkTypeIsnt;

  /// No description provided for @mailThisMomentDoesntExist.
  ///
  /// In zh, this message translates to:
  /// **'动态不存在或已删除'**
  String get mailThisMomentDoesntExist;

  /// No description provided for @mailUnclaimed.
  ///
  /// In zh, this message translates to:
  /// **'待领取'**
  String get mailUnclaimed;

  /// No description provided for @mailUntitled.
  ///
  /// In zh, this message translates to:
  /// **'（无标题）'**
  String get mailUntitled;

  /// No description provided for @nearbyDistanceUnknown.
  ///
  /// In zh, this message translates to:
  /// **'距离未知'**
  String get nearbyDistanceUnknown;

  /// No description provided for @nearbyEnterValidLatitudeLongitude.
  ///
  /// In zh, this message translates to:
  /// **'请先填写有效的经纬度'**
  String get nearbyEnterValidLatitudeLongitude;

  /// No description provided for @nearbyFailedSave.
  ///
  /// In zh, this message translates to:
  /// **'设置失败: {e}'**
  String nearbyFailedSave(Object e);

  /// No description provided for @nearbyKilometers.
  ///
  /// In zh, this message translates to:
  /// **'{p1} 公里'**
  String nearbyKilometers(Object p1);

  /// No description provided for @nearbyKilometersRounded.
  ///
  /// In zh, this message translates to:
  /// **'{p1} 公里'**
  String nearbyKilometersRounded(Object p1);

  /// No description provided for @nearbyLatitudeExample.
  ///
  /// In zh, this message translates to:
  /// **'如 39.9042'**
  String get nearbyLatitudeExample;

  /// No description provided for @nearbyLatitudeLabel.
  ///
  /// In zh, this message translates to:
  /// **'纬度 latitude'**
  String get nearbyLatitudeLabel;

  /// No description provided for @nearbyLetPeopleNearbyAdd.
  ///
  /// In zh, this message translates to:
  /// **'允许附近的人加我'**
  String get nearbyLetPeopleNearbyAdd;

  /// No description provided for @nearbyLongitudeExample.
  ///
  /// In zh, this message translates to:
  /// **'如 116.4074'**
  String get nearbyLongitudeExample;

  /// No description provided for @nearbyLongitudeLabel.
  ///
  /// In zh, this message translates to:
  /// **'经度 longitude'**
  String get nearbyLongitudeLabel;

  /// No description provided for @nearbyMeters.
  ///
  /// In zh, this message translates to:
  /// **'{p1} 米'**
  String nearbyMeters(Object p1);

  /// No description provided for @nearbyMiniID.
  ///
  /// In zh, this message translates to:
  /// **'迷你号 {p1} · {p2}'**
  String nearbyMiniID(Object p1, Object p2);

  /// No description provided for @nearbyNoOneFoundNearby.
  ///
  /// In zh, this message translates to:
  /// **'附近没有找到人'**
  String get nearbyNoOneFoundNearby;

  /// No description provided for @nearbyPeopleFirstPage.
  ///
  /// In zh, this message translates to:
  /// **'共 {p1} 人（仅显示第 1 页）'**
  String nearbyPeopleFirstPage(Object p1);

  /// No description provided for @nearbyQueryFailed.
  ///
  /// In zh, this message translates to:
  /// **'查询失败：{_error}'**
  String nearbyQueryFailed(Object _error);

  /// No description provided for @nearbyReading.
  ///
  /// In zh, this message translates to:
  /// **'读取中…'**
  String get nearbyReading;

  /// No description provided for @nearbyReportLocationFindPeople.
  ///
  /// In zh, this message translates to:
  /// **'上报位置并查找附近的人'**
  String get nearbyReportLocationFindPeople;

  /// No description provided for @nearbyThisExternalClientSystem.
  ///
  /// In zh, this message translates to:
  /// **'外部客户端未接入系统定位，请手动填写经纬度后再查询。'**
  String get nearbyThisExternalClientSystem;

  /// No description provided for @nearbyWhenEnabledPeopleNearby.
  ///
  /// In zh, this message translates to:
  /// **'开启后附近的人可搜索到我并加好友'**
  String get nearbyWhenEnabledPeopleNearby;

  /// No description provided for @partnerAlias.
  ///
  /// In zh, this message translates to:
  /// **'别称 #{p1}'**
  String partnerAlias(Object p1);

  /// No description provided for @partnerBestPartnerSlotsLeft.
  ///
  /// In zh, this message translates to:
  /// **'最佳拍档剩余空位 x {remaining}'**
  String partnerBestPartnerSlotsLeft(Object remaining);

  /// No description provided for @partnerDaysRelation.
  ///
  /// In zh, this message translates to:
  /// **'结成关系天数：{p1}'**
  String partnerDaysRelation(Object p1);

  /// No description provided for @partnerNoBestPartnersYet.
  ///
  /// In zh, this message translates to:
  /// **'暂无最佳拍档'**
  String get partnerNoBestPartnersYet;

  /// No description provided for @partnerPartnerSlots.
  ///
  /// In zh, this message translates to:
  /// **'可建立拍档数'**
  String get partnerPartnerSlots;

  /// No description provided for @partnerRapport.
  ///
  /// In zh, this message translates to:
  /// **'默契度 {p1}'**
  String partnerRapport(Object p1);

  /// No description provided for @partnerRapport2.
  ///
  /// In zh, this message translates to:
  /// **'默契度 {p1}/{next}'**
  String partnerRapport2(Object next, Object p1);

  /// No description provided for @partnerRapport3.
  ///
  /// In zh, this message translates to:
  /// **'默契度 · {p1}'**
  String partnerRapport3(Object p1);

  /// No description provided for @partnerRapport4.
  ///
  /// In zh, this message translates to:
  /// **'默契度 · {p1}（{p2}/{next}）'**
  String partnerRapport4(Object next, Object p1, Object p2);

  /// No description provided for @partnersAfterDaysWithoutInteracting.
  ///
  /// In zh, this message translates to:
  /// **'连续 {kPartnerStaleDays} 天不互动，默契度每天 -{kPartnerDecayPerDay}'**
  String partnersAfterDaysWithoutInteracting(
    Object kPartnerDecayPerDay,
    Object kPartnerStaleDays,
  );

  /// No description provided for @partnersFailedLoadRecentPlaymates.
  ///
  /// In zh, this message translates to:
  /// **'最近玩伴拉取失败'**
  String get partnersFailedLoadRecentPlaymates;

  /// No description provided for @partnersFindPeopleYouPlayed.
  ///
  /// In zh, this message translates to:
  /// **'退出房间后也能找回一起玩过的人'**
  String get partnersFindPeopleYouPlayed;

  /// No description provided for @partnersMyPartners.
  ///
  /// In zh, this message translates to:
  /// **'我的拍档'**
  String get partnersMyPartners;

  /// No description provided for @partnersNoPartnersYet.
  ///
  /// In zh, this message translates to:
  /// **'还没有拍档'**
  String get partnersNoPartnersYet;

  /// No description provided for @partnersNoPlaymatesYet.
  ///
  /// In zh, this message translates to:
  /// **'还没有一起玩过的伙伴'**
  String get partnersNoPlaymatesYet;

  /// No description provided for @partnersPartner.
  ///
  /// In zh, this message translates to:
  /// **'搭子'**
  String get partnersPartner;

  /// No description provided for @partnersPeopleYouPlayedAppear.
  ///
  /// In zh, this message translates to:
  /// **'进过房间后这里会出现一起玩过的人'**
  String get partnersPeopleYouPlayedAppear;

  /// No description provided for @partnersRapport.
  ///
  /// In zh, this message translates to:
  /// **'默契度 {tacit}'**
  String partnersRapport(Object tacit);

  /// No description provided for @partnersRapportDropWithoutInteraction.
  ///
  /// In zh, this message translates to:
  /// **'默契度 {tacit} → 再不互动会降到 {floor}'**
  String partnersRapportDropWithoutInteraction(Object floor, Object tacit);

  /// No description provided for @partnersRapportNextLevel.
  ///
  /// In zh, this message translates to:
  /// **'默契度 {tacit} / 下一级 {next}'**
  String partnersRapportNextLevel(Object next, Object tacit);

  /// No description provided for @partnersRapportRelationLevelServer.
  ///
  /// In zh, this message translates to:
  /// **'默契度与关系等级（服务端数据）'**
  String get partnersRapportRelationLevelServer;

  /// No description provided for @partnersReach100RapportFriend.
  ///
  /// In zh, this message translates to:
  /// **'在游戏里与好友的默契度达到 100 即可建立拍档关系'**
  String get partnersReach100RapportFriend;

  /// No description provided for @partnersRecentPlaymates.
  ///
  /// In zh, this message translates to:
  /// **'最近玩伴'**
  String get partnersRecentPlaymates;

  /// No description provided for @partnersRecentlyPlayed.
  ///
  /// In zh, this message translates to:
  /// **'最近一起玩过'**
  String get partnersRecentlyPlayed;

  /// No description provided for @partnersRefreshRecentPlaymates.
  ///
  /// In zh, this message translates to:
  /// **'刷新最近玩伴'**
  String get partnersRefreshRecentPlaymates;

  /// No description provided for @partnersTimeInteract.
  ///
  /// In zh, this message translates to:
  /// **'该互动了'**
  String get partnersTimeInteract;

  /// No description provided for @playerInfoAddFriend.
  ///
  /// In zh, this message translates to:
  /// **'加好友'**
  String get playerInfoAddFriend;

  /// No description provided for @playerInfoAdventurer.
  ///
  /// In zh, this message translates to:
  /// **'冒险家：{adv}'**
  String playerInfoAdventurer(Object adv);

  /// No description provided for @playerInfoFriendRequestSent.
  ///
  /// In zh, this message translates to:
  /// **'已发送好友申请'**
  String get playerInfoFriendRequestSent;

  /// No description provided for @playerInfoMyProfile.
  ///
  /// In zh, this message translates to:
  /// **'个人中心'**
  String get playerInfoMyProfile;

  /// No description provided for @playerInfoRapport.
  ///
  /// In zh, this message translates to:
  /// **'默契度：{tacit}'**
  String playerInfoRapport(Object tacit);

  /// No description provided for @playerInfoRequestFailedTryAgain.
  ///
  /// In zh, this message translates to:
  /// **'申请失败，请稍后重试'**
  String get playerInfoRequestFailedTryAgain;

  /// No description provided for @playerInfoSend.
  ///
  /// In zh, this message translates to:
  /// **'赠送'**
  String get playerInfoSend;

  /// No description provided for @profileAlreadyBlocked.
  ///
  /// In zh, this message translates to:
  /// **'已在黑名单'**
  String get profileAlreadyBlocked;

  /// No description provided for @profileAndMaps.
  ///
  /// In zh, this message translates to:
  /// **'等 {p1} 张地图'**
  String profileAndMaps(Object p1);

  /// No description provided for @profileArtwork.
  ///
  /// In zh, this message translates to:
  /// **'立绘'**
  String get profileArtwork;

  /// No description provided for @profileAvatarFrame.
  ///
  /// In zh, this message translates to:
  /// **'头像框'**
  String get profileAvatarFrame;

  /// No description provided for @profileAvatarFrameUpdated.
  ///
  /// In zh, this message translates to:
  /// **'头像框已更新'**
  String get profileAvatarFrameUpdated;

  /// No description provided for @profileBlock.
  ///
  /// In zh, this message translates to:
  /// **'拉黑'**
  String get profileBlock;

  /// No description provided for @profileCharm.
  ///
  /// In zh, this message translates to:
  /// **'魅力值'**
  String get profileCharm;

  /// No description provided for @profileCouldntLoadProfileLayout.
  ///
  /// In zh, this message translates to:
  /// **'未取到主页布局'**
  String get profileCouldntLoadProfileLayout;

  /// No description provided for @profileCreditScore.
  ///
  /// In zh, this message translates to:
  /// **'信用分'**
  String get profileCreditScore;

  /// No description provided for @profileEdit.
  ///
  /// In zh, this message translates to:
  /// **'编辑'**
  String get profileEdit;

  /// No description provided for @profileEditAvatar.
  ///
  /// In zh, this message translates to:
  /// **'头像编辑'**
  String get profileEditAvatar;

  /// No description provided for @profileEditLayout.
  ///
  /// In zh, this message translates to:
  /// **'编辑布局'**
  String get profileEditLayout;

  /// No description provided for @profileFamily.
  ///
  /// In zh, this message translates to:
  /// **'家族: {familyName}'**
  String profileFamily(Object familyName);

  /// No description provided for @profileFavoritesCreated.
  ///
  /// In zh, this message translates to:
  /// **'已创建收藏夹'**
  String get profileFavoritesCreated;

  /// No description provided for @profileFollowers.
  ///
  /// In zh, this message translates to:
  /// **'粉丝'**
  String get profileFollowers;

  /// No description provided for @profileFriendBio.
  ///
  /// In zh, this message translates to:
  /// **'交友宣言'**
  String get profileFriendBio;

  /// No description provided for @profileIPRegion.
  ///
  /// In zh, this message translates to:
  /// **'IP属地：{p1}'**
  String profileIPRegion(Object p1);

  /// No description provided for @profileLayoutSaved.
  ///
  /// In zh, this message translates to:
  /// **'布局已保存'**
  String get profileLayoutSaved;

  /// No description provided for @profileLightChaseProject.
  ///
  /// In zh, this message translates to:
  /// **'追光计划'**
  String get profileLightChaseProject;

  /// No description provided for @profileMedals.
  ///
  /// In zh, this message translates to:
  /// **'勋章'**
  String get profileMedals;

  /// No description provided for @profileMedalsEarned.
  ///
  /// In zh, this message translates to:
  /// **'已获得勋章'**
  String get profileMedalsEarned;

  /// No description provided for @profileMiniIDCopied.
  ///
  /// In zh, this message translates to:
  /// **'迷你号已复制'**
  String get profileMiniIDCopied;

  /// No description provided for @profileMiniTraces.
  ///
  /// In zh, this message translates to:
  /// **'迷你印迹'**
  String get profileMiniTraces;

  /// No description provided for @profileMomentsPublished.
  ///
  /// In zh, this message translates to:
  /// **'已发布 {postingCount} 条动态'**
  String profileMomentsPublished(Object postingCount);

  /// No description provided for @profileMyFavorites.
  ///
  /// In zh, this message translates to:
  /// **'我的收藏夹'**
  String get profileMyFavorites;

  /// No description provided for @profileNoFriendBioSet.
  ///
  /// In zh, this message translates to:
  /// **'还没有设置交友宣言'**
  String get profileNoFriendBioSet;

  /// No description provided for @profileNoOwnedSkinsArtwork.
  ///
  /// In zh, this message translates to:
  /// **'暂未获取到已拥有的皮肤或立绘'**
  String get profileNoOwnedSkinsArtwork;

  /// No description provided for @profileNoPublishedMapWorks.
  ///
  /// In zh, this message translates to:
  /// **'暂无已发布地图作品'**
  String get profileNoPublishedMapWorks;

  /// No description provided for @profileNoTitleEquipped.
  ///
  /// In zh, this message translates to:
  /// **'未佩戴称号'**
  String get profileNoTitleEquipped;

  /// No description provided for @profileOwnAvatarFrames.
  ///
  /// In zh, this message translates to:
  /// **'已拥有 {p1} 个头像框'**
  String profileOwnAvatarFrames(Object p1);

  /// No description provided for @profileOwnStylesLocalIcons.
  ///
  /// In zh, this message translates to:
  /// **'已拥有 {skinModuleCount} 件装扮（本地暂无对应图标）'**
  String profileOwnStylesLocalIcons(Object skinModuleCount);

  /// No description provided for @profilePersonalInfo.
  ///
  /// In zh, this message translates to:
  /// **'个人资料'**
  String get profilePersonalInfo;

  /// No description provided for @profilePersonalStyle.
  ///
  /// In zh, this message translates to:
  /// **'个性装扮'**
  String get profilePersonalStyle;

  /// No description provided for @profilePhotosShownProfile.
  ///
  /// In zh, this message translates to:
  /// **'主页展示的照片'**
  String get profilePhotosShownProfile;

  /// No description provided for @profilePopularity.
  ///
  /// In zh, this message translates to:
  /// **'人气值'**
  String get profilePopularity;

  /// No description provided for @profileProfile.
  ///
  /// In zh, this message translates to:
  /// **'个人主页'**
  String get profileProfile;

  /// No description provided for @profilePublishWork.
  ///
  /// In zh, this message translates to:
  /// **'发布作品'**
  String get profilePublishWork;

  /// No description provided for @profileRecentVisitors.
  ///
  /// In zh, this message translates to:
  /// **'最近访客'**
  String get profileRecentVisitors;

  /// No description provided for @profileRemoveThemBlocklist.
  ///
  /// In zh, this message translates to:
  /// **'确定将 TA 移出黑名单吗？'**
  String get profileRemoveThemBlocklist;

  /// No description provided for @profileStylesCollected.
  ///
  /// In zh, this message translates to:
  /// **'已收集装扮'**
  String get profileStylesCollected;

  /// No description provided for @profileThisExternalClientDoesnt.
  ///
  /// In zh, this message translates to:
  /// **'外部客户端暂不展示动态正文'**
  String get profileThisExternalClientDoesnt;

  /// No description provided for @profileThisExternalClientHasnt.
  ///
  /// In zh, this message translates to:
  /// **'外部客户端暂未获取该项数据'**
  String get profileThisExternalClientHasnt;

  /// No description provided for @profileTitle.
  ///
  /// In zh, this message translates to:
  /// **'称号'**
  String get profileTitle;

  /// No description provided for @profileTotalCharmReceivedGifts.
  ///
  /// In zh, this message translates to:
  /// **'累计收到礼物魅力值'**
  String get profileTotalCharmReceivedGifts;

  /// No description provided for @profileUnfollowed.
  ///
  /// In zh, this message translates to:
  /// **'已取消关注'**
  String get profileUnfollowed;

  /// No description provided for @profileUnnamed.
  ///
  /// In zh, this message translates to:
  /// **'未命名'**
  String get profileUnnamed;

  /// No description provided for @profileUse.
  ///
  /// In zh, this message translates to:
  /// **'使用'**
  String get profileUse;

  /// No description provided for @profileUseArtwork.
  ///
  /// In zh, this message translates to:
  /// **'使用该立绘'**
  String get profileUseArtwork;

  /// No description provided for @profileUseArtworkAvatar.
  ///
  /// In zh, this message translates to:
  /// **'确定使用该立绘作为头像吗？'**
  String get profileUseArtworkAvatar;

  /// No description provided for @profileUseAvatar.
  ///
  /// In zh, this message translates to:
  /// **'使用该头像'**
  String get profileUseAvatar;

  /// No description provided for @profileUseAvatarFrame.
  ///
  /// In zh, this message translates to:
  /// **'使用该头像框'**
  String get profileUseAvatarFrame;

  /// No description provided for @profileUseAvatarFrame2.
  ///
  /// In zh, this message translates to:
  /// **'确定使用头像框 #{id} 吗？'**
  String profileUseAvatarFrame2(Object id);

  /// No description provided for @profileUseSkinAvatar.
  ///
  /// In zh, this message translates to:
  /// **'确定使用该皮肤作为头像吗？'**
  String get profileUseSkinAvatar;

  /// No description provided for @profileViewMoments.
  ///
  /// In zh, this message translates to:
  /// **'查看我的动态'**
  String get profileViewMoments;

  /// No description provided for @profileYouWontSeeTheir.
  ///
  /// In zh, this message translates to:
  /// **'拉黑后将无法看到 TA 的动态与消息，确定？'**
  String get profileYouWontSeeTheir;

  /// No description provided for @publishDynamicsAVoteNeedsTitle.
  ///
  /// In zh, this message translates to:
  /// **'投票需要标题和至少 2 个选项'**
  String get publishDynamicsAVoteNeedsTitle;

  /// No description provided for @publishDynamicsAllowMultipleChoice.
  ///
  /// In zh, this message translates to:
  /// **'允许多选'**
  String get publishDynamicsAllowMultipleChoice;

  /// No description provided for @publishDynamicsAttachVote.
  ///
  /// In zh, this message translates to:
  /// **'附带投票'**
  String get publishDynamicsAttachVote;

  /// No description provided for @publishDynamicsChooseFriends.
  ///
  /// In zh, this message translates to:
  /// **'选择好友'**
  String get publishDynamicsChooseFriends;

  /// No description provided for @publishDynamicsChooseImage.
  ///
  /// In zh, this message translates to:
  /// **'选择图片'**
  String get publishDynamicsChooseImage;

  /// No description provided for @publishDynamicsDeadline.
  ///
  /// In zh, this message translates to:
  /// **'截止时间'**
  String get publishDynamicsDeadline;

  /// No description provided for @publishDynamicsDeadlineMustLeast30.
  ///
  /// In zh, this message translates to:
  /// **'截止时间需晚于当前时间 30 分钟'**
  String get publishDynamicsDeadlineMustLeast30;

  /// No description provided for @publishDynamicsDeleteImage.
  ///
  /// In zh, this message translates to:
  /// **'删除图片'**
  String get publishDynamicsDeleteImage;

  /// No description provided for @publishDynamicsEnterSomeContent.
  ///
  /// In zh, this message translates to:
  /// **'请输入内容'**
  String get publishDynamicsEnterSomeContent;

  /// No description provided for @publishDynamicsFailedChooseImage.
  ///
  /// In zh, this message translates to:
  /// **'选择图片失败：{e}'**
  String publishDynamicsFailedChooseImage(Object e);

  /// No description provided for @publishDynamicsFailedCreateVote.
  ///
  /// In zh, this message translates to:
  /// **'投票创建失败'**
  String get publishDynamicsFailedCreateVote;

  /// No description provided for @publishDynamicsFailedDeleteImage.
  ///
  /// In zh, this message translates to:
  /// **'图片删除失败：{e}'**
  String publishDynamicsFailedDeleteImage(Object e);

  /// No description provided for @publishDynamicsFailedPublishRet.
  ///
  /// In zh, this message translates to:
  /// **'发布失败: ret={p1} {p2}'**
  String publishDynamicsFailedPublishRet(Object p1, Object p2);

  /// No description provided for @publishDynamicsFriends.
  ///
  /// In zh, this message translates to:
  /// **'@好友'**
  String get publishDynamicsFriends;

  /// No description provided for @publishDynamicsFriendsVoteAfterYou.
  ///
  /// In zh, this message translates to:
  /// **'发布后可让好友投票'**
  String get publishDynamicsFriendsVoteAfterYou;

  /// No description provided for @publishDynamicsImageUploadFailed.
  ///
  /// In zh, this message translates to:
  /// **'图片上传失败：{p1}'**
  String publishDynamicsImageUploadFailed(Object p1);

  /// No description provided for @publishDynamicsImageUploadFailed2.
  ///
  /// In zh, this message translates to:
  /// **'图片上传失败：{e}'**
  String publishDynamicsImageUploadFailed2(Object e);

  /// No description provided for @publishDynamicsImages.
  ///
  /// In zh, this message translates to:
  /// **'图片（{p1}/{_maxPics}）'**
  String publishDynamicsImages(Object _maxPics, Object p1);

  /// No description provided for @publishDynamicsNoFriends.
  ///
  /// In zh, this message translates to:
  /// **'暂无好友可 @'**
  String get publishDynamicsNoFriends;

  /// No description provided for @publishDynamicsOption.
  ///
  /// In zh, this message translates to:
  /// **'选项 {p1}'**
  String publishDynamicsOption(Object p1);

  /// No description provided for @publishDynamicsPublished.
  ///
  /// In zh, this message translates to:
  /// **'发布成功'**
  String get publishDynamicsPublished;

  /// No description provided for @publishDynamicsSearchTopics.
  ///
  /// In zh, this message translates to:
  /// **'搜索话题'**
  String get publishDynamicsSearchTopics;

  /// No description provided for @publishDynamicsShareSomethingNew.
  ///
  /// In zh, this message translates to:
  /// **'分享新鲜事…'**
  String get publishDynamicsShareSomethingNew;

  /// No description provided for @publishDynamicsSomeImagesHaventFinished.
  ///
  /// In zh, this message translates to:
  /// **'有图片尚未上传成功'**
  String get publishDynamicsSomeImagesHaventFinished;

  /// No description provided for @publishDynamicsTopicOptional.
  ///
  /// In zh, this message translates to:
  /// **'话题（可选）'**
  String get publishDynamicsTopicOptional;

  /// No description provided for @publishDynamicsUploadingImagesWait.
  ///
  /// In zh, this message translates to:
  /// **'图片上传中，请稍候'**
  String get publishDynamicsUploadingImagesWait;

  /// No description provided for @publishDynamicsVisibility.
  ///
  /// In zh, this message translates to:
  /// **'可见范围'**
  String get publishDynamicsVisibility;

  /// No description provided for @publishDynamicsVoteTitle.
  ///
  /// In zh, this message translates to:
  /// **'投票标题'**
  String get publishDynamicsVoteTitle;

  /// No description provided for @publishDynamicsYouUploadMostImages.
  ///
  /// In zh, this message translates to:
  /// **'最多只能上传 {_maxPics} 张图片'**
  String publishDynamicsYouUploadMostImages(Object _maxPics);

  /// No description provided for @qrAskThemEnterNumber.
  ///
  /// In zh, this message translates to:
  /// **'让对方在「好友 → 按迷你号添加」中输入此号码'**
  String get qrAskThemEnterNumber;

  /// No description provided for @qrCopyMiniID.
  ///
  /// In zh, this message translates to:
  /// **'复制迷你号'**
  String get qrCopyMiniID;

  /// No description provided for @qrMyMiniID.
  ///
  /// In zh, this message translates to:
  /// **'我的迷你号'**
  String get qrMyMiniID;

  /// No description provided for @relationFollowers.
  ///
  /// In zh, this message translates to:
  /// **'我的粉丝 {p1}'**
  String relationFollowers(Object p1);

  /// No description provided for @relationFollowing.
  ///
  /// In zh, this message translates to:
  /// **'我的关注 {p1}'**
  String relationFollowing(Object p1);

  /// No description provided for @relationNoFollowersYet.
  ///
  /// In zh, this message translates to:
  /// **'还没有粉丝'**
  String get relationNoFollowersYet;

  /// No description provided for @relationNotFollowingAnyoneYet.
  ///
  /// In zh, this message translates to:
  /// **'还没有关注任何人'**
  String get relationNotFollowingAnyoneYet;

  /// No description provided for @requestErrorCopyURL.
  ///
  /// In zh, this message translates to:
  /// **'复制地址'**
  String get requestErrorCopyURL;

  /// No description provided for @requestErrorFailedRequests.
  ///
  /// In zh, this message translates to:
  /// **'请求失败记录'**
  String get requestErrorFailedRequests;

  /// No description provided for @requestErrorNoFailureRecordsYet.
  ///
  /// In zh, this message translates to:
  /// **'暂无失败记录'**
  String get requestErrorNoFailureRecordsYet;

  /// No description provided for @requestErrorNoUrl.
  ///
  /// In zh, this message translates to:
  /// **'(无请求地址)'**
  String get requestErrorNoUrl;

  /// No description provided for @requestErrorRequestURLCopied.
  ///
  /// In zh, this message translates to:
  /// **'已复制请求地址'**
  String get requestErrorRequestURLCopied;

  /// No description provided for @requestErrorRequestsFailed.
  ///
  /// In zh, this message translates to:
  /// **'{total} 个请求失败'**
  String requestErrorRequestsFailed(Object total);

  /// No description provided for @sessionMenuCancelDoDisturb.
  ///
  /// In zh, this message translates to:
  /// **'取消免打扰'**
  String get sessionMenuCancelDoDisturb;

  /// No description provided for @sessionMenuCancelOnlineNotification.
  ///
  /// In zh, this message translates to:
  /// **'取消上线通知'**
  String get sessionMenuCancelOnlineNotification;

  /// No description provided for @sessionMenuDeleteFriend.
  ///
  /// In zh, this message translates to:
  /// **'删除好友'**
  String get sessionMenuDeleteFriend;

  /// No description provided for @sessionMenuDeleteFriend2.
  ///
  /// In zh, this message translates to:
  /// **'确定删除好友「{p1}」吗？'**
  String sessionMenuDeleteFriend2(Object p1);

  /// No description provided for @sessionMenuDoDisturb.
  ///
  /// In zh, this message translates to:
  /// **'免打扰'**
  String get sessionMenuDoDisturb;

  /// No description provided for @sessionMenuDoDisturb2.
  ///
  /// In zh, this message translates to:
  /// **'已开启免打扰'**
  String get sessionMenuDoDisturb2;

  /// No description provided for @sessionMenuDoDisturbOff.
  ///
  /// In zh, this message translates to:
  /// **'已取消免打扰'**
  String get sessionMenuDoDisturbOff;

  /// No description provided for @sessionMenuEnterNoteNameLeave.
  ///
  /// In zh, this message translates to:
  /// **'输入备注名，留空则清除'**
  String get sessionMenuEnterNoteNameLeave;

  /// No description provided for @sessionMenuFailedNudge.
  ///
  /// In zh, this message translates to:
  /// **'拍一拍失败'**
  String get sessionMenuFailedNudge;

  /// No description provided for @sessionMenuFriendDeleted.
  ///
  /// In zh, this message translates to:
  /// **'已删除好友'**
  String get sessionMenuFriendDeleted;

  /// No description provided for @sessionMenuNote.
  ///
  /// In zh, this message translates to:
  /// **'备注'**
  String get sessionMenuNote;

  /// No description provided for @sessionMenuNoteName.
  ///
  /// In zh, this message translates to:
  /// **'备注名'**
  String get sessionMenuNoteName;

  /// No description provided for @sessionMenuNoteSaved.
  ///
  /// In zh, this message translates to:
  /// **'备注已保存'**
  String get sessionMenuNoteSaved;

  /// No description provided for @sessionMenuNudge.
  ///
  /// In zh, this message translates to:
  /// **'拍一拍'**
  String get sessionMenuNudge;

  /// No description provided for @sessionMenuNudged.
  ///
  /// In zh, this message translates to:
  /// **'已拍一拍'**
  String get sessionMenuNudged;

  /// No description provided for @sessionMenuOnlineNotification.
  ///
  /// In zh, this message translates to:
  /// **'已开启上线通知'**
  String get sessionMenuOnlineNotification;

  /// No description provided for @sessionMenuOnlineNotificationOff.
  ///
  /// In zh, this message translates to:
  /// **'已关闭上线通知'**
  String get sessionMenuOnlineNotificationOff;

  /// No description provided for @sessionMenuRemoveConversation.
  ///
  /// In zh, this message translates to:
  /// **'移除会话'**
  String get sessionMenuRemoveConversation;

  /// No description provided for @sessionsConversationRemoved.
  ///
  /// In zh, this message translates to:
  /// **'已移除会话'**
  String get sessionsConversationRemoved;

  /// No description provided for @sessionsFriend.
  ///
  /// In zh, this message translates to:
  /// **'好友 {p1}'**
  String sessionsFriend(Object p1);

  /// No description provided for @sessionsGroup.
  ///
  /// In zh, this message translates to:
  /// **'群 {p1}'**
  String sessionsGroup(Object p1);

  /// No description provided for @sessionsNoConversationsPeopleYou.
  ///
  /// In zh, this message translates to:
  /// **'暂无会话\n聊过天的人会出现在这里'**
  String get sessionsNoConversationsPeopleYou;

  /// No description provided for @sessionsNoMatchingConversations.
  ///
  /// In zh, this message translates to:
  /// **'没有匹配的会话'**
  String get sessionsNoMatchingConversations;

  /// No description provided for @sessionsOnlyConversationsChattedDevice.
  ///
  /// In zh, this message translates to:
  /// **'历史消息只保留本机聊过的会话'**
  String get sessionsOnlyConversationsChattedDevice;

  /// No description provided for @sessionsSearchConversationsNicknameMini.
  ///
  /// In zh, this message translates to:
  /// **'搜索会话（昵称或迷你号）'**
  String get sessionsSearchConversationsNicknameMini;

  /// No description provided for @sessionsSearchMiniIDNickname.
  ///
  /// In zh, this message translates to:
  /// **'支持迷你号和昵称查找'**
  String get sessionsSearchMiniIDNickname;

  /// No description provided for @settingsAboutAbout.
  ///
  /// In zh, this message translates to:
  /// **'关于'**
  String get settingsAboutAbout;

  /// No description provided for @settingsAboutAlreadyUpDate.
  ///
  /// In zh, this message translates to:
  /// **'已是最新版本（{kAppVersion}）'**
  String settingsAboutAlreadyUpDate(Object kAppVersion);

  /// No description provided for @settingsAboutAppPrivateDirectoryAuto.
  ///
  /// In zh, this message translates to:
  /// **'应用私有目录（自动轮转）'**
  String get settingsAboutAppPrivateDirectoryAuto;

  /// No description provided for @settingsAboutCheckFailedYouAlso.
  ///
  /// In zh, this message translates to:
  /// **'检查失败：{p1}\n\n也可以直接到 Releases 页面查看：\n'**
  String settingsAboutCheckFailedYouAlso(Object p1);

  /// No description provided for @settingsAboutCheckLatestBuildGitHub.
  ///
  /// In zh, this message translates to:
  /// **'查询 GitHub 上的最新构建'**
  String get settingsAboutCheckLatestBuildGitHub;

  /// No description provided for @settingsAboutCheckUpdates.
  ///
  /// In zh, this message translates to:
  /// **'检查更新'**
  String get settingsAboutCheckUpdates;

  /// No description provided for @settingsAboutChecking.
  ///
  /// In zh, this message translates to:
  /// **'正在检查…'**
  String get settingsAboutChecking;

  /// No description provided for @settingsAboutClearLogs.
  ///
  /// In zh, this message translates to:
  /// **'清空日志'**
  String get settingsAboutClearLogs;

  /// No description provided for @settingsAboutDeleteRotatedLogFiles.
  ///
  /// In zh, this message translates to:
  /// **'删除全部轮转日志文件'**
  String get settingsAboutDeleteRotatedLogFiles;

  /// No description provided for @settingsAboutExportDiagnostics.
  ///
  /// In zh, this message translates to:
  /// **'导出诊断信息'**
  String get settingsAboutExportDiagnostics;

  /// No description provided for @settingsAboutFailedClear.
  ///
  /// In zh, this message translates to:
  /// **'清空失败：{e}'**
  String settingsAboutFailedClear(Object e);

  /// No description provided for @settingsAboutFailedCollectDiagnostics.
  ///
  /// In zh, this message translates to:
  /// **'汇总诊断失败：{e}'**
  String settingsAboutFailedCollectDiagnostics(Object e);

  /// No description provided for @settingsAboutGotIt.
  ///
  /// In zh, this message translates to:
  /// **'知道了'**
  String get settingsAboutGotIt;

  /// No description provided for @settingsAboutLogFiles.
  ///
  /// In zh, this message translates to:
  /// **'日志文件'**
  String get settingsAboutLogFiles;

  /// No description provided for @settingsAboutLogsCleared.
  ///
  /// In zh, this message translates to:
  /// **'日志已清空'**
  String get settingsAboutLogsCleared;

  /// No description provided for @settingsAboutMnChat.
  ///
  /// In zh, this message translates to:
  /// **'关于 MnChat'**
  String get settingsAboutMnChat;

  /// No description provided for @settingsAboutNewVersionAvailableCurrent.
  ///
  /// In zh, this message translates to:
  /// **'发现新版本 {p1}（当前 {kAppVersion}）\n\n{p2}'**
  String settingsAboutNewVersionAvailableCurrent(
    Object kAppVersion,
    Object p1,
    Object p2,
  );

  /// No description provided for @settingsAboutNewVersionFound.
  ///
  /// In zh, this message translates to:
  /// **'发现新版本'**
  String get settingsAboutNewVersionFound;

  /// No description provided for @settingsAboutNoLogsYet.
  ///
  /// In zh, this message translates to:
  /// **'暂无日志'**
  String get settingsAboutNoLogsYet;

  /// No description provided for @settingsAboutNone.
  ///
  /// In zh, this message translates to:
  /// **'（无）'**
  String get settingsAboutNone;

  /// No description provided for @settingsAboutOpenSourceLicenses.
  ///
  /// In zh, this message translates to:
  /// **'开源许可'**
  String get settingsAboutOpenSourceLicenses;

  /// No description provided for @settingsAboutOther.
  ///
  /// In zh, this message translates to:
  /// **'其他'**
  String get settingsAboutOther;

  /// No description provided for @settingsAboutRecentRequestFailures.
  ///
  /// In zh, this message translates to:
  /// **'## 最近的请求失败'**
  String get settingsAboutRecentRequestFailures;

  /// No description provided for @settingsAboutThirdPartyDependenciesLicenses.
  ///
  /// In zh, this message translates to:
  /// **'第三方依赖与许可证'**
  String get settingsAboutThirdPartyDependenciesLicenses;

  /// No description provided for @settingsAboutVersion.
  ///
  /// In zh, this message translates to:
  /// **'版本'**
  String get settingsAboutVersion;

  /// No description provided for @settingsAboutVersionPlatformTableCounts.
  ///
  /// In zh, this message translates to:
  /// **'版本 / 平台 / 表计数 / 日志尾部 / 最近请求失败'**
  String get settingsAboutVersionPlatformTableCounts;

  /// No description provided for @settingsAccount.
  ///
  /// In zh, this message translates to:
  /// **'账号'**
  String get settingsAccount;

  /// No description provided for @settingsAccountAccountSecurity.
  ///
  /// In zh, this message translates to:
  /// **'账号与安全'**
  String get settingsAccountAccountSecurity;

  /// No description provided for @settingsAccountAppLock.
  ///
  /// In zh, this message translates to:
  /// **'应用锁'**
  String get settingsAccountAppLock;

  /// No description provided for @settingsAccountAppLockDisabled.
  ///
  /// In zh, this message translates to:
  /// **'已关闭应用锁'**
  String get settingsAccountAppLockDisabled;

  /// No description provided for @settingsAccountAppLockEnabled.
  ///
  /// In zh, this message translates to:
  /// **'已开启应用锁'**
  String get settingsAccountAppLockEnabled;

  /// No description provided for @settingsAccountAutoSign.
  ///
  /// In zh, this message translates to:
  /// **'自动登录'**
  String get settingsAccountAutoSign;

  /// No description provided for @settingsAccountAutoSignDisabled.
  ///
  /// In zh, this message translates to:
  /// **'已关闭自动登录'**
  String get settingsAccountAutoSignDisabled;

  /// No description provided for @settingsAccountAutoSignEnabledCredentials.
  ///
  /// In zh, this message translates to:
  /// **'已开启自动登录（下次登录将保存凭据）'**
  String get settingsAccountAutoSignEnabledCredentials;

  /// No description provided for @settingsAccountDigits48.
  ///
  /// In zh, this message translates to:
  /// **'4-8 位数字'**
  String get settingsAccountDigits48;

  /// No description provided for @settingsAccountDigits68.
  ///
  /// In zh, this message translates to:
  /// **'6-8 位数字'**
  String get settingsAccountDigits68;

  /// No description provided for @settingsAccountEnterAppLockPassword.
  ///
  /// In zh, this message translates to:
  /// **'输入应用锁密码'**
  String get settingsAccountEnterAppLockPassword;

  /// No description provided for @settingsAccountPasswordLength.
  ///
  /// In zh, this message translates to:
  /// **'密码需为 6-8 位数字'**
  String get settingsAccountPasswordLength;

  /// No description provided for @settingsAccountPasswordsDontMatch.
  ///
  /// In zh, this message translates to:
  /// **'两次输入不一致'**
  String get settingsAccountPasswordsDontMatch;

  /// No description provided for @settingsAccountProfile.
  ///
  /// In zh, this message translates to:
  /// **'资料'**
  String get settingsAccountProfile;

  /// No description provided for @settingsAccountReEnterPassword.
  ///
  /// In zh, this message translates to:
  /// **'再次输入密码'**
  String get settingsAccountReEnterPassword;

  /// No description provided for @settingsAccountRequirePasswordLaunchReturning.
  ///
  /// In zh, this message translates to:
  /// **'启动 / 回前台时需输入密码解锁'**
  String get settingsAccountRequirePasswordLaunchReturning;

  /// No description provided for @settingsAccountSecurity.
  ///
  /// In zh, this message translates to:
  /// **'安全'**
  String get settingsAccountSecurity;

  /// No description provided for @settingsAccountSetAppLockPassword.
  ///
  /// In zh, this message translates to:
  /// **'设置应用锁密码'**
  String get settingsAccountSetAppLockPassword;

  /// No description provided for @settingsAccountSetBioWantLike.
  ///
  /// In zh, this message translates to:
  /// **'设置我的个性签名（想要/喜欢）'**
  String get settingsAccountSetBioWantLike;

  /// No description provided for @settingsAccountSignAutomaticallyNextLaunch.
  ///
  /// In zh, this message translates to:
  /// **'开启后下次启动自动登录（需先登录一次以保存凭据）'**
  String get settingsAccountSignAutomaticallyNextLaunch;

  /// No description provided for @settingsAccountSocialTags.
  ///
  /// In zh, this message translates to:
  /// **'交友标签'**
  String get settingsAccountSocialTags;

  /// No description provided for @settingsAccountViewAvatarEditNickname.
  ///
  /// In zh, this message translates to:
  /// **'查看头像 / 修改昵称 / 头像框'**
  String get settingsAccountViewAvatarEditNickname;

  /// No description provided for @settingsAppLock.
  ///
  /// In zh, this message translates to:
  /// **'应用锁已开启'**
  String get settingsAppLock;

  /// No description provided for @settingsDark.
  ///
  /// In zh, this message translates to:
  /// **'深色'**
  String get settingsDark;

  /// No description provided for @settingsFollowSystem.
  ///
  /// In zh, this message translates to:
  /// **'跟随系统'**
  String get settingsFollowSystem;

  /// No description provided for @settingsFriendRequestLimitsVisit.
  ///
  /// In zh, this message translates to:
  /// **'加好友限制 / 访问踪迹 / 聊天记录 / 存储占用'**
  String get settingsFriendRequestLimitsVisit;

  /// No description provided for @settingsGeneralAppearance.
  ///
  /// In zh, this message translates to:
  /// **'外观'**
  String get settingsGeneralAppearance;

  /// No description provided for @settingsGeneralAvatarFrameAnimation.
  ///
  /// In zh, this message translates to:
  /// **'头像框动画'**
  String get settingsGeneralAvatarFrameAnimation;

  /// No description provided for @settingsGeneralCloseTray.
  ///
  /// In zh, this message translates to:
  /// **'关闭到托盘'**
  String get settingsGeneralCloseTray;

  /// No description provided for @settingsGeneralConversationOrder.
  ///
  /// In zh, this message translates to:
  /// **'会话排序'**
  String get settingsGeneralConversationOrder;

  /// No description provided for @settingsGeneralDesktop.
  ///
  /// In zh, this message translates to:
  /// **'桌面'**
  String get settingsGeneralDesktop;

  /// No description provided for @settingsGeneralGeneralAppearance.
  ///
  /// In zh, this message translates to:
  /// **'通用与外观'**
  String get settingsGeneralGeneralAppearance;

  /// No description provided for @settingsGeneralLightDarkModeAccent.
  ///
  /// In zh, this message translates to:
  /// **'明暗模式 / 强调色 / 聊天字号'**
  String get settingsGeneralLightDarkModeAccent;

  /// No description provided for @settingsGeneralMinimizeSystemTrayInstead.
  ///
  /// In zh, this message translates to:
  /// **'关闭窗口时最小化到系统托盘而非退出'**
  String get settingsGeneralMinimizeSystemTrayInstead;

  /// No description provided for @settingsGeneralMinimizeTrayWhenClosing.
  ///
  /// In zh, this message translates to:
  /// **'关闭窗口时将最小化到托盘'**
  String get settingsGeneralMinimizeTrayWhenClosing;

  /// No description provided for @settingsGeneralNoSystemTrayAvailable.
  ///
  /// In zh, this message translates to:
  /// **'当前桌面没有可用的系统托盘，关闭窗口会直接退出（已自动关闭）'**
  String get settingsGeneralNoSystemTrayAvailable;

  /// No description provided for @settingsGeneralQuitWhenClosingWindow.
  ///
  /// In zh, this message translates to:
  /// **'关闭窗口时将直接退出'**
  String get settingsGeneralQuitWhenClosingWindow;

  /// No description provided for @settingsGeneralSwitchBetweenOwnedChat.
  ///
  /// In zh, this message translates to:
  /// **'切换已拥有的聊天气泡'**
  String get settingsGeneralSwitchBetweenOwnedChat;

  /// No description provided for @settingsGeneralThemeDisplaySettings.
  ///
  /// In zh, this message translates to:
  /// **'主题显示设置'**
  String get settingsGeneralThemeDisplaySettings;

  /// No description provided for @settingsGeneralWhenOffStaticAvatar.
  ///
  /// In zh, this message translates to:
  /// **'关闭后仅显示静态头像框，省电省流'**
  String get settingsGeneralWhenOffStaticAvatar;

  /// No description provided for @settingsLight.
  ///
  /// In zh, this message translates to:
  /// **'浅色'**
  String get settingsLight;

  /// No description provided for @settingsNotificationAdd.
  ///
  /// In zh, this message translates to:
  /// **'添加'**
  String get settingsNotificationAdd;

  /// No description provided for @settingsNotificationAddPhrase.
  ///
  /// In zh, this message translates to:
  /// **'新增短语'**
  String get settingsNotificationAddPhrase;

  /// No description provided for @settingsNotificationAddQuickPhrase.
  ///
  /// In zh, this message translates to:
  /// **'新增快捷短语'**
  String get settingsNotificationAddQuickPhrase;

  /// No description provided for @settingsNotificationBackgroundConnectionDisabled.
  ///
  /// In zh, this message translates to:
  /// **'已关闭后台保持连接'**
  String get settingsNotificationBackgroundConnectionDisabled;

  /// No description provided for @settingsNotificationBackgroundConnectionEnabled.
  ///
  /// In zh, this message translates to:
  /// **'已开启后台保持连接'**
  String get settingsNotificationBackgroundConnectionEnabled;

  /// No description provided for @settingsNotificationBackgroundNotificationsArentSupported.
  ///
  /// In zh, this message translates to:
  /// **'当前平台不支持后台通知'**
  String get settingsNotificationBackgroundNotificationsArentSupported;

  /// No description provided for @settingsNotificationClearUnreadMarkerWhen.
  ///
  /// In zh, this message translates to:
  /// **'打开会话即清除未读标记'**
  String get settingsNotificationClearUnreadMarkerWhen;

  /// No description provided for @settingsNotificationDoDisturbEnds.
  ///
  /// In zh, this message translates to:
  /// **'免打扰结束'**
  String get settingsNotificationDoDisturbEnds;

  /// No description provided for @settingsNotificationDoDisturbHours.
  ///
  /// In zh, this message translates to:
  /// **'免打扰时段'**
  String get settingsNotificationDoDisturbHours;

  /// No description provided for @settingsNotificationDoDisturbHoursUpdated.
  ///
  /// In zh, this message translates to:
  /// **'免打扰时段已更新'**
  String get settingsNotificationDoDisturbHoursUpdated;

  /// No description provided for @settingsNotificationDoDisturbStarts.
  ///
  /// In zh, this message translates to:
  /// **'免打扰开始'**
  String get settingsNotificationDoDisturbStarts;

  /// No description provided for @settingsNotificationEnterPhraseContent.
  ///
  /// In zh, this message translates to:
  /// **'输入短语内容'**
  String get settingsNotificationEnterPhraseContent;

  /// No description provided for @settingsNotificationHideNotificationContent.
  ///
  /// In zh, this message translates to:
  /// **'通知隐藏内容'**
  String get settingsNotificationHideNotificationContent;

  /// No description provided for @settingsNotificationInsertQuicklyWhenSending.
  ///
  /// In zh, this message translates to:
  /// **'发送消息时快捷插入（对齐游戏内置 SecretQuickMsg）'**
  String get settingsNotificationInsertQuicklyWhenSending;

  /// No description provided for @settingsNotificationKeepConnectionBackground.
  ///
  /// In zh, this message translates to:
  /// **'后台保持连接'**
  String get settingsNotificationKeepConnectionBackground;

  /// No description provided for @settingsNotificationLongPressConversationList.
  ///
  /// In zh, this message translates to:
  /// **'在会话列表长按某条会话设置'**
  String get settingsNotificationLongPressConversationList;

  /// No description provided for @settingsNotificationMarkReadOpen.
  ///
  /// In zh, this message translates to:
  /// **'进入会话自动已读'**
  String get settingsNotificationMarkReadOpen;

  /// No description provided for @settingsNotificationMessages.
  ///
  /// In zh, this message translates to:
  /// **'消息'**
  String get settingsNotificationMessages;

  /// No description provided for @settingsNotificationMessagesNotifications.
  ///
  /// In zh, this message translates to:
  /// **'消息与通知'**
  String get settingsNotificationMessagesNotifications;

  /// No description provided for @settingsNotificationNewMessageNotifications.
  ///
  /// In zh, this message translates to:
  /// **'新消息通知'**
  String get settingsNotificationNewMessageNotifications;

  /// No description provided for @settingsNotificationNewMessageNotificationsDisabled.
  ///
  /// In zh, this message translates to:
  /// **'已关闭新消息通知'**
  String get settingsNotificationNewMessageNotificationsDisabled;

  /// No description provided for @settingsNotificationNewMessageNotificationsEnabled.
  ///
  /// In zh, this message translates to:
  /// **'已开启新消息通知'**
  String get settingsNotificationNewMessageNotificationsEnabled;

  /// No description provided for @settingsNotificationNoPhrasesYet.
  ///
  /// In zh, this message translates to:
  /// **'暂无短语'**
  String get settingsNotificationNoPhrasesYet;

  /// No description provided for @settingsNotificationNotificationSound.
  ///
  /// In zh, this message translates to:
  /// **'通知提示音'**
  String get settingsNotificationNotificationSound;

  /// No description provided for @settingsNotificationNotificationVibration.
  ///
  /// In zh, this message translates to:
  /// **'通知震动'**
  String get settingsNotificationNotificationVibration;

  /// No description provided for @settingsNotificationNotifications.
  ///
  /// In zh, this message translates to:
  /// **'通知'**
  String get settingsNotificationNotifications;

  /// No description provided for @settingsNotificationOnDesktopPressEnter.
  ///
  /// In zh, this message translates to:
  /// **'桌面端按 Enter 发送，Shift+Enter 换行'**
  String get settingsNotificationOnDesktopPressEnter;

  /// No description provided for @settingsNotificationOnlyAlertMeMentions.
  ///
  /// In zh, this message translates to:
  /// **'群里仅 @我 时提醒'**
  String get settingsNotificationOnlyAlertMeMentions;

  /// No description provided for @settingsNotificationPerConversationMutePin.
  ///
  /// In zh, this message translates to:
  /// **'会话级免打扰 / 置顶'**
  String get settingsNotificationPerConversationMutePin;

  /// No description provided for @settingsNotificationPhraseAlreadyExistsInvalid.
  ///
  /// In zh, this message translates to:
  /// **'短语已存在或内容无效'**
  String get settingsNotificationPhraseAlreadyExistsInvalid;

  /// No description provided for @settingsNotificationQuickPhrases.
  ///
  /// In zh, this message translates to:
  /// **'快捷短语'**
  String get settingsNotificationQuickPhrases;

  /// No description provided for @settingsNotificationSendEnter.
  ///
  /// In zh, this message translates to:
  /// **'回车发送'**
  String get settingsNotificationSendEnter;

  /// No description provided for @settingsNotificationShowNewMessageAlert.
  ///
  /// In zh, this message translates to:
  /// **'锁屏 / 通知栏只提示有新消息，不显示正文'**
  String get settingsNotificationShowNewMessageAlert;

  /// No description provided for @settingsNotificationShowSystemNotificationNew.
  ///
  /// In zh, this message translates to:
  /// **'应用在后台时收到新消息弹出系统通知'**
  String get settingsNotificationShowSystemNotificationNew;

  /// No description provided for @settingsNotificationTheForegroundServiceKeeps.
  ///
  /// In zh, this message translates to:
  /// **'由前台服务维持长连接，后台也能收到新消息'**
  String get settingsNotificationTheForegroundServiceKeeps;

  /// No description provided for @settingsNotificationVibrateWhenNewMessage.
  ///
  /// In zh, this message translates to:
  /// **'收到新消息时震动提醒'**
  String get settingsNotificationVibrateWhenNewMessage;

  /// No description provided for @settingsNotificationWhenGroupMessagesNotify.
  ///
  /// In zh, this message translates to:
  /// **'开启后群消息只有提到我（正文含 @我的昵称）才弹通知，私聊不受影响'**
  String get settingsNotificationWhenGroupMessagesNotify;

  /// No description provided for @settingsNotificationWhenOffNotificationsArrive.
  ///
  /// In zh, this message translates to:
  /// **'关闭后通知静默到达（通知本身照常出现）'**
  String get settingsNotificationWhenOffNotificationsArrive;

  /// No description provided for @settingsNotificationYouWontReceiveSystem.
  ///
  /// In zh, this message translates to:
  /// **'应用退到后台后不会收到系统通知。'**
  String get settingsNotificationYouWontReceiveSystem;

  /// No description provided for @settingsNotificationsDoDisturb.
  ///
  /// In zh, this message translates to:
  /// **'通知开 · 免打扰 {p1}'**
  String settingsNotificationsDoDisturb(Object p1);

  /// No description provided for @settingsNotificationsDoDisturb2.
  ///
  /// In zh, this message translates to:
  /// **'通知开 · 未设免打扰'**
  String get settingsNotificationsDoDisturb2;

  /// No description provided for @settingsNotificationsOff.
  ///
  /// In zh, this message translates to:
  /// **'通知已关闭'**
  String get settingsNotificationsOff;

  /// No description provided for @settingsPreferences.
  ///
  /// In zh, this message translates to:
  /// **'偏好'**
  String get settingsPreferences;

  /// No description provided for @settingsPrivacyAllowOthersAddMe.
  ///
  /// In zh, this message translates to:
  /// **'允许他人拉我入群'**
  String get settingsPrivacyAllowOthersAddMe;

  /// No description provided for @settingsPrivacyAutomaticallyJoinInvitedGroups.
  ///
  /// In zh, this message translates to:
  /// **'自动加入被邀请的群'**
  String get settingsPrivacyAutomaticallyJoinInvitedGroups;

  /// No description provided for @settingsPrivacyBlockFriendRequestsStrangers.
  ///
  /// In zh, this message translates to:
  /// **'拒绝陌生人加好友'**
  String get settingsPrivacyBlockFriendRequestsStrangers;

  /// No description provided for @settingsPrivacyClearImageCache.
  ///
  /// In zh, this message translates to:
  /// **'清除图片缓存'**
  String get settingsPrivacyClearImageCache;

  /// No description provided for @settingsPrivacyClearing.
  ///
  /// In zh, this message translates to:
  /// **'正在清除…'**
  String get settingsPrivacyClearing;

  /// No description provided for @settingsPrivacyCounting.
  ///
  /// In zh, this message translates to:
  /// **'正在统计…'**
  String get settingsPrivacyCounting;

  /// No description provided for @settingsPrivacyData.
  ///
  /// In zh, this message translates to:
  /// **'隐私与数据'**
  String get settingsPrivacyData;

  /// No description provided for @settingsPrivacyData2.
  ///
  /// In zh, this message translates to:
  /// **'数据'**
  String get settingsPrivacyData2;

  /// No description provided for @settingsPrivacyDatabaseSizeRetentionClear.
  ///
  /// In zh, this message translates to:
  /// **'数据库占用 / 保留期 / 按会话清理 / VACUUM'**
  String get settingsPrivacyDatabaseSizeRetentionClear;

  /// No description provided for @settingsPrivacyDeletesCachedAvatarsMoment.
  ///
  /// In zh, this message translates to:
  /// **'将删除已缓存的头像与动态图片，下次显示时重新下载。聊天记录不受影响。'**
  String get settingsPrivacyDeletesCachedAvatarsMoment;

  /// No description provided for @settingsPrivacyDisabledStrangersAddMe.
  ///
  /// In zh, this message translates to:
  /// **'已关闭：允许陌生人加好友'**
  String get settingsPrivacyDisabledStrangersAddMe;

  /// No description provided for @settingsPrivacyEnabledStrangersCantAdd.
  ///
  /// In zh, this message translates to:
  /// **'已开启：拒绝陌生人加好友'**
  String get settingsPrivacyEnabledStrangersCantAdd;

  /// No description provided for @settingsPrivacyExportImportChatData.
  ///
  /// In zh, this message translates to:
  /// **'导出 / 导入聊天数据备份'**
  String get settingsPrivacyExportImportChatData;

  /// No description provided for @settingsPrivacyImageCacheCleared.
  ///
  /// In zh, this message translates to:
  /// **'图片缓存已清除'**
  String get settingsPrivacyImageCacheCleared;

  /// No description provided for @settingsPrivacyLeaveTraceWhenVisiting.
  ///
  /// In zh, this message translates to:
  /// **'访问主页留下踪迹'**
  String get settingsPrivacyLeaveTraceWhenVisiting;

  /// No description provided for @settingsPrivacyPrivacy.
  ///
  /// In zh, this message translates to:
  /// **'隐私'**
  String get settingsPrivacyPrivacy;

  /// No description provided for @settingsPrivacyStorageManagement.
  ///
  /// In zh, this message translates to:
  /// **'存储管理'**
  String get settingsPrivacyStorageManagement;

  /// No description provided for @settingsPrivacyUsingAvatarsMomentImages.
  ///
  /// In zh, this message translates to:
  /// **'当前占用 {p1}（头像与动态图片）'**
  String settingsPrivacyUsingAvatarsMomentImages(Object p1);

  /// No description provided for @settingsPrivacyWhenIJoinAutomatically.
  ///
  /// In zh, this message translates to:
  /// **'开启后收到邀请将自动进群'**
  String get settingsPrivacyWhenIJoinAutomatically;

  /// No description provided for @settingsPrivacyWhenOffInvitationsOthers.
  ///
  /// In zh, this message translates to:
  /// **'关闭后他人邀请将被拒绝'**
  String get settingsPrivacyWhenOffInvitationsOthers;

  /// No description provided for @settingsPrivacyWhenOffViewingSomeones.
  ///
  /// In zh, this message translates to:
  /// **'关闭后，查看他人主页不会出现在对方的访客记录中'**
  String get settingsPrivacyWhenOffViewingSomeones;

  /// No description provided for @settingsPrivacyWhenStrangersCantAdd.
  ///
  /// In zh, this message translates to:
  /// **'开启后陌生人无法添加我为好友'**
  String get settingsPrivacyWhenStrangersCantAdd;

  /// No description provided for @settingsProfileSocialTagsAuto.
  ///
  /// In zh, this message translates to:
  /// **'个人资料 / 交友标签 / 自动登录'**
  String get settingsProfileSocialTagsAuto;

  /// No description provided for @settingsSettings.
  ///
  /// In zh, this message translates to:
  /// **'设置'**
  String get settingsSettings;

  /// No description provided for @settingsSignOut.
  ///
  /// In zh, this message translates to:
  /// **'退出登录'**
  String get settingsSignOut;

  /// No description provided for @settingsSignOut2.
  ///
  /// In zh, this message translates to:
  /// **'退出'**
  String get settingsSignOut2;

  /// No description provided for @settingsSignOutCurrentAccount.
  ///
  /// In zh, this message translates to:
  /// **'确定要退出当前账号吗？'**
  String get settingsSignOutCurrentAccount;

  /// No description provided for @settingsThemeTextSizeBubbles.
  ///
  /// In zh, this message translates to:
  /// **'{p1} · 主题 / 字号 / 气泡 / 会话排序'**
  String settingsThemeTextSizeBubbles(Object p1);

  /// No description provided for @settingsVCheckUpdatesOpen.
  ///
  /// In zh, this message translates to:
  /// **'v{kAppVersion} · 检查更新 / 开源许可 / 诊断导出'**
  String settingsVCheckUpdatesOpen(Object kAppVersion);

  /// No description provided for @shellFriendsGroupChatsRoom.
  ///
  /// In zh, this message translates to:
  /// **'好友 / 群聊 · 无需进入房间'**
  String get shellFriendsGroupChatsRoom;

  /// No description provided for @shellMoments.
  ///
  /// In zh, this message translates to:
  /// **'动态'**
  String get shellMoments;

  /// No description provided for @shellSelectConversationStartChatting.
  ///
  /// In zh, this message translates to:
  /// **'选择会话开始聊天'**
  String get shellSelectConversationStartChatting;

  /// No description provided for @signFailedSave.
  ///
  /// In zh, this message translates to:
  /// **'保存失败'**
  String get signFailedSave;

  /// No description provided for @signFailedSave2.
  ///
  /// In zh, this message translates to:
  /// **'保存失败: {e}'**
  String signFailedSave2(Object e);

  /// No description provided for @signLike.
  ///
  /// In zh, this message translates to:
  /// **'喜欢…'**
  String get signLike;

  /// No description provided for @signMyCard.
  ///
  /// In zh, this message translates to:
  /// **'我的名片'**
  String get signMyCard;

  /// No description provided for @signNotSet.
  ///
  /// In zh, this message translates to:
  /// **'不设置'**
  String get signNotSet;

  /// No description provided for @signNotSet2.
  ///
  /// In zh, this message translates to:
  /// **'未设置'**
  String get signNotSet2;

  /// No description provided for @signSaved.
  ///
  /// In zh, this message translates to:
  /// **'已保存'**
  String get signSaved;

  /// No description provided for @signWant.
  ///
  /// In zh, this message translates to:
  /// **'想要…'**
  String get signWant;

  /// No description provided for @storageAutoCleanup.
  ///
  /// In zh, this message translates to:
  /// **'自动清理'**
  String get storageAutoCleanup;

  /// No description provided for @storageCleanupFailed.
  ///
  /// In zh, this message translates to:
  /// **'清理失败：{e}'**
  String storageCleanupFailed(Object e);

  /// No description provided for @storageClearConversation.
  ///
  /// In zh, this message translates to:
  /// **'按会话清理'**
  String get storageClearConversation;

  /// No description provided for @storageClearConversationHistory.
  ///
  /// In zh, this message translates to:
  /// **'清理会话记录'**
  String get storageClearConversationHistory;

  /// No description provided for @storageConversationHistoryCleared.
  ///
  /// In zh, this message translates to:
  /// **'已清理该会话记录'**
  String get storageConversationHistoryCleared;

  /// No description provided for @storageDeleteLocalChatHistory.
  ///
  /// In zh, this message translates to:
  /// **'将删除本机「{p1}」的全部聊天记录（服务端记录不受影响）。此操作无法撤销。'**
  String storageDeleteLocalChatHistory(Object p1);

  /// No description provided for @storageDeleteOlderLocalRecords.
  ///
  /// In zh, this message translates to:
  /// **'删除更早的本机记录'**
  String get storageDeleteOlderLocalRecords;

  /// No description provided for @storageDeletedRecords.
  ///
  /// In zh, this message translates to:
  /// **'已删除 {removed} 条记录'**
  String storageDeletedRecords(Object removed);

  /// No description provided for @storageKeepLastDays.
  ///
  /// In zh, this message translates to:
  /// **'只保留最近 {days} 天'**
  String storageKeepLastDays(Object days);

  /// No description provided for @storageMessagesConversations.
  ///
  /// In zh, this message translates to:
  /// **'{_messageCount} 条消息 · {p1} 个会话'**
  String storageMessagesConversations(Object _messageCount, Object p1);

  /// No description provided for @storageMessagesDotSessions.
  ///
  /// In zh, this message translates to:
  /// **'{p1} 条 · {p2}'**
  String storageMessagesDotSessions(Object p1, Object p2);

  /// No description provided for @storageNoLocalChatHistory.
  ///
  /// In zh, this message translates to:
  /// **'本机还没有聊天记录'**
  String get storageNoLocalChatHistory;

  /// No description provided for @storagePermanentlyDeleteLocalChat.
  ///
  /// In zh, this message translates to:
  /// **'将永久删除本机 {days} 天以前的聊天记录（服务端记录不受影响）。此操作无法撤销。'**
  String storagePermanentlyDeleteLocalChat(Object days);

  /// No description provided for @storageProcessing.
  ///
  /// In zh, this message translates to:
  /// **'处理中…'**
  String get storageProcessing;

  /// No description provided for @storageReclaimFailed.
  ///
  /// In zh, this message translates to:
  /// **'回收失败：{e}'**
  String storageReclaimFailed(Object e);

  /// No description provided for @storageReclaimFreeSpace.
  ///
  /// In zh, this message translates to:
  /// **'回收空闲空间'**
  String get storageReclaimFreeSpace;

  /// No description provided for @storageReclaimedFreeSpace.
  ///
  /// In zh, this message translates to:
  /// **'已回收空闲空间'**
  String get storageReclaimedFreeSpace;

  /// No description provided for @storageStorageUsed.
  ///
  /// In zh, this message translates to:
  /// **'本机占用'**
  String get storageStorageUsed;

  /// No description provided for @storageVACUUMRunAfterDeleting.
  ///
  /// In zh, this message translates to:
  /// **'VACUUM（删除记录后执行）'**
  String get storageVACUUMRunAfterDeleting;

  /// No description provided for @themeSettingsAccentColor.
  ///
  /// In zh, this message translates to:
  /// **'强调色'**
  String get themeSettingsAccentColor;

  /// No description provided for @themeSettingsAndroidFollowsWallpaperLinux.
  ///
  /// In zh, this message translates to:
  /// **'Android 跟随壁纸取色、Linux 跟随桌面主题色；开启后上面的强调色不再生效'**
  String get themeSettingsAndroidFollowsWallpaperLinux;

  /// No description provided for @themeSettingsChatTextSize.
  ///
  /// In zh, this message translates to:
  /// **'聊天字号'**
  String get themeSettingsChatTextSize;

  /// No description provided for @themeSettingsExampleMessageScalesText.
  ///
  /// In zh, this message translates to:
  /// **'示例：这条消息会随字号缩放。'**
  String get themeSettingsExampleMessageScalesText;

  /// No description provided for @themeSettingsGotReply.
  ///
  /// In zh, this message translates to:
  /// **'收到！这是我的回复。'**
  String get themeSettingsGotReply;

  /// No description provided for @themeSettingsHiSampleMessageOther.
  ///
  /// In zh, this message translates to:
  /// **'你好，这是对方的示例消息。'**
  String get themeSettingsHiSampleMessageOther;

  /// No description provided for @themeSettingsHighContrast.
  ///
  /// In zh, this message translates to:
  /// **'高对比度'**
  String get themeSettingsHighContrast;

  /// No description provided for @themeSettingsIncreaseForegroundBackgroundContrast.
  ///
  /// In zh, this message translates to:
  /// **'提高前景 / 背景对比（M3 高对比档），弱视或强光下更易读'**
  String get themeSettingsIncreaseForegroundBackgroundContrast;

  /// No description provided for @themeSettingsLivePreview.
  ///
  /// In zh, this message translates to:
  /// **'实时预览'**
  String get themeSettingsLivePreview;

  /// No description provided for @themeSettingsOnlyAppliesDarkMode.
  ///
  /// In zh, this message translates to:
  /// **'仅深色模式生效（当前为浅色模式）'**
  String get themeSettingsOnlyAppliesDarkMode;

  /// No description provided for @themeSettingsPureBlackModeAMOLED.
  ///
  /// In zh, this message translates to:
  /// **'纯黑模式（AMOLED）'**
  String get themeSettingsPureBlackModeAMOLED;

  /// No description provided for @themeSettingsResetDefault.
  ///
  /// In zh, this message translates to:
  /// **'恢复默认'**
  String get themeSettingsResetDefault;

  /// No description provided for @themeSettingsShowRawTextRich.
  ///
  /// In zh, this message translates to:
  /// **'富文本显示原文本'**
  String get themeSettingsShowRawTextRich;

  /// No description provided for @themeSettingsThemeMode.
  ///
  /// In zh, this message translates to:
  /// **'主题模式'**
  String get themeSettingsThemeMode;

  /// No description provided for @themeSettingsUsePureBlackBackgrounds.
  ///
  /// In zh, this message translates to:
  /// **'深色模式下背景改用纯黑，OLED 屏更省电、观感更沉'**
  String get themeSettingsUsePureBlackBackgrounds;

  /// No description provided for @themeSettingsUseSystemColors.
  ///
  /// In zh, this message translates to:
  /// **'跟随系统取色'**
  String get themeSettingsUseSystemColors;

  /// No description provided for @themeSettingsWhenGameTagsLike.
  ///
  /// In zh, this message translates to:
  /// **'开启后，[i][color][b] 等游戏标签原样显示，不再渲染颜色、加粗或表情'**
  String get themeSettingsWhenGameTagsLike;

  /// No description provided for @videoUnablePlay.
  ///
  /// In zh, this message translates to:
  /// **'无法播放：{error}'**
  String videoUnablePlay(Object error);

  /// No description provided for @videoVideo.
  ///
  /// In zh, this message translates to:
  /// **'视频'**
  String get videoVideo;

  /// No description provided for @visitorsNoVisitorsYet.
  ///
  /// In zh, this message translates to:
  /// **'还没有人来访'**
  String get visitorsNoVisitorsYet;

  /// No description provided for @visitorsVisitorRecords.
  ///
  /// In zh, this message translates to:
  /// **'访客记录'**
  String get visitorsVisitorRecords;

  /// No description provided for @voiceNoMicrophonePermissionDevice.
  ///
  /// In zh, this message translates to:
  /// **'拿不到麦克风权限，或设备不可用'**
  String get voiceNoMicrophonePermissionDevice;

  /// No description provided for @voicePlayingVoiceSeconds.
  ///
  /// In zh, this message translates to:
  /// **'播放语音 {total} 秒'**
  String voicePlayingVoiceSeconds(Object total);

  /// No description provided for @voiceStopSend.
  ///
  /// In zh, this message translates to:
  /// **'停止并发送'**
  String get voiceStopSend;

  /// No description provided for @voiceVoicePlaybackIsntSupported.
  ///
  /// In zh, this message translates to:
  /// **'当前平台暂不支持播放语音'**
  String get voiceVoicePlaybackIsntSupported;

  /// No description provided for @bubbleNameStyleNote.
  ///
  /// In zh, this message translates to:
  /// **'气泡名称/样式由游戏内置配置决定，外部客户端无法显示，仅能切换佩戴。'**
  String get bubbleNameStyleNote;

  /// No description provided for @chatRoomNameInGame.
  ///
  /// In zh, this message translates to:
  /// **'房间: {p1}（需在游戏内加入）'**
  String chatRoomNameInGame(Object p1);

  /// No description provided for @dataImportMergeConfirm.
  ///
  /// In zh, this message translates to:
  /// **'将把备份文件中的消息 / 会话 / 好友合并到当前账号，已存在的记录会自动跳过，不会删除或覆盖本地数据。是否继续？'**
  String get dataImportMergeConfirm;

  /// No description provided for @dataImportSummary.
  ///
  /// In zh, this message translates to:
  /// **'导入完成：消息 {p1} 条，会话 {p2} 个，好友 {p3} 个'**
  String dataImportSummary(Object p1, Object p2, Object p3);

  /// No description provided for @settingsAboutCheckFailedWithUrl.
  ///
  /// In zh, this message translates to:
  /// **'检查失败：{p1}\n\n也可以直接到 Releases 页面查看：\n{p2}'**
  String settingsAboutCheckFailedWithUrl(Object p1, Object p2);

  /// No description provided for @settingsAboutClientLine.
  ///
  /// In zh, this message translates to:
  /// **'迷你世界外部聊天客户端 · 客户端 {p1} ({p2}) · {p3}'**
  String settingsAboutClientLine(Object p1, Object p2, Object p3);

  /// No description provided for @settingsAboutLogSizeNote.
  ///
  /// In zh, this message translates to:
  /// **'{p1} KB · 应用私有目录（自动轮转）'**
  String settingsAboutLogSizeNote(Object p1);

  /// No description provided for @storageMessagesAndSessions.
  ///
  /// In zh, this message translates to:
  /// **'{p1} 条消息 · {p2} 个会话'**
  String storageMessagesAndSessions(Object p1, Object p2);

  /// No description provided for @storageFreePagesNote.
  ///
  /// In zh, this message translates to:
  /// **' · {p1} 个空闲页可回收'**
  String storageFreePagesNote(Object p1);

  /// No description provided for @chatFoundCount.
  ///
  /// In zh, this message translates to:
  /// **'找到 {p1} 条'**
  String chatFoundCount(Object p1);

  /// No description provided for @chatRecent100Only.
  ///
  /// In zh, this message translates to:
  /// **'（只列出最近 100 条）'**
  String get chatRecent100Only;

  /// No description provided for @loginRemoveAccountConfirm.
  ///
  /// In zh, this message translates to:
  /// **'移除 {p1}？\n（不影响游戏端账号）'**
  String loginRemoveAccountConfirm(Object p1);

  /// No description provided for @playerInfoTitleWithValue.
  ///
  /// In zh, this message translates to:
  /// **'称号：{p1}'**
  String playerInfoTitleWithValue(Object p1);

  /// No description provided for @chatAmountYuan.
  ///
  /// In zh, this message translates to:
  /// **'金额 ¥{p1}'**
  String chatAmountYuan(Object p1);

  /// No description provided for @dataExportEncrypted.
  ///
  /// In zh, this message translates to:
  /// **'导出（加密）'**
  String get dataExportEncrypted;

  /// No description provided for @dataExportEncryptedHint.
  ///
  /// In zh, this message translates to:
  /// **'设置口令后用 AES-256-GCM 加密备份文件'**
  String get dataExportEncryptedHint;

  /// No description provided for @dataPassphraseEmpty.
  ///
  /// In zh, this message translates to:
  /// **'口令不能为空'**
  String get dataPassphraseEmpty;

  /// No description provided for @dataPassphraseMismatch.
  ///
  /// In zh, this message translates to:
  /// **'两次输入的口令不一致'**
  String get dataPassphraseMismatch;

  /// No description provided for @dataSetBackupPassphrase.
  ///
  /// In zh, this message translates to:
  /// **'设置备份口令'**
  String get dataSetBackupPassphrase;

  /// No description provided for @dataEnterBackupPassphrase.
  ///
  /// In zh, this message translates to:
  /// **'输入备份口令'**
  String get dataEnterBackupPassphrase;

  /// No description provided for @dataPassphrase.
  ///
  /// In zh, this message translates to:
  /// **'口令'**
  String get dataPassphrase;

  /// No description provided for @dataPassphraseHint.
  ///
  /// In zh, this message translates to:
  /// **'至少 6 位，忘记后无法恢复'**
  String get dataPassphraseHint;

  /// No description provided for @dataPassphraseAgain.
  ///
  /// In zh, this message translates to:
  /// **'再次输入'**
  String get dataPassphraseAgain;

  /// No description provided for @dataConfirm.
  ///
  /// In zh, this message translates to:
  /// **'确定'**
  String get dataConfirm;

  /// No description provided for @settingsAboutDownloadUpdate.
  ///
  /// In zh, this message translates to:
  /// **'下载并安装'**
  String get settingsAboutDownloadUpdate;

  /// No description provided for @settingsAboutDownloading.
  ///
  /// In zh, this message translates to:
  /// **'正在下载更新'**
  String get settingsAboutDownloading;

  /// No description provided for @settingsAboutNoPackageForPlatform.
  ///
  /// In zh, this message translates to:
  /// **'该版本没有提供当前平台的安装包'**
  String get settingsAboutNoPackageForPlatform;

  /// No description provided for @settingsAboutUpdateOpened.
  ///
  /// In zh, this message translates to:
  /// **'已打开安装包'**
  String get settingsAboutUpdateOpened;

  /// No description provided for @settingsAboutUpdateSaved.
  ///
  /// In zh, this message translates to:
  /// **'安装包已下载，可在文件管理器中手动安装'**
  String get settingsAboutUpdateSaved;

  /// No description provided for @settingsAboutUpdateDownloadFailed.
  ///
  /// In zh, this message translates to:
  /// **'下载失败，请检查网络后重试'**
  String get settingsAboutUpdateDownloadFailed;

  /// No description provided for @chatDropImageHere.
  ///
  /// In zh, this message translates to:
  /// **'松开以发送图片'**
  String get chatDropImageHere;

  /// No description provided for @chatDropOnlyImages.
  ///
  /// In zh, this message translates to:
  /// **'只支持拖入图片文件'**
  String get chatDropOnlyImages;

  /// No description provided for @chatImageReadFailed.
  ///
  /// In zh, this message translates to:
  /// **'读取图片失败'**
  String get chatImageReadFailed;
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
      <String>['en', 'zh'].contains(locale.languageCode);

  @override
  bool shouldReload(_AppLocalizationsDelegate old) => false;
}

AppLocalizations lookupAppLocalizations(Locale locale) {
  // Lookup logic when only language code is specified.
  switch (locale.languageCode) {
    case 'en':
      return AppLocalizationsEn();
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
