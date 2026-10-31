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

  @override
  String get accountMenuChooseMembersOptional => '选择成员（可选）';

  @override
  String get accountMenuCreate => '创建';

  @override
  String get accountMenuCreateGroup => '创建群';

  @override
  String get accountMenuEnterGroupName => '输入群名称';

  @override
  String get accountMenuEnterGroupName2 => '请输入群名称';

  @override
  String accountMenuFailedCreate(Object e) {
    return '创建失败: $e';
  }

  @override
  String accountMenuFailedCreateRet(Object ret) {
    return '创建失败: ret=$ret';
  }

  @override
  String get accountMenuGroupCreated => '群已创建';

  @override
  String get accountMenuMenu => '菜单';

  @override
  String get accountMenuMyProfile => '我的资料';

  @override
  String get accountMenuRefreshConversations => '刷新会话';

  @override
  String get accountMenuSwitchAccount => '切换账号';

  @override
  String get avatarEditAvatar => '头像';

  @override
  String get avatarEditAvatarInfoMissingTry => '头像信息缺失，请稍后重试';

  @override
  String get avatarEditAvatarUpdated => '头像已更新';

  @override
  String get avatarEditChooseCustomAvatar => '选择自定义头像';

  @override
  String get avatarEditConfirmChange => '确认修改';

  @override
  String get avatarEditCost => '消耗';

  @override
  String get avatarEditCustom => '自定义';

  @override
  String get avatarEditDeveloper => '开发者';

  @override
  String get avatarEditDisplayedFamilyUpdated => '展示家族已更新';

  @override
  String get avatarEditEnterNewName => '输入修改的名字';

  @override
  String avatarEditFailedChangeName(Object e) {
    return '改名失败：$e';
  }

  @override
  String avatarEditFailedEquip(Object e) {
    return '佩戴失败：$e';
  }

  @override
  String get avatarEditFailedEquipTryAgain => '佩戴失败，请稍后重试';

  @override
  String get avatarEditFailedLoadFamilyList => '家族列表加载失败';

  @override
  String get avatarEditFailedLoadTitleList => '称号列表加载失败';

  @override
  String get avatarEditFailedPinTryAgain => '置顶失败，请稍后重试';

  @override
  String avatarEditFailedSet(Object e) {
    return '设置失败：$e';
  }

  @override
  String get avatarEditFailedSetTryAgain => '设置失败，请稍后重试';

  @override
  String avatarEditFailedSwitch(Object e) {
    return '切换失败：$e';
  }

  @override
  String get avatarEditFailedSwitchTryAgain => '切换失败，请稍后重试';

  @override
  String get avatarEditFailedUnpinTryAgain => '取消置顶失败，请稍后重试';

  @override
  String get avatarEditFreeMembers => '会员免费';

  @override
  String get avatarEditInUse => '使用中';

  @override
  String get avatarEditMiniSeason => '迷你季';

  @override
  String get avatarEditMount => '坐骑';

  @override
  String get avatarEditNameChanged => '改名成功';

  @override
  String get avatarEditNickname => '昵称';

  @override
  String get avatarEditNoTitlesCategory => '该分类下暂无称号';

  @override
  String avatarEditOperationFailed(Object e) {
    return '操作失败：$e';
  }

  @override
  String get avatarEditOutfit => '装扮';

  @override
  String get avatarEditPersonality => '个性';

  @override
  String get avatarEditPleaseDontUploadImages => '请勿上传包含恐怖、反动等不良元素的图片哦';

  @override
  String get avatarEditRenameCostReviewDecided => '改名消耗与审核由服务端裁决';

  @override
  String get avatarEditReviewFailed => '审核失败';

  @override
  String get avatarEditSelectedSwitchAutomaticallyAfter => '已使用，审核通过后自动替换';

  @override
  String get avatarEditThisExternalClientHasnt => '外部客户端暂未获取坐骑头像列表';

  @override
  String get avatarEditThisImageViolatesRules => '当前图片违规无法使用';

  @override
  String get avatarEditTitleCategoryConfigFetched => '称号分类配置未获取，暂无法按分类筛选';

  @override
  String get avatarEditTitleEquipped => '称号已佩戴';

  @override
  String get avatarEditUnderReview => '审核中';

  @override
  String avatarEditUploadFailed(Object e) {
    return '上传失败：$e';
  }

  @override
  String get avatarEditUploadFailedTryAgain => '上传失败，请稍后重试';

  @override
  String get avatarEditUploadedPendingReview => '上传成功，等待审核';

  @override
  String get avatarEditValidUntil => '有效期';

  @override
  String get badgesPremiumMember => '大会员';

  @override
  String badgesRapport(Object p1) {
    return '默契度 · $p1';
  }

  @override
  String badgesRapport2(Object next, Object p1, Object tacitnum) {
    return '默契度 · $p1（$tacitnum/$next）';
  }

  @override
  String get blocklistAdd => '加入黑名单';

  @override
  String get blocklistAdded => '已加入黑名单';

  @override
  String get blocklistClear => '清空';

  @override
  String get blocklistClearAll => '清空黑名单';

  @override
  String get blocklistCleared => '已清空';

  @override
  String get blocklistEmpty => '暂无黑名单好友';

  @override
  String get blocklistEnterMiniIdToBlock => '输入要拉黑的迷你号';

  @override
  String blocklistFailedClear(Object e) {
    return '清空失败: $e';
  }

  @override
  String blocklistMiniId(Object p1) {
    return '迷你号 $p1';
  }

  @override
  String get blocklistMiniIdUin => '迷你号 (Uin)';

  @override
  String get blocklistRemove => '移出黑名单';

  @override
  String get blocklistRemoveAllFriends => '确定移出黑名单中的全部好友吗？';

  @override
  String get blocklistRemoved => '已移出黑名单';

  @override
  String bubbleBubble(Object p1) {
    return '气泡 #$p1';
  }

  @override
  String bubbleBubbleEquipped(Object id) {
    return '已佩戴气泡 #$id';
  }

  @override
  String get bubbleBubbleNamesStylesDefined => '气泡名称/样式由游戏内置配置决定，外部客户端无法显示，';

  @override
  String get bubbleBubbleUnequipped => '已取消佩戴气泡';

  @override
  String get bubbleChatBubble => '聊天气泡';

  @override
  String get bubbleExpired => '已过期';

  @override
  String get bubbleNoBubblesAvailableYet => '还没有可用气泡';

  @override
  String get bubbleOnlyEquipSwitchingAvailable => '仅能切换佩戴。';

  @override
  String get bubblePermanent => '永久';

  @override
  String get bubbleUnequip => '取消佩戴';

  @override
  String bubbleValidUntil(Object dd, Object mo) {
    return '有效期至 $mo-$dd';
  }

  @override
  String get chatAnimatedEmoji => '动态表情';

  @override
  String chatAuthor(Object p1) {
    return '作者: $p1';
  }

  @override
  String get chatBack => '返回';

  @override
  String get chatBackLatest => '回到最新';

  @override
  String get chatChooseAudioFile => '选择音频文件';

  @override
  String get chatChooseImageSend => '选择要发送的图片';

  @override
  String get chatChooseVoiceFileSend => '选择要发送的语音文件';

  @override
  String chatCopied(Object p1) {
    return '已复制 $p1 条';
  }

  @override
  String get chatCopySelected => '复制选中';

  @override
  String get chatCouldntFetchGroupMember => '还没拉到群成员名单，稍后再试';

  @override
  String get chatEmoji => '表情';

  @override
  String get chatEnterKeywordsSearchChat => '输入关键词搜索本会话消息';

  @override
  String get chatExitSearch => '退出搜索';

  @override
  String get chatExportSelected => '导出选中';

  @override
  String get chatExportSelectedMessages => '导出选中消息';

  @override
  String chatExported(Object path) {
    return '已导出到 $path';
  }

  @override
  String chatFailedExport(Object e) {
    return '导出失败：$e';
  }

  @override
  String chatFailedForward(Object e) {
    return '转发失败: $e';
  }

  @override
  String chatFailedLoadMoments(Object e) {
    return '动态加载失败: $e';
  }

  @override
  String chatFailedReadImage(Object e) {
    return '读取图片失败：$e';
  }

  @override
  String chatFailedSend(Object e) {
    return '发送失败: $e';
  }

  @override
  String chatForwardChatHistory(Object text) {
    return '转发聊天记录：\\n$text';
  }

  @override
  String get chatGift => '礼物';

  @override
  String get chatGiftsSentFriendChats => '礼物只能送给好友会话';

  @override
  String get chatGreetingHi => '嗨~';

  @override
  String get chatGroup => '群';

  @override
  String get chatGroupChat => '群聊';

  @override
  String get chatGroupDetails => '群详情';

  @override
  String get chatGroupMembers => '@群成员';

  @override
  String get chatImage => '图片';

  @override
  String get chatImageUploadFailedTry => '图片上传失败，请稍后重试';

  @override
  String get chatInteractiveEmojiCurrentlyWork => '互动表情暂仅支持好友会话';

  @override
  String get chatInvitesYouPlayFound => '邀请你一起玩 · 发现一个好玩的地图，快来一起吧';

  @override
  String get chatInvitesYouPlayJoin => '邀请你一起玩 · 需在游戏内加入房间';

  @override
  String get chatJoinGame => '（需在游戏内加入）';

  @override
  String get chatJoinRoomGame => '房间需在游戏内加入';

  @override
  String get chatJumpDate => '跳到某一天';

  @override
  String get chatLetsPlayTogether => '一起来玩呀';

  @override
  String get chatLoadEarlier => '加载更早';

  @override
  String get chatLoading => '加载中…';

  @override
  String get chatMap => '地图';

  @override
  String get chatMapShare => '地图分享';

  @override
  String get chatMe => '我';

  @override
  String get chatMessagesISent => '我发出的消息';

  @override
  String chatMessagesNotSent(Object count) {
    return '$count 条消息未发送';
  }

  @override
  String chatMiniID(Object p1) {
    return '迷你号 $p1';
  }

  @override
  String get chatNewMessagesBelow => '以下为新消息';

  @override
  String get chatNoEarlierChatHistory => '没有更早的聊天记录了';

  @override
  String get chatNoImageFilePath => '剪贴板里没有图片文件路径';

  @override
  String get chatNoMatchingMembers => '没有匹配的成员';

  @override
  String get chatNoMessagesAroundDate => '这一天附近没有消息';

  @override
  String get chatNoMessagesYetSay => '暂无消息，打个招呼吧 👋';

  @override
  String get chatNoTextContent => '（无文本内容）';

  @override
  String get chatOlderChatHistoryStored => '本地还存有更早的聊天记录';

  @override
  String get chatOpenMapGame => '地图需在游戏内打开';

  @override
  String get chatPasteImage => '粘贴图片';

  @override
  String chatRapport(Object p1) {
    return '默契度 +$p1';
  }

  @override
  String get chatRapportGift => '默契礼物';

  @override
  String get chatRecord => '录音';

  @override
  String get chatRecordMicrophoneNow => '现在用麦克风录一段';

  @override
  String get chatRedPacketsMustClaimed => '红包需在游戏内领取';

  @override
  String chatResent(Object sent) {
    return '已重发 $sent 条';
  }

  @override
  String get chatRoom => '房间';

  @override
  String get chatRoomInvite => '房间邀请';

  @override
  String chatRoomWithName(Object p1) {
    return '房间: $p1';
  }

  @override
  String get chatSayHello => '打个招呼';

  @override
  String get chatSearchChat => '搜索本会话消息';

  @override
  String get chatSearchGroupMembers => '搜索群成员';

  @override
  String get chatSearchMessages => '搜索消息';

  @override
  String chatSelected(Object p1) {
    return '已选 $p1 条';
  }

  @override
  String get chatSendFirstMessageStart => '发送第一条消息，开启你们的冒险';

  @override
  String get chatStillSentTryAgain => '仍未发送成功，稍后再试';

  @override
  String get chatTheirMessages => '对方的消息';

  @override
  String get chatThem => '对方';

  @override
  String get chatThisMessageTextForward => '这条消息没有可转发的文本';

  @override
  String get chatThisMessageTextResend => '这条消息没有可重发的文本';

  @override
  String get chatTypeMessage => '输入消息…';

  @override
  String chatViewingHistory(Object p1, Object p2, Object p3) {
    return '正在查看 $p1-$p2-$p3 的历史';
  }

  @override
  String chatVoice(Object p1) {
    return '[语音] $p1';
  }

  @override
  String get chatVoiceShort => '[语音]';

  @override
  String get chatVoiceUploadFailedTry => '语音上传失败，请稍后重试';

  @override
  String get chatWhatYouUp => '在干嘛';

  @override
  String get commonBestPartners => '最佳拍档';

  @override
  String get commonConversations => '会话';

  @override
  String commonFailedLoad(Object _error) {
    return '加载失败：$_error';
  }

  @override
  String commonFailedLoad2(Object e) {
    return '加载失败: $e';
  }

  @override
  String get commonFamily => '家族';

  @override
  String get commonFollowed => '已关注';

  @override
  String get commonFollowing => '关注';

  @override
  String get commonFriend => '好友';

  @override
  String commonMiniID(Object p1) {
    return '迷你号 $p1';
  }

  @override
  String commonMiniID2(Object uin) {
    return '迷你号 $uin';
  }

  @override
  String get commonNotSignedIn => '未登录';

  @override
  String commonOperationFailed(Object e) {
    return '操作失败: $e';
  }

  @override
  String get commonPin => '置顶';

  @override
  String get commonPinned => '已置顶';

  @override
  String get commonRefresh => '刷新';

  @override
  String get commonRetry => '重试';

  @override
  String get commonUnpin => '取消置顶';

  @override
  String get commonUnpinned => '已取消置顶';

  @override
  String get dataCanceled => '已取消';

  @override
  String get dataChatHistory => '聊天记录';

  @override
  String dataChatsFriends(Object p1, Object p2) {
    return '会话 $p1 个，好友 $p2 个';
  }

  @override
  String get dataChooseChatHistoryBackup => '选择聊天记录备份文件';

  @override
  String get dataCounting => '统计中…';

  @override
  String get dataExistingRecordsSkippedAutomatically =>
      '已存在的记录会自动跳过，不会删除或覆盖本地数据。是否继续？';

  @override
  String get dataExportChatHistory => '导出聊天记录';

  @override
  String get dataExportCurrentAccountsMessages =>
      '把当前账号的消息 / 会话 / 好友导出为 JSON 文件';

  @override
  String get dataImport => '导入';

  @override
  String get dataImportChatHistory => '导入聊天记录';

  @override
  String dataImportCompleteMessages(Object p1) {
    return '导入完成：消息 $p1 条，';
  }

  @override
  String dataImportFailed(Object e) {
    return '导入失败：$e';
  }

  @override
  String get dataLocalData => '本地数据';

  @override
  String get dataMergeImportJSONBackup => '从 JSON 备份文件合并导入（自动跳过已存在的记录）';

  @override
  String dataMessagesChats(Object _messageCount, Object _sessionCount) {
    return '共 $_messageCount 条消息 · $_sessionCount 个会话';
  }

  @override
  String get dataMessagesChatsFriendsBackup => '将把备份文件中的消息 / 会话 / 好友合并到当前账号，';

  @override
  String get dataSignBeforeExporting => '请先登录后再导出';

  @override
  String dynamicsAuthorMoments(Object p1) {
    return '$p1 的动态';
  }

  @override
  String dynamicsCardAuthor(Object p1) {
    return '作者 $p1';
  }

  @override
  String get dynamicsCardEnded => '已结束';

  @override
  String get dynamicsCardFailedForward => '转发失败';

  @override
  String get dynamicsCardForwardedFriend => '已转发给好友';

  @override
  String get dynamicsCardGiveaway => '抽奖';

  @override
  String get dynamicsCardGiveawayLoading => '抽奖（加载中）';

  @override
  String get dynamicsCardNoFriendsShare => '还没有好友可以分享';

  @override
  String get dynamicsCardOngoing => '进行中';

  @override
  String dynamicsCardOpenWorkMap(Object p1) {
    return '打开作品/地图：$p1';
  }

  @override
  String get dynamicsCardOperationFailedTryAgain => '操作失败，请稍后重试';

  @override
  String dynamicsCardParticipants(Object p1) {
    return '参与 $p1 人';
  }

  @override
  String dynamicsCardPrizeX(Object p1) {
    return '奖品 ×$p1';
  }

  @override
  String get dynamicsCardViewFullText => '查看全文';

  @override
  String get dynamicsCardVoteLoading => '投票（加载中）';

  @override
  String dynamicsCardWinners(Object p1) {
    return '开奖 $p1 人';
  }

  @override
  String dynamicsCategory(Object p1) {
    return '分类$p1';
  }

  @override
  String get dynamicsDetailChangeVisibility => '改可见范围';

  @override
  String dynamicsDetailChanged(Object p1) {
    return '已改为「$p1」';
  }

  @override
  String get dynamicsDetailCollapseReplies => '收起回复';

  @override
  String get dynamicsDetailCommentActions => '评论操作';

  @override
  String get dynamicsDetailCommentPosted => '评论已发布';

  @override
  String dynamicsDetailComments(Object p1) {
    return '共$p1条评论';
  }

  @override
  String dynamicsDetailDAgo(Object p1) {
    return '$p1天前';
  }

  @override
  String get dynamicsDetailDefault => '默认';

  @override
  String get dynamicsDetailDeleteComment => '删除评论';

  @override
  String get dynamicsDetailDeleteComment2 => '确定删除这条评论吗？';

  @override
  String get dynamicsDetailDeleteFailed => '删除失败';

  @override
  String dynamicsDetailDeleteFailed2(Object e) {
    return '删除失败: $e';
  }

  @override
  String get dynamicsDetailDeleteMoment => '删除动态';

  @override
  String get dynamicsDetailDeleteReply => '删除回复';

  @override
  String get dynamicsDetailDeleteReply2 => '确定删除这条回复吗？';

  @override
  String get dynamicsDetailDeleted => '已删除';

  @override
  String get dynamicsDetailFailedLoadVoteInfo => '投票信息加载失败';

  @override
  String get dynamicsDetailFailedPublish => '发布失败';

  @override
  String dynamicsDetailFailedPublish2(Object e) {
    return '发布失败: $e';
  }

  @override
  String dynamicsDetailFailedShare(Object e) {
    return '分享失败: $e';
  }

  @override
  String get dynamicsDetailGiveawayDetailsOngoing => '抽奖详情（进行中）';

  @override
  String dynamicsDetailHrAgo(Object p1) {
    return '$p1小时前';
  }

  @override
  String get dynamicsDetailJustNow => '刚刚';

  @override
  String get dynamicsDetailLatest => '最新';

  @override
  String get dynamicsDetailLike => '点赞';

  @override
  String get dynamicsDetailLoadMoreComments => '加载更多评论';

  @override
  String dynamicsDetailMinAgo(Object p1) {
    return '$p1分钟前';
  }

  @override
  String dynamicsDetailMoAgo(Object p1) {
    return '$p1个月前';
  }

  @override
  String get dynamicsDetailMomentDeleted => '动态已删除';

  @override
  String get dynamicsDetailMomentDetails => '动态详情';

  @override
  String get dynamicsDetailMomentManagement => '动态管理';

  @override
  String get dynamicsDetailMultipleChoiceSubmitAfter => '可多选，选好后提交';

  @override
  String get dynamicsDetailNoCommentsYet => '暂无评论';

  @override
  String get dynamicsDetailNoFriendsShare => '暂无好友可分享';

  @override
  String get dynamicsDetailNoRepliesYet => '暂无回复';

  @override
  String get dynamicsDetailOperationFailed => '操作失败';

  @override
  String dynamicsDetailOption(Object p1) {
    return '选项 $p1';
  }

  @override
  String get dynamicsDetailPublish => '发布';

  @override
  String dynamicsDetailReplies(Object p1) {
    return '共$p1条回复';
  }

  @override
  String get dynamicsDetailReply => '回复';

  @override
  String dynamicsDetailReply2(Object name) {
    return '回复 $name';
  }

  @override
  String dynamicsDetailReply3(Object name) {
    return '回复 @$name';
  }

  @override
  String get dynamicsDetailReplyActions => '回复操作';

  @override
  String get dynamicsDetailReplyPosted => '回复已发布';

  @override
  String get dynamicsDetailShareChat => '分享到聊天';

  @override
  String get dynamicsDetailShareMoment => '分享动态到…';

  @override
  String dynamicsDetailShared(Object picked) {
    return '已分享给 $picked';
  }

  @override
  String get dynamicsDetailSignVote => '登录后可参与投票';

  @override
  String get dynamicsDetailSingleChoiceTapSubmit => '单选，点选后提交';

  @override
  String get dynamicsDetailSubmitting => '提交中…';

  @override
  String get dynamicsDetailTapWriteComment => '点击写评论';

  @override
  String get dynamicsDetailThisCannotUndoneDelete => '删除后不可恢复，确定删除这条动态吗？';

  @override
  String get dynamicsDetailUnlike => '取消点赞';

  @override
  String get dynamicsDetailVote => '投票';

  @override
  String get dynamicsDetailVoteFailed => '投票失败';

  @override
  String dynamicsDetailVoteFailed2(Object e) {
    return '投票失败: $e';
  }

  @override
  String dynamicsDetailVotes(Object p1) {
    return '$p1票';
  }

  @override
  String get dynamicsDetailWriteComment => '写评论';

  @override
  String dynamicsDetailYrAgo(Object p1) {
    return '$p1年前';
  }

  @override
  String get dynamicsLocal => '同城';

  @override
  String get dynamicsMine => '我的';

  @override
  String get dynamicsMomentNotifications => '动态通知';

  @override
  String get dynamicsNoMomentsYetPull => '暂无动态，下拉刷新';

  @override
  String get dynamicsOfficial => '官方';

  @override
  String get dynamicsPopular => '热门';

  @override
  String get dynamicsPostMoment => '发布动态';

  @override
  String get dynamicsTopicNoMomentsTopicYet => '该话题暂无动态，下拉刷新';

  @override
  String get dynamicsTopicNoTopicsYetPull => '暂无话题，下拉刷新';

  @override
  String dynamicsTopicTopic(Object p1) {
    return '话题 $p1';
  }

  @override
  String get dynamicsTopicTopics => '话题';

  @override
  String get emojiAddEmojiPack => '添加表情包';

  @override
  String get emojiBasics => '基础';

  @override
  String get emojiEmojiPackManagementIsnt => '表情包管理暂未开放';

  @override
  String get emojiEmojiPackStoreIsnt => '表情包商城暂未开放';

  @override
  String get emojiEmojiSettings => '表情设置';

  @override
  String get emojiInteractive => '互动';

  @override
  String get emojiMember => '会员';

  @override
  String get emojiNoEmojiPacksAvailable => '暂无可用的表情包';

  @override
  String get familyAnnouncement => '公告';

  @override
  String get familyApprove => '通过';

  @override
  String get familyApproved => '已通过';

  @override
  String familyFailedLeave(Object e) {
    return '退出失败: $e';
  }

  @override
  String get familyFamilyJoinRequests => '入族申请';

  @override
  String get familyFamilyMessages => '家族消息';

  @override
  String familyJoinedFamilies(Object p1) {
    return '已加入 $p1 个家族';
  }

  @override
  String get familyLeader => '族长';

  @override
  String familyLeave(Object p1) {
    return '确定退出「$p1」吗？';
  }

  @override
  String get familyLeaveFamily => '退出家族';

  @override
  String get familyMembers => '成员数';

  @override
  String get familyMembers2 => '成员';

  @override
  String get familyMessageFamily => '发家族消息…';

  @override
  String get familyNoFamilyJoinRequests => '暂无入族申请';

  @override
  String get familyNoFamilyMessages => '暂无家族消息';

  @override
  String familyRefreshHint(Object _error) {
    return '$_error\\n\\n点击右上角刷新';
  }

  @override
  String get familyRejected => '已拒绝';

  @override
  String get familyTransferLeadership => '转让族长';

  @override
  String get familyYouHaventJoinedAny => '你尚未加入任何家族';

  @override
  String get favoritesContentGone => '（内容已不在本机）';

  @override
  String get friendFilterFilter => '筛选';

  @override
  String get friendFilterFriendsInvite => '邀请一起玩的好友';

  @override
  String get friendFilterGeneral => '通用';

  @override
  String get friendFilterNewTag => '新建标签';

  @override
  String get friendFilterOnlineFriends => '在线好友';

  @override
  String get friendFilterReset => '重置';

  @override
  String get friendFilterTagNameMax5 => '标签名（最多 5 个字）';

  @override
  String get friendFilterTags => '标签';

  @override
  String get friendFilterYouHaventCreatedAny => '你还未创建标签';

  @override
  String get friendRequestAccept => '同意';

  @override
  String get friendRequestAddFriend => '添加好友';

  @override
  String get friendRequestEnterTheirMiniID => '输入对方的迷你号';

  @override
  String get friendRequestEnterValidMiniID => '请输入有效的迷你号';

  @override
  String friendRequestFailedApprove(Object e) {
    return '通过失败: $e';
  }

  @override
  String friendRequestFailedReject(Object e) {
    return '拒绝失败: $e';
  }

  @override
  String friendRequestFailedSendRequest(Object e) {
    return '发送申请失败: $e';
  }

  @override
  String get friendRequestFriendAdded => '已添加好友';

  @override
  String friendRequestFriendRequestSent(Object uin) {
    return '已向 $uin 发送好友申请';
  }

  @override
  String get friendRequestFriendRequests => '好友申请';

  @override
  String friendRequestGroup(Object p1) {
    return '群 $p1';
  }

  @override
  String get friendRequestGroupInvites => '群邀请';

  @override
  String friendRequestInvitedMembers(Object p1, Object p2) {
    return '邀请人 $p1 · 成员 $p2';
  }

  @override
  String get friendRequestNoGroupInvites => '暂无群邀请';

  @override
  String get friendRequestNoPendingFriendRequests => '暂无待处理的好友申请';

  @override
  String friendRequestOperationFailedRet(Object ret) {
    return '操作失败: ret=$ret';
  }

  @override
  String get friendRequestReject => '拒绝';

  @override
  String get friendRequestReject2 => '全部拒绝';

  @override
  String get friendRequestRejectedFriendRequests => '已拒绝全部好友申请';

  @override
  String get friendRequestRequestList => '申请列表';

  @override
  String get friendRequestSendRequest => '发送申请';

  @override
  String get friendTagAfterDeletionTagRemoved => '删除后该标签会从所有好友身上移除。';

  @override
  String get friendTagClearTagsTheseFriends => '清除这些好友的标签';

  @override
  String friendTagCreated(Object label) {
    return '已创建「$label」';
  }

  @override
  String get friendTagDeleteTag => '删除标签';

  @override
  String friendTagDeleteTag2(Object p1) {
    return '删除标签「$p1」';
  }

  @override
  String get friendTagDone => '完成';

  @override
  String friendTagFriends(Object p1) {
    return '$p1 位好友';
  }

  @override
  String friendTagServerDidntAcceptResult(Object code) {
    return '服务端未受理（result=$code）';
  }

  @override
  String get friendTagTagDeleted => '已删除标签';

  @override
  String friendTagTagFriends(Object p1) {
    return '给 $p1 位好友打标签';
  }

  @override
  String get friendTagTagsApplied => '已打标签';

  @override
  String get friendTagTagsRemoved => '已取消标签';

  @override
  String get friendsAddMiniID => '按迷你号添加';

  @override
  String get friendsAddTags => '打标签';

  @override
  String get friendsBlocklist => '黑名单';

  @override
  String get friendsBulkManagement => '批量管理';

  @override
  String get friendsClearTags => '清除标签';

  @override
  String get friendsCloseSearch => '关闭搜索';

  @override
  String get friendsDefaultFriendOrder => '好友默认排序';

  @override
  String get friendsExitBulkManagement => '退出批量管理';

  @override
  String get friendsFollowingFollowers => '关注与粉丝';

  @override
  String get friendsGroupLeaveHistory => '退群记录';

  @override
  String get friendsGroups => '群组';

  @override
  String get friendsHighestRapportFirst => '默契度从高到低';

  @override
  String friendsMiniID(Object gameText, Object p1) {
    return '$gameText · 迷你号 $p1';
  }

  @override
  String get friendsMore => '更多';

  @override
  String get friendsMostRecentLoginFirst => '登录从近到远';

  @override
  String get friendsMyFriends => '我的好友';

  @override
  String get friendsMyQRCode => '我的二维码';

  @override
  String get friendsNoFriendsMatchFilters => '没有符合条件的好友';

  @override
  String get friendsNoFriendsYetPull => '暂无好友\\n下拉刷新或点击右上角添加';

  @override
  String get friendsNoGroupChats => '暂无群聊';

  @override
  String get friendsOffline => '离线';

  @override
  String get friendsOldestLoginFirst => '登录从远到近';

  @override
  String get friendsOnline => '在线';

  @override
  String friendsOnlineFriends(Object online, Object total) {
    return '在线好友 $online/$total';
  }

  @override
  String get friendsOnlineNotifications => '上线通知';

  @override
  String friendsOnlineNotificationsSetPeople(Object p1) {
    return '已设置上线通知（$p1 人）';
  }

  @override
  String get friendsPeopleNearby => '附近的人';

  @override
  String get friendsSearch => '搜索';

  @override
  String friendsSearch2(Object _search) {
    return '搜索：$_search';
  }

  @override
  String get friendsSearchFriendNicknameMini => '搜索好友昵称 / 迷你号…';

  @override
  String friendsSelected(Object count) {
    return '已选 $count 人';
  }

  @override
  String friendsSort(Object p1) {
    return '排序方式：$p1';
  }

  @override
  String get friendsSort2 => '排序方式';

  @override
  String get friendsTagsCleared => '已清除标签';

  @override
  String get friendsTapOpenGroupChat => '点击进入群聊';

  @override
  String get friendsViewProfile => '查看主页';

  @override
  String giftBuyIntoInventoryFirst(Object p1, Object p2) {
    return '先买进仓库再送，扣 $p1 $p2';
  }

  @override
  String get giftBuySend => '扣费购买赠送';

  @override
  String giftBuyThenSend(Object _num) {
    return '购买 $_num 份后赠送';
  }

  @override
  String get giftCouldntLoadGiftConfig => '取不到礼物配置（或当前无可赠送礼物）';

  @override
  String giftDailyRapportCap(Object p1) {
    return '每日默契度上限 $p1';
  }

  @override
  String giftDeductsInventoryFreeInventory(Object p1) {
    return '扣仓库库存，免费；仓库 ×$p1';
  }

  @override
  String giftFailedSendGift(Object e) {
    return '赠送失败: $e';
  }

  @override
  String get giftFree => '免费';

  @override
  String get giftGiftSent => '赠送成功';

  @override
  String giftInventoryX(Object owned) {
    return '仓库 ×$owned';
  }

  @override
  String get giftQuantity => '数量';

  @override
  String giftRapport(Object p1) {
    return '默契度 +$p1';
  }

  @override
  String giftRapport2(Object p1) {
    return '默契度 +$p1';
  }

  @override
  String get giftSendAfterWatchingAd => '看完广告后送出';

  @override
  String giftSendFree(Object _num) {
    return '免费赠送 $_num 份';
  }

  @override
  String get giftSendFree2 => '免费赠送';

  @override
  String giftSendGift(Object _displayName) {
    return '赠送礼物给 $_displayName';
  }

  @override
  String get giftSendGiftInventory => '从礼物仓库赠送';

  @override
  String giftSendInventoryFree(Object _num) {
    return '从仓库赠送 $_num 份（免费）';
  }

  @override
  String giftSendInventoryInventoryFail(Object _num, Object p1) {
    return '从仓库赠送 $_num 份（仓库只有 $p1 份，会失败）';
  }

  @override
  String get giftUseTodaysFreeSend => '用当日的免费赠送次数';

  @override
  String get giftWatchAd => '看广告';

  @override
  String giftWatchAdSend(Object _num) {
    return '看广告赠送 $_num 份';
  }

  @override
  String get giftWatchAdSend2 => '看广告赠送';

  @override
  String get groupDetailAllRejected => '已全部拒绝';

  @override
  String get groupDetailBlockMembersMessages => '屏蔽该成员消息';

  @override
  String get groupDetailChooseFriendsInvite => '选择要邀请的好友';

  @override
  String get groupDetailChooseNewGroupOwner => '选择新群主';

  @override
  String get groupDetailClear => '清除';

  @override
  String get groupDetailDisbandGroup => '解散群';

  @override
  String get groupDetailEditGroupName => '修改群名';

  @override
  String groupDetailFailedClear(Object e) {
    return '清除失败: $e';
  }

  @override
  String groupDetailFailedDisband(Object e) {
    return '解散失败: $e';
  }

  @override
  String groupDetailFailedInvite(Object e) {
    return '邀请失败: $e';
  }

  @override
  String groupDetailFailedPin(Object e) {
    return '置顶失败: $e';
  }

  @override
  String groupDetailFailedTransfer(Object e) {
    return '转让失败: $e';
  }

  @override
  String groupDetailFailedUpdate(Object e) {
    return '更新失败: $e';
  }

  @override
  String groupDetailGroup(Object gid) {
    return '群 $gid';
  }

  @override
  String groupDetailGroup2(Object p1) {
    return '群 $p1';
  }

  @override
  String get groupDetailGroupDataCannotRecovered => '解散后群内数据将不可恢复，确定解散？';

  @override
  String get groupDetailGroupDisbanded => '群已解散';

  @override
  String get groupDetailGroupID => '群号';

  @override
  String get groupDetailGroupName => '群名称';

  @override
  String get groupDetailGroupNameUpdated => '已更新群名';

  @override
  String get groupDetailGroupNotificationsMuted => '已开启群免打扰';

  @override
  String get groupDetailGroupNotificationsUnmuted => '已关闭群免打扰';

  @override
  String get groupDetailGroupOwner => '群主';

  @override
  String get groupDetailGroupPinned => '已置顶群';

  @override
  String get groupDetailInvitationSent => '已发送邀请';

  @override
  String get groupDetailInvite => '邀请';

  @override
  String get groupDetailInviteFriendsGroup => '邀请好友入群';

  @override
  String get groupDetailLeaveGroup => '退出群';

  @override
  String get groupDetailLeaveGroup2 => '确定退出该群吗？';

  @override
  String get groupDetailLeftGroup => '已退出群';

  @override
  String get groupDetailMemberRemoved => '已移出该成员';

  @override
  String get groupDetailMembersMessagesBlocked => '已屏蔽该成员消息';

  @override
  String get groupDetailMuteGroupNotifications => '群消息免打扰';

  @override
  String get groupDetailMuteMember => '禁言该成员';

  @override
  String get groupDetailMuted => '已禁言';

  @override
  String groupDetailNameWithMe(Object name) {
    return '$name（我）';
  }

  @override
  String get groupDetailNoFriendsInvite => '暂无好友可邀请';

  @override
  String get groupDetailNoGroupLeaveHistory => '没有退群记录';

  @override
  String get groupDetailNoMemberInfoYet => '暂无成员信息（可能未拉取到）';

  @override
  String get groupDetailNoMembersTransfer => '没有可转让的成员';

  @override
  String get groupDetailPinGroup => '群置顶';

  @override
  String get groupDetailRecordsCleared => '已清除记录';

  @override
  String get groupDetailReject => '一键拒绝';

  @override
  String get groupDetailRejectJoinRequests => '一键拒绝入群申请';

  @override
  String get groupDetailRejectPendingJoinRequests => '拒绝本群全部待处理的入群申请？';

  @override
  String get groupDetailRemoveGroup => '移出该群';

  @override
  String groupDetailRemoveGroup2(Object p1) {
    return '确定将 $p1 移出本群？';
  }

  @override
  String get groupDetailRemoveGroupMember => '移出群成员';

  @override
  String get groupDetailReportMember => '举报该成员';

  @override
  String get groupDetailReportSubmitted => '已提交举报';

  @override
  String get groupDetailSave => '保存';

  @override
  String groupDetailSelected(Object p1) {
    return '已选 $p1 人';
  }

  @override
  String get groupDetailTransferGroupOwnership => '转让群主';

  @override
  String groupDetailTransferGroupOwnership2(Object p1) {
    return '确认将群主转给 $p1？';
  }

  @override
  String get groupDetailTransferred => '已转让';

  @override
  String get groupDetailUnblockMember => '解除屏蔽该成员';

  @override
  String get groupDetailUnblocked => '已解除屏蔽';

  @override
  String get groupDetailUnmuteGroup => '取消群免打扰';

  @override
  String get groupDetailUnmuteMember => '解除该成员禁言';

  @override
  String get groupDetailUnmuted => '已解除禁言';

  @override
  String get groupDetailUnpinGroup => '取消群置顶';

  @override
  String get groupDetailYouLeftGroup => '你已退出该群';

  @override
  String get groupDetailYouWereRemovedGroup => '你被移出该群';

  @override
  String get homeLayoutUnknownModule => '未知模块';

  @override
  String get lockEnterAppLockPassword => '请输入应用锁密码';

  @override
  String get lockWrongPassword => '密码错误';

  @override
  String get loginAddAccount => '添加账号';

  @override
  String get loginBackAccountList => '返回账号列表';

  @override
  String get loginChooseAccount => '选择账号';

  @override
  String get loginEnterPassword => '请输入密码';

  @override
  String loginMiniID(Object p1) {
    return '迷你号 $p1';
  }

  @override
  String get loginMiniWorldExternalChat => '迷你世界外部聊天 · 选择账号登录';

  @override
  String get loginNoSavedAccountsYet => '还没有保存的账号';

  @override
  String get loginPassword => '密码';

  @override
  String get loginRemove => '移除';

  @override
  String get loginRemoveAccount => '移除账号';

  @override
  String get loginSign => '登录';

  @override
  String get loginSignAdd => '登录并添加';

  @override
  String get loginSignAutomaticallyNextTime => '下次自动登录';

  @override
  String get loginSigning => '登录中…';

  @override
  String get loginUinMiniID => 'Uin / 迷你号';

  @override
  String get mailAll => '全部';

  @override
  String get mailAttachments => '附件';

  @override
  String get mailClaimAttachments => '领取附件';

  @override
  String get mailClaimed => '已领取';

  @override
  String mailDAgo(Object p1) {
    return '$p1天前';
  }

  @override
  String get mailDeleteRead => '删除已读';

  @override
  String get mailDetails => '详情';

  @override
  String get mailFailedFollow => '关注失败';

  @override
  String get mailFailedMarkRead => '标记已读失败';

  @override
  String get mailFilterType => '筛选类型';

  @override
  String mailFrom(Object p1) {
    return '来自$p1';
  }

  @override
  String get mailFromMiniWorldOfficial => '来自迷你官方';

  @override
  String get mailGo => '前往';

  @override
  String mailHrAgo(Object p1) {
    return '$p1小时前';
  }

  @override
  String mailItem(Object p1) {
    return '物品 $p1';
  }

  @override
  String get mailLink => '链接';

  @override
  String get mailMarkRead => '一键已读';

  @override
  String get mailMessageCenter => '消息中心';

  @override
  String get mailMessageDetails => '消息详情';

  @override
  String mailMinAgo(Object p1) {
    return '$p1分钟前';
  }

  @override
  String get mailNoContent => '（无内容）';

  @override
  String get mailNoMessages => '暂无消息';

  @override
  String get mailThisLinkTypeIsnt => '该跳转类型暂不支持';

  @override
  String get mailThisMomentDoesntExist => '动态不存在或已删除';

  @override
  String get mailUnclaimed => '待领取';

  @override
  String get mailUntitled => '（无标题）';

  @override
  String get nearbyDistanceUnknown => '距离未知';

  @override
  String get nearbyEnterValidLatitudeLongitude => '请先填写有效的经纬度';

  @override
  String nearbyFailedSave(Object e) {
    return '设置失败: $e';
  }

  @override
  String nearbyKilometers(Object p1) {
    return '$p1 公里';
  }

  @override
  String nearbyKilometersRounded(Object p1) {
    return '$p1 公里';
  }

  @override
  String get nearbyLatitudeExample => '如 39.9042';

  @override
  String get nearbyLatitudeLabel => '纬度 latitude';

  @override
  String get nearbyLetPeopleNearbyAdd => '允许附近的人加我';

  @override
  String get nearbyLongitudeExample => '如 116.4074';

  @override
  String get nearbyLongitudeLabel => '经度 longitude';

  @override
  String nearbyMeters(Object p1) {
    return '$p1 米';
  }

  @override
  String nearbyMiniID(Object p1, Object p2) {
    return '迷你号 $p1 · $p2';
  }

  @override
  String get nearbyNoOneFoundNearby => '附近没有找到人';

  @override
  String nearbyPeopleFirstPage(Object p1) {
    return '共 $p1 人（仅显示第 1 页）';
  }

  @override
  String nearbyQueryFailed(Object _error) {
    return '查询失败：$_error';
  }

  @override
  String get nearbyReading => '读取中…';

  @override
  String get nearbyReportLocationFindPeople => '上报位置并查找附近的人';

  @override
  String get nearbyThisExternalClientSystem => '外部客户端未接入系统定位，请手动填写经纬度后再查询。';

  @override
  String get nearbyWhenEnabledPeopleNearby => '开启后附近的人可搜索到我并加好友';

  @override
  String partnerAlias(Object p1) {
    return '别称 #$p1';
  }

  @override
  String partnerBestPartnerSlotsLeft(Object remaining) {
    return '最佳拍档剩余空位 x $remaining';
  }

  @override
  String partnerDaysRelation(Object p1) {
    return '结成关系天数：$p1';
  }

  @override
  String get partnerNoBestPartnersYet => '暂无最佳拍档';

  @override
  String get partnerPartnerSlots => '可建立拍档数';

  @override
  String partnerRapport(Object p1) {
    return '默契度 $p1';
  }

  @override
  String partnerRapport2(Object next, Object p1) {
    return '默契度 $p1/$next';
  }

  @override
  String partnerRapport3(Object p1) {
    return '默契度 · $p1';
  }

  @override
  String partnerRapport4(Object next, Object p1, Object p2) {
    return '默契度 · $p1（$p2/$next）';
  }

  @override
  String partnersAfterDaysWithoutInteracting(
    Object kPartnerDecayPerDay,
    Object kPartnerStaleDays,
  ) {
    return '连续 $kPartnerStaleDays 天不互动，默契度每天 -$kPartnerDecayPerDay';
  }

  @override
  String get partnersFailedLoadRecentPlaymates => '最近玩伴拉取失败';

  @override
  String get partnersFindPeopleYouPlayed => '退出房间后也能找回一起玩过的人';

  @override
  String get partnersMyPartners => '我的拍档';

  @override
  String get partnersNoPartnersYet => '还没有拍档';

  @override
  String get partnersNoPlaymatesYet => '还没有一起玩过的伙伴';

  @override
  String get partnersPartner => '搭子';

  @override
  String get partnersPeopleYouPlayedAppear => '进过房间后这里会出现一起玩过的人';

  @override
  String partnersRapport(Object tacit) {
    return '默契度 $tacit';
  }

  @override
  String partnersRapportDropWithoutInteraction(Object floor, Object tacit) {
    return '默契度 $tacit → 再不互动会降到 $floor';
  }

  @override
  String partnersRapportNextLevel(Object next, Object tacit) {
    return '默契度 $tacit / 下一级 $next';
  }

  @override
  String get partnersRapportRelationLevelServer => '默契度与关系等级（服务端数据）';

  @override
  String get partnersReach100RapportFriend => '在游戏里与好友的默契度达到 100 即可建立拍档关系';

  @override
  String get partnersRecentPlaymates => '最近玩伴';

  @override
  String get partnersRecentlyPlayed => '最近一起玩过';

  @override
  String get partnersRefreshRecentPlaymates => '刷新最近玩伴';

  @override
  String get partnersTimeInteract => '该互动了';

  @override
  String get playerInfoAddFriend => '加好友';

  @override
  String playerInfoAdventurer(Object adv) {
    return '冒险家：$adv';
  }

  @override
  String get playerInfoFriendRequestSent => '已发送好友申请';

  @override
  String get playerInfoMyProfile => '个人中心';

  @override
  String playerInfoRapport(Object tacit) {
    return '默契度：$tacit';
  }

  @override
  String get playerInfoRequestFailedTryAgain => '申请失败，请稍后重试';

  @override
  String get playerInfoSend => '赠送';

  @override
  String get profileAlreadyBlocked => '已在黑名单';

  @override
  String profileAndMaps(Object p1) {
    return '等 $p1 张地图';
  }

  @override
  String get profileArtwork => '立绘';

  @override
  String get profileAvatarFrame => '头像框';

  @override
  String get profileAvatarFrameUpdated => '头像框已更新';

  @override
  String get profileBlock => '拉黑';

  @override
  String get profileCharm => '魅力值';

  @override
  String get profileCouldntLoadProfileLayout => '未取到主页布局';

  @override
  String get profileCreditScore => '信用分';

  @override
  String get profileEdit => '编辑';

  @override
  String get profileEditAvatar => '头像编辑';

  @override
  String get profileEditLayout => '编辑布局';

  @override
  String profileFamily(Object familyName) {
    return '家族: $familyName';
  }

  @override
  String get profileFavoritesCreated => '已创建收藏夹';

  @override
  String get profileFollowers => '粉丝';

  @override
  String get profileFriendBio => '交友宣言';

  @override
  String profileIPRegion(Object p1) {
    return 'IP属地：$p1';
  }

  @override
  String get profileLayoutSaved => '布局已保存';

  @override
  String get profileLightChaseProject => '追光计划';

  @override
  String get profileMedals => '勋章';

  @override
  String get profileMedalsEarned => '已获得勋章';

  @override
  String get profileMiniIDCopied => '迷你号已复制';

  @override
  String get profileMiniTraces => '迷你印迹';

  @override
  String profileMomentsPublished(Object postingCount) {
    return '已发布 $postingCount 条动态';
  }

  @override
  String get profileMyFavorites => '我的收藏夹';

  @override
  String get profileNoFriendBioSet => '还没有设置交友宣言';

  @override
  String get profileNoOwnedSkinsArtwork => '暂未获取到已拥有的皮肤或立绘';

  @override
  String get profileNoPublishedMapWorks => '暂无已发布地图作品';

  @override
  String get profileNoTitleEquipped => '未佩戴称号';

  @override
  String profileOwnAvatarFrames(Object p1) {
    return '已拥有 $p1 个头像框';
  }

  @override
  String profileOwnStylesLocalIcons(Object skinModuleCount) {
    return '已拥有 $skinModuleCount 件装扮（本地暂无对应图标）';
  }

  @override
  String get profilePersonalInfo => '个人资料';

  @override
  String get profilePersonalStyle => '个性装扮';

  @override
  String get profilePhotosShownProfile => '主页展示的照片';

  @override
  String get profilePopularity => '人气值';

  @override
  String get profileProfile => '个人主页';

  @override
  String get profilePublishWork => '发布作品';

  @override
  String get profileRecentVisitors => '最近访客';

  @override
  String get profileRemoveThemBlocklist => '确定将 TA 移出黑名单吗？';

  @override
  String get profileStylesCollected => '已收集装扮';

  @override
  String get profileThisExternalClientDoesnt => '外部客户端暂不展示动态正文';

  @override
  String get profileThisExternalClientHasnt => '外部客户端暂未获取该项数据';

  @override
  String get profileTitle => '称号';

  @override
  String get profileTotalCharmReceivedGifts => '累计收到礼物魅力值';

  @override
  String get profileUnfollowed => '已取消关注';

  @override
  String get profileUnnamed => '未命名';

  @override
  String get profileUse => '使用';

  @override
  String get profileUseArtwork => '使用该立绘';

  @override
  String get profileUseArtworkAvatar => '确定使用该立绘作为头像吗？';

  @override
  String get profileUseAvatar => '使用该头像';

  @override
  String get profileUseAvatarFrame => '使用该头像框';

  @override
  String profileUseAvatarFrame2(Object id) {
    return '确定使用头像框 #$id 吗？';
  }

  @override
  String get profileUseSkinAvatar => '确定使用该皮肤作为头像吗？';

  @override
  String get profileViewMoments => '查看我的动态';

  @override
  String get profileYouWontSeeTheir => '拉黑后将无法看到 TA 的动态与消息，确定？';

  @override
  String get publishDynamicsAVoteNeedsTitle => '投票需要标题和至少 2 个选项';

  @override
  String get publishDynamicsAllowMultipleChoice => '允许多选';

  @override
  String get publishDynamicsAttachVote => '附带投票';

  @override
  String get publishDynamicsChooseFriends => '选择好友';

  @override
  String get publishDynamicsChooseImage => '选择图片';

  @override
  String get publishDynamicsDeadline => '截止时间';

  @override
  String get publishDynamicsDeadlineMustLeast30 => '截止时间需晚于当前时间 30 分钟';

  @override
  String get publishDynamicsDeleteImage => '删除图片';

  @override
  String get publishDynamicsEnterSomeContent => '请输入内容';

  @override
  String publishDynamicsFailedChooseImage(Object e) {
    return '选择图片失败：$e';
  }

  @override
  String get publishDynamicsFailedCreateVote => '投票创建失败';

  @override
  String publishDynamicsFailedDeleteImage(Object e) {
    return '图片删除失败：$e';
  }

  @override
  String publishDynamicsFailedPublishRet(Object p1, Object p2) {
    return '发布失败: ret=$p1 $p2';
  }

  @override
  String get publishDynamicsFriends => '@好友';

  @override
  String get publishDynamicsFriendsVoteAfterYou => '发布后可让好友投票';

  @override
  String publishDynamicsImageUploadFailed(Object p1) {
    return '图片上传失败：$p1';
  }

  @override
  String publishDynamicsImageUploadFailed2(Object e) {
    return '图片上传失败：$e';
  }

  @override
  String publishDynamicsImages(Object _maxPics, Object p1) {
    return '图片（$p1/$_maxPics）';
  }

  @override
  String get publishDynamicsNoFriends => '暂无好友可 @';

  @override
  String publishDynamicsOption(Object p1) {
    return '选项 $p1';
  }

  @override
  String get publishDynamicsPublished => '发布成功';

  @override
  String get publishDynamicsSearchTopics => '搜索话题';

  @override
  String get publishDynamicsShareSomethingNew => '分享新鲜事…';

  @override
  String get publishDynamicsSomeImagesHaventFinished => '有图片尚未上传成功';

  @override
  String get publishDynamicsTopicOptional => '话题（可选）';

  @override
  String get publishDynamicsUploadingImagesWait => '图片上传中，请稍候';

  @override
  String get publishDynamicsVisibility => '可见范围';

  @override
  String get publishDynamicsVoteTitle => '投票标题';

  @override
  String publishDynamicsYouUploadMostImages(Object _maxPics) {
    return '最多只能上传 $_maxPics 张图片';
  }

  @override
  String get qrAskThemEnterNumber => '让对方在「好友 → 按迷你号添加」中输入此号码';

  @override
  String get qrCopyMiniID => '复制迷你号';

  @override
  String get qrMyMiniID => '我的迷你号';

  @override
  String relationFollowers(Object p1) {
    return '我的粉丝 $p1';
  }

  @override
  String relationFollowing(Object p1) {
    return '我的关注 $p1';
  }

  @override
  String get relationNoFollowersYet => '还没有粉丝';

  @override
  String get relationNotFollowingAnyoneYet => '还没有关注任何人';

  @override
  String get requestErrorCopyURL => '复制地址';

  @override
  String get requestErrorFailedRequests => '请求失败记录';

  @override
  String get requestErrorNoFailureRecordsYet => '暂无失败记录';

  @override
  String get requestErrorNoUrl => '(无请求地址)';

  @override
  String get requestErrorRequestURLCopied => '已复制请求地址';

  @override
  String requestErrorRequestsFailed(Object total) {
    return '$total 个请求失败';
  }

  @override
  String get sessionMenuCancelDoDisturb => '取消免打扰';

  @override
  String get sessionMenuCancelOnlineNotification => '取消上线通知';

  @override
  String get sessionMenuDeleteFriend => '删除好友';

  @override
  String sessionMenuDeleteFriend2(Object p1) {
    return '确定删除好友「$p1」吗？';
  }

  @override
  String get sessionMenuDoDisturb => '免打扰';

  @override
  String get sessionMenuDoDisturb2 => '已开启免打扰';

  @override
  String get sessionMenuDoDisturbOff => '已取消免打扰';

  @override
  String get sessionMenuEnterNoteNameLeave => '输入备注名，留空则清除';

  @override
  String get sessionMenuFailedNudge => '拍一拍失败';

  @override
  String get sessionMenuFriendDeleted => '已删除好友';

  @override
  String get sessionMenuNote => '备注';

  @override
  String get sessionMenuNoteName => '备注名';

  @override
  String get sessionMenuNoteSaved => '备注已保存';

  @override
  String get sessionMenuNudge => '拍一拍';

  @override
  String get sessionMenuNudged => '已拍一拍';

  @override
  String get sessionMenuOnlineNotification => '已开启上线通知';

  @override
  String get sessionMenuOnlineNotificationOff => '已关闭上线通知';

  @override
  String get sessionMenuRemoveConversation => '移除会话';

  @override
  String get sessionsConversationRemoved => '已移除会话';

  @override
  String sessionsFriend(Object p1) {
    return '好友 $p1';
  }

  @override
  String sessionsGroup(Object p1) {
    return '群 $p1';
  }

  @override
  String get sessionsNoConversationsPeopleYou => '暂无会话\\n聊过天的人会出现在这里';

  @override
  String get sessionsNoMatchingConversations => '没有匹配的会话';

  @override
  String get sessionsOnlyConversationsChattedDevice => '历史消息只保留本机聊过的会话';

  @override
  String get sessionsSearchConversationsNicknameMini => '搜索会话（昵称或迷你号）';

  @override
  String get sessionsSearchMiniIDNickname => '支持迷你号和昵称查找';

  @override
  String get settingsAboutAbout => '关于';

  @override
  String settingsAboutAlreadyUpDate(Object kAppVersion) {
    return '已是最新版本（$kAppVersion）';
  }

  @override
  String get settingsAboutAppPrivateDirectoryAuto => '应用私有目录（自动轮转）';

  @override
  String settingsAboutCheckFailedYouAlso(Object p1) {
    return '检查失败：$p1\\n\\n也可以直接到 Releases 页面查看：\\n';
  }

  @override
  String get settingsAboutCheckLatestBuildGitHub => '查询 GitHub 上的最新构建';

  @override
  String get settingsAboutCheckUpdates => '检查更新';

  @override
  String get settingsAboutChecking => '正在检查…';

  @override
  String get settingsAboutClearLogs => '清空日志';

  @override
  String get settingsAboutDeleteRotatedLogFiles => '删除全部轮转日志文件';

  @override
  String get settingsAboutExportDiagnostics => '导出诊断信息';

  @override
  String settingsAboutFailedClear(Object e) {
    return '清空失败：$e';
  }

  @override
  String settingsAboutFailedCollectDiagnostics(Object e) {
    return '汇总诊断失败：$e';
  }

  @override
  String get settingsAboutGotIt => '知道了';

  @override
  String get settingsAboutLogFiles => '日志文件';

  @override
  String get settingsAboutLogsCleared => '日志已清空';

  @override
  String get settingsAboutMnChat => '关于 MnChat';

  @override
  String settingsAboutNewVersionAvailableCurrent(
    Object kAppVersion,
    Object p1,
    Object p2,
  ) {
    return '发现新版本 $p1（当前 $kAppVersion）\\n\\n$p2';
  }

  @override
  String get settingsAboutNewVersionFound => '发现新版本';

  @override
  String get settingsAboutNoLogsYet => '暂无日志';

  @override
  String get settingsAboutNone => '（无）';

  @override
  String get settingsAboutOpenSourceLicenses => '开源许可';

  @override
  String get settingsAboutOther => '其他';

  @override
  String get settingsAboutRecentRequestFailures => '## 最近的请求失败';

  @override
  String get settingsAboutThirdPartyDependenciesLicenses => '第三方依赖与许可证';

  @override
  String get settingsAboutVersion => '版本';

  @override
  String get settingsAboutVersionPlatformTableCounts =>
      '版本 / 平台 / 表计数 / 日志尾部 / 最近请求失败';

  @override
  String get settingsAccount => '账号';

  @override
  String get settingsAccountAccountSecurity => '账号与安全';

  @override
  String get settingsAccountAppLock => '应用锁';

  @override
  String get settingsAccountAppLockDisabled => '已关闭应用锁';

  @override
  String get settingsAccountAppLockEnabled => '已开启应用锁';

  @override
  String get settingsAccountAutoSign => '自动登录';

  @override
  String get settingsAccountAutoSignDisabled => '已关闭自动登录';

  @override
  String get settingsAccountAutoSignEnabledCredentials => '已开启自动登录（下次登录将保存凭据）';

  @override
  String get settingsAccountDigits48 => '4-8 位数字';

  @override
  String get settingsAccountDigits68 => '6-8 位数字';

  @override
  String get settingsAccountEnterAppLockPassword => '输入应用锁密码';

  @override
  String get settingsAccountPasswordLength => '密码需为 6-8 位数字';

  @override
  String get settingsAccountPasswordsDontMatch => '两次输入不一致';

  @override
  String get settingsAccountProfile => '资料';

  @override
  String get settingsAccountReEnterPassword => '再次输入密码';

  @override
  String get settingsAccountRequirePasswordLaunchReturning =>
      '启动 / 回前台时需输入密码解锁';

  @override
  String get settingsAccountSecurity => '安全';

  @override
  String get settingsAccountSetAppLockPassword => '设置应用锁密码';

  @override
  String get settingsAccountSetBioWantLike => '设置我的个性签名（想要/喜欢）';

  @override
  String get settingsAccountSignAutomaticallyNextLaunch =>
      '开启后下次启动自动登录（需先登录一次以保存凭据）';

  @override
  String get settingsAccountSocialTags => '交友标签';

  @override
  String get settingsAccountViewAvatarEditNickname => '查看头像 / 修改昵称 / 头像框';

  @override
  String get settingsAppLock => '应用锁已开启';

  @override
  String get settingsDark => '深色';

  @override
  String get settingsFollowSystem => '跟随系统';

  @override
  String get settingsFriendRequestLimitsVisit => '加好友限制 / 访问踪迹 / 聊天记录 / 存储占用';

  @override
  String get settingsGeneralAppearance => '外观';

  @override
  String get settingsGeneralAvatarFrameAnimation => '头像框动画';

  @override
  String get settingsGeneralCloseTray => '关闭到托盘';

  @override
  String get settingsGeneralConversationOrder => '会话排序';

  @override
  String get settingsGeneralDesktop => '桌面';

  @override
  String get settingsGeneralGeneralAppearance => '通用与外观';

  @override
  String get settingsGeneralLightDarkModeAccent => '明暗模式 / 强调色 / 聊天字号';

  @override
  String get settingsGeneralMinimizeSystemTrayInstead => '关闭窗口时最小化到系统托盘而非退出';

  @override
  String get settingsGeneralMinimizeTrayWhenClosing => '关闭窗口时将最小化到托盘';

  @override
  String get settingsGeneralNoSystemTrayAvailable =>
      '当前桌面没有可用的系统托盘，关闭窗口会直接退出（已自动关闭）';

  @override
  String get settingsGeneralQuitWhenClosingWindow => '关闭窗口时将直接退出';

  @override
  String get settingsGeneralSwitchBetweenOwnedChat => '切换已拥有的聊天气泡';

  @override
  String get settingsGeneralThemeDisplaySettings => '主题显示设置';

  @override
  String get settingsGeneralWhenOffStaticAvatar => '关闭后仅显示静态头像框，省电省流';

  @override
  String get settingsLight => '浅色';

  @override
  String get settingsNotificationAdd => '添加';

  @override
  String get settingsNotificationAddPhrase => '新增短语';

  @override
  String get settingsNotificationAddQuickPhrase => '新增快捷短语';

  @override
  String get settingsNotificationBackgroundConnectionDisabled => '已关闭后台保持连接';

  @override
  String get settingsNotificationBackgroundConnectionEnabled => '已开启后台保持连接';

  @override
  String get settingsNotificationBackgroundNotificationsArentSupported =>
      '当前平台不支持后台通知';

  @override
  String get settingsNotificationClearUnreadMarkerWhen => '打开会话即清除未读标记';

  @override
  String get settingsNotificationDoDisturbEnds => '免打扰结束';

  @override
  String get settingsNotificationDoDisturbHours => '免打扰时段';

  @override
  String get settingsNotificationDoDisturbHoursUpdated => '免打扰时段已更新';

  @override
  String get settingsNotificationDoDisturbStarts => '免打扰开始';

  @override
  String get settingsNotificationEnterPhraseContent => '输入短语内容';

  @override
  String get settingsNotificationHideNotificationContent => '通知隐藏内容';

  @override
  String get settingsNotificationInsertQuicklyWhenSending =>
      '发送消息时快捷插入（对齐游戏内置 SecretQuickMsg）';

  @override
  String get settingsNotificationKeepConnectionBackground => '后台保持连接';

  @override
  String get settingsNotificationLongPressConversationList => '在会话列表长按某条会话设置';

  @override
  String get settingsNotificationMarkReadOpen => '进入会话自动已读';

  @override
  String get settingsNotificationMessages => '消息';

  @override
  String get settingsNotificationMessagesNotifications => '消息与通知';

  @override
  String get settingsNotificationNewMessageNotifications => '新消息通知';

  @override
  String get settingsNotificationNewMessageNotificationsDisabled => '已关闭新消息通知';

  @override
  String get settingsNotificationNewMessageNotificationsEnabled => '已开启新消息通知';

  @override
  String get settingsNotificationNoPhrasesYet => '暂无短语';

  @override
  String get settingsNotificationNotificationSound => '通知提示音';

  @override
  String get settingsNotificationNotificationVibration => '通知震动';

  @override
  String get settingsNotificationNotifications => '通知';

  @override
  String get settingsNotificationOnDesktopPressEnter =>
      '桌面端按 Enter 发送，Shift+Enter 换行';

  @override
  String get settingsNotificationOnlyAlertMeMentions => '群里仅 @我 时提醒';

  @override
  String get settingsNotificationPerConversationMutePin => '会话级免打扰 / 置顶';

  @override
  String get settingsNotificationPhraseAlreadyExistsInvalid => '短语已存在或内容无效';

  @override
  String get settingsNotificationQuickPhrases => '快捷短语';

  @override
  String get settingsNotificationSendEnter => '回车发送';

  @override
  String get settingsNotificationShowNewMessageAlert => '锁屏 / 通知栏只提示有新消息，不显示正文';

  @override
  String get settingsNotificationShowSystemNotificationNew =>
      '应用在后台时收到新消息弹出系统通知';

  @override
  String get settingsNotificationTheForegroundServiceKeeps =>
      '由前台服务维持长连接，后台也能收到新消息';

  @override
  String get settingsNotificationVibrateWhenNewMessage => '收到新消息时震动提醒';

  @override
  String get settingsNotificationWhenGroupMessagesNotify =>
      '开启后群消息只有提到我（正文含 @我的昵称）才弹通知，私聊不受影响';

  @override
  String get settingsNotificationWhenOffNotificationsArrive =>
      '关闭后通知静默到达（通知本身照常出现）';

  @override
  String get settingsNotificationYouWontReceiveSystem => '应用退到后台后不会收到系统通知。';

  @override
  String settingsNotificationsDoDisturb(Object p1) {
    return '通知开 · 免打扰 $p1';
  }

  @override
  String get settingsNotificationsDoDisturb2 => '通知开 · 未设免打扰';

  @override
  String get settingsNotificationsOff => '通知已关闭';

  @override
  String get settingsPreferences => '偏好';

  @override
  String get settingsPrivacyAllowOthersAddMe => '允许他人拉我入群';

  @override
  String get settingsPrivacyAutomaticallyJoinInvitedGroups => '自动加入被邀请的群';

  @override
  String get settingsPrivacyBlockFriendRequestsStrangers => '拒绝陌生人加好友';

  @override
  String get settingsPrivacyClearImageCache => '清除图片缓存';

  @override
  String get settingsPrivacyClearing => '正在清除…';

  @override
  String get settingsPrivacyCounting => '正在统计…';

  @override
  String get settingsPrivacyData => '隐私与数据';

  @override
  String get settingsPrivacyData2 => '数据';

  @override
  String get settingsPrivacyDatabaseSizeRetentionClear =>
      '数据库占用 / 保留期 / 按会话清理 / VACUUM';

  @override
  String get settingsPrivacyDeletesCachedAvatarsMoment =>
      '将删除已缓存的头像与动态图片，下次显示时重新下载。聊天记录不受影响。';

  @override
  String get settingsPrivacyDisabledStrangersAddMe => '已关闭：允许陌生人加好友';

  @override
  String get settingsPrivacyEnabledStrangersCantAdd => '已开启：拒绝陌生人加好友';

  @override
  String get settingsPrivacyExportImportChatData => '导出 / 导入聊天数据备份';

  @override
  String get settingsPrivacyImageCacheCleared => '图片缓存已清除';

  @override
  String get settingsPrivacyLeaveTraceWhenVisiting => '访问主页留下踪迹';

  @override
  String get settingsPrivacyPrivacy => '隐私';

  @override
  String get settingsPrivacyStorageManagement => '存储管理';

  @override
  String settingsPrivacyUsingAvatarsMomentImages(Object p1) {
    return '当前占用 $p1（头像与动态图片）';
  }

  @override
  String get settingsPrivacyWhenIJoinAutomatically => '开启后收到邀请将自动进群';

  @override
  String get settingsPrivacyWhenOffInvitationsOthers => '关闭后他人邀请将被拒绝';

  @override
  String get settingsPrivacyWhenOffViewingSomeones => '关闭后，查看他人主页不会出现在对方的访客记录中';

  @override
  String get settingsPrivacyWhenStrangersCantAdd => '开启后陌生人无法添加我为好友';

  @override
  String get settingsProfileSocialTagsAuto => '个人资料 / 交友标签 / 自动登录';

  @override
  String get settingsSettings => '设置';

  @override
  String get settingsSignOut => '退出登录';

  @override
  String get settingsSignOut2 => '退出';

  @override
  String get settingsSignOutCurrentAccount => '确定要退出当前账号吗？';

  @override
  String settingsThemeTextSizeBubbles(Object p1) {
    return '$p1 · 主题 / 字号 / 气泡 / 会话排序';
  }

  @override
  String settingsVCheckUpdatesOpen(Object kAppVersion) {
    return 'v$kAppVersion · 检查更新 / 开源许可 / 诊断导出';
  }

  @override
  String get shellFriendsGroupChatsRoom => '好友 / 群聊 · 无需进入房间';

  @override
  String get shellMoments => '动态';

  @override
  String get shellSelectConversationStartChatting => '选择会话开始聊天';

  @override
  String get signFailedSave => '保存失败';

  @override
  String signFailedSave2(Object e) {
    return '保存失败: $e';
  }

  @override
  String get signLike => '喜欢…';

  @override
  String get signMyCard => '我的名片';

  @override
  String get signNotSet => '不设置';

  @override
  String get signNotSet2 => '未设置';

  @override
  String get signSaved => '已保存';

  @override
  String get signWant => '想要…';

  @override
  String get storageAutoCleanup => '自动清理';

  @override
  String storageCleanupFailed(Object e) {
    return '清理失败：$e';
  }

  @override
  String get storageClearConversation => '按会话清理';

  @override
  String get storageClearConversationHistory => '清理会话记录';

  @override
  String get storageConversationHistoryCleared => '已清理该会话记录';

  @override
  String storageDeleteLocalChatHistory(Object p1) {
    return '将删除本机「$p1」的全部聊天记录（服务端记录不受影响）。此操作无法撤销。';
  }

  @override
  String get storageDeleteOlderLocalRecords => '删除更早的本机记录';

  @override
  String storageDeletedRecords(Object removed) {
    return '已删除 $removed 条记录';
  }

  @override
  String storageKeepLastDays(Object days) {
    return '只保留最近 $days 天';
  }

  @override
  String storageMessagesConversations(Object _messageCount, Object p1) {
    return '$_messageCount 条消息 · $p1 个会话';
  }

  @override
  String storageMessagesDotSessions(Object p1, Object p2) {
    return '$p1 条 · $p2';
  }

  @override
  String get storageNoLocalChatHistory => '本机还没有聊天记录';

  @override
  String storagePermanentlyDeleteLocalChat(Object days) {
    return '将永久删除本机 $days 天以前的聊天记录（服务端记录不受影响）。此操作无法撤销。';
  }

  @override
  String get storageProcessing => '处理中…';

  @override
  String storageReclaimFailed(Object e) {
    return '回收失败：$e';
  }

  @override
  String get storageReclaimFreeSpace => '回收空闲空间';

  @override
  String get storageReclaimedFreeSpace => '已回收空闲空间';

  @override
  String get storageStorageUsed => '本机占用';

  @override
  String get storageVACUUMRunAfterDeleting => 'VACUUM（删除记录后执行）';

  @override
  String get themeSettingsAccentColor => '强调色';

  @override
  String get themeSettingsAndroidFollowsWallpaperLinux =>
      'Android 跟随壁纸取色、Linux 跟随桌面主题色；开启后上面的强调色不再生效';

  @override
  String get themeSettingsChatTextSize => '聊天字号';

  @override
  String get themeSettingsExampleMessageScalesText => '示例：这条消息会随字号缩放。';

  @override
  String get themeSettingsGotReply => '收到！这是我的回复。';

  @override
  String get themeSettingsHiSampleMessageOther => '你好，这是对方的示例消息。';

  @override
  String get themeSettingsHighContrast => '高对比度';

  @override
  String get themeSettingsIncreaseForegroundBackgroundContrast =>
      '提高前景 / 背景对比（M3 高对比档），弱视或强光下更易读';

  @override
  String get themeSettingsLivePreview => '实时预览';

  @override
  String get themeSettingsOnlyAppliesDarkMode => '仅深色模式生效（当前为浅色模式）';

  @override
  String get themeSettingsPureBlackModeAMOLED => '纯黑模式（AMOLED）';

  @override
  String get themeSettingsResetDefault => '恢复默认';

  @override
  String get themeSettingsShowRawTextRich => '富文本显示原文本';

  @override
  String get themeSettingsThemeMode => '主题模式';

  @override
  String get themeSettingsUsePureBlackBackgrounds =>
      '深色模式下背景改用纯黑，OLED 屏更省电、观感更沉';

  @override
  String get themeSettingsUseSystemColors => '跟随系统取色';

  @override
  String get themeSettingsWhenGameTagsLike =>
      '开启后，[i][color][b] 等游戏标签原样显示，不再渲染颜色、加粗或表情';

  @override
  String videoUnablePlay(Object error) {
    return '无法播放：$error';
  }

  @override
  String get videoVideo => '视频';

  @override
  String get visitorsNoVisitorsYet => '还没有人来访';

  @override
  String get visitorsVisitorRecords => '访客记录';

  @override
  String get voiceNoMicrophonePermissionDevice => '拿不到麦克风权限，或设备不可用';

  @override
  String voicePlayingVoiceSeconds(Object total) {
    return '播放语音 $total 秒';
  }

  @override
  String get voiceStopSend => '停止并发送';

  @override
  String get voiceVoicePlaybackIsntSupported => '当前平台暂不支持播放语音';

  @override
  String get bubbleNameStyleNote => '气泡名称/样式由游戏内置配置决定，外部客户端无法显示，仅能切换佩戴。';

  @override
  String chatRoomNameInGame(Object p1) {
    return '房间: $p1（需在游戏内加入）';
  }

  @override
  String get dataImportMergeConfirm =>
      '将把备份文件中的消息 / 会话 / 好友合并到当前账号，已存在的记录会自动跳过，不会删除或覆盖本地数据。是否继续？';

  @override
  String dataImportSummary(Object p1, Object p2, Object p3) {
    return '导入完成：消息 $p1 条，会话 $p2 个，好友 $p3 个';
  }

  @override
  String settingsAboutCheckFailedWithUrl(Object p1, Object p2) {
    return '检查失败：$p1\n\n也可以直接到 Releases 页面查看：\n$p2';
  }

  @override
  String settingsAboutClientLine(Object p1, Object p2, Object p3) {
    return '迷你世界外部聊天客户端 · 客户端 $p1 ($p2) · $p3';
  }

  @override
  String settingsAboutLogSizeNote(Object p1) {
    return '$p1 KB · 应用私有目录（自动轮转）';
  }

  @override
  String storageMessagesAndSessions(Object p1, Object p2) {
    return '$p1 条消息 · $p2 个会话';
  }

  @override
  String storageFreePagesNote(Object p1) {
    return ' · $p1 个空闲页可回收';
  }

  @override
  String chatFoundCount(Object p1) {
    return '找到 $p1 条';
  }

  @override
  String get chatRecent100Only => '（只列出最近 100 条）';

  @override
  String loginRemoveAccountConfirm(Object p1) {
    return '移除 $p1？\n（不影响游戏端账号）';
  }

  @override
  String playerInfoTitleWithValue(Object p1) {
    return '称号：$p1';
  }

  @override
  String chatAmountYuan(Object p1) {
    return '金额 ¥$p1';
  }

  @override
  String get dataExportEncrypted => '导出（加密）';

  @override
  String get dataExportEncryptedHint => '设置口令后用 AES-256-GCM 加密备份文件';

  @override
  String get dataPassphraseEmpty => '口令不能为空';

  @override
  String get dataPassphraseMismatch => '两次输入的口令不一致';

  @override
  String get dataSetBackupPassphrase => '设置备份口令';

  @override
  String get dataEnterBackupPassphrase => '输入备份口令';

  @override
  String get dataPassphrase => '口令';

  @override
  String get dataPassphraseHint => '至少 6 位，忘记后无法恢复';

  @override
  String get dataPassphraseAgain => '再次输入';

  @override
  String get dataConfirm => '确定';

  @override
  String get settingsAboutDownloadUpdate => '下载并安装';

  @override
  String get settingsAboutDownloading => '正在下载更新';

  @override
  String get settingsAboutNoPackageForPlatform => '该版本没有提供当前平台的安装包';

  @override
  String get settingsAboutUpdateOpened => '已打开安装包';

  @override
  String get settingsAboutUpdateSaved => '安装包已下载，可在文件管理器中手动安装';

  @override
  String get settingsAboutUpdateDownloadFailed => '下载失败，请检查网络后重试';

  @override
  String get chatDropImageHere => '松开以发送图片';

  @override
  String get chatDropOnlyImages => '只支持拖入图片文件';

  @override
  String get chatImageReadFailed => '读取图片失败';
}
