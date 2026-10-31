// ignore: unused_import
import 'package:intl/intl.dart' as intl;

import 'app_localizations.dart';

// ignore_for_file: type=lint

/// The translations for English (`en`).
class AppLocalizationsEn extends AppLocalizations {
  AppLocalizationsEn([String locale = 'en']) : super(locale);

  @override
  String get appTitle => 'MnChat · Mini World external chat';

  @override
  String get menuCopy => 'Copy';

  @override
  String get menuQuote => 'Quote';

  @override
  String get menuForward => 'Forward';

  @override
  String get menuMultiSelect => 'Select';

  @override
  String get menuFavorite => 'Favorites';

  @override
  String get menuUnfavorite => 'Unfavorite';

  @override
  String get menuDeleteLocal => 'Delete (this device only)';

  @override
  String get menuResend => 'Resend';

  @override
  String get sheetMessageActions => 'Message actions';

  @override
  String get favoritesTitle => 'Favorites';

  @override
  String get favoritesEmpty => 'No saved messages yet';

  @override
  String get favoritesEmptyHint => 'Long-press any message to save it';

  @override
  String get searchTitle => 'Search chat history';

  @override
  String get searchHint => 'Search all conversations';

  @override
  String get searchEmpty => 'No matching messages';

  @override
  String get searchEmptyHint =>
      'Try another keyword; single characters work too';

  @override
  String searchCount(int count) {
    return 'Found $count';
  }

  @override
  String get searchScopeAll => 'All conversations';

  @override
  String selectedCount(int count) {
    return '$count selected';
  }

  @override
  String get actionForward => 'Forward';

  @override
  String get actionDelete => 'Delete';

  @override
  String get actionFavorite => 'Favorites';

  @override
  String get toastCopied => 'Copied';

  @override
  String get toastFavorited => 'Saved';

  @override
  String get toastUnfavorited => 'Removed from favorites';

  @override
  String get toastDeletedLocal => 'Deleted on this device';

  @override
  String get toastForwarded => 'Forwarded';

  @override
  String get commonCancel => 'Cancel';

  @override
  String get commonClose => 'Close';

  @override
  String get commonConfirm => 'OK';

  @override
  String get commonUndo => 'Undo';

  @override
  String get forwardPickSession => 'Choose a conversation to forward to';

  @override
  String get forwardNoTarget => 'No friends or groups to forward to';

  @override
  String get deleteLocalConfirmTitle => 'Delete message on this device?';

  @override
  String get deleteLocalConfirmBody =>
      'Only affects local records; the other party and other devices can still see this message.';

  @override
  String get quotePrefix => 'Quote';

  @override
  String get voiceMessage => 'Voice';

  @override
  String get typingIndicator => 'The other person is typing…';

  @override
  String get accountMenuChooseMembersOptional => 'Choose members (optional)';

  @override
  String get accountMenuCreate => 'Create';

  @override
  String get accountMenuCreateGroup => 'Create group';

  @override
  String get accountMenuEnterGroupName => 'Enter group name';

  @override
  String get accountMenuEnterGroupName2 => 'Enter a group name';

  @override
  String accountMenuFailedCreate(Object e) {
    return 'Failed to create: $e';
  }

  @override
  String accountMenuFailedCreateRet(Object ret) {
    return 'Failed to create: ret=$ret';
  }

  @override
  String get accountMenuGroupCreated => 'Group created';

  @override
  String get accountMenuMenu => 'Menu';

  @override
  String get accountMenuMyProfile => 'My profile';

  @override
  String get accountMenuRefreshConversations => 'Refresh conversations';

  @override
  String get accountMenuSwitchAccount => 'Switch account';

  @override
  String get avatarEditAvatar => 'Avatar';

  @override
  String get avatarEditAvatarInfoMissingTry =>
      'Avatar info missing, please try again later';

  @override
  String get avatarEditAvatarUpdated => 'Avatar updated';

  @override
  String get avatarEditChooseCustomAvatar => 'Choose a custom avatar';

  @override
  String get avatarEditConfirmChange => 'Confirm change';

  @override
  String get avatarEditCost => 'Cost';

  @override
  String get avatarEditCustom => 'Custom';

  @override
  String get avatarEditDeveloper => 'Developer';

  @override
  String get avatarEditDisplayedFamilyUpdated => 'Displayed family updated';

  @override
  String get avatarEditEnterNewName => 'Enter a new name';

  @override
  String avatarEditFailedChangeName(Object e) {
    return 'Failed to change name: $e';
  }

  @override
  String avatarEditFailedEquip(Object e) {
    return 'Failed to equip: $e';
  }

  @override
  String get avatarEditFailedEquipTryAgain =>
      'Failed to equip, please try again later';

  @override
  String get avatarEditFailedLoadFamilyList => 'Failed to load family list';

  @override
  String get avatarEditFailedLoadTitleList => 'Failed to load title list';

  @override
  String get avatarEditFailedPinTryAgain =>
      'Failed to pin, please try again later';

  @override
  String avatarEditFailedSet(Object e) {
    return 'Failed to set: $e';
  }

  @override
  String get avatarEditFailedSetTryAgain =>
      'Failed to set, please try again later';

  @override
  String avatarEditFailedSwitch(Object e) {
    return 'Failed to switch: $e';
  }

  @override
  String get avatarEditFailedSwitchTryAgain =>
      'Failed to switch, please try again later';

  @override
  String get avatarEditFailedUnpinTryAgain =>
      'Failed to unpin, please try again later';

  @override
  String get avatarEditFreeMembers => 'Free for members';

  @override
  String get avatarEditInUse => 'In use';

  @override
  String get avatarEditMiniSeason => 'Mini Season';

  @override
  String get avatarEditMount => 'Mount';

  @override
  String get avatarEditNameChanged => 'Name changed';

  @override
  String get avatarEditNickname => 'Nickname';

  @override
  String get avatarEditNoTitlesCategory => 'No titles in this category';

  @override
  String avatarEditOperationFailed(Object e) {
    return 'Operation failed: $e';
  }

  @override
  String get avatarEditOutfit => 'Outfit';

  @override
  String get avatarEditPersonality => 'Personality';

  @override
  String get avatarEditPleaseDontUploadImages =>
      'Please don\'t upload images with horror, offensive or other inappropriate content';

  @override
  String get avatarEditRenameCostReviewDecided =>
      'Rename cost and review are decided by the server';

  @override
  String get avatarEditReviewFailed => 'Review failed';

  @override
  String get avatarEditSelectedSwitchAutomaticallyAfter =>
      'Selected; it will switch automatically after review';

  @override
  String get avatarEditThisExternalClientHasnt =>
      'This external client hasn\'t fetched mount avatars yet';

  @override
  String get avatarEditThisImageViolatesRules =>
      'This image violates the rules and can\'t be used';

  @override
  String get avatarEditTitleCategoryConfigFetched =>
      'Title category config not fetched, filtering by category isn\'t available yet';

  @override
  String get avatarEditTitleEquipped => 'Title equipped';

  @override
  String get avatarEditUnderReview => 'Under review';

  @override
  String avatarEditUploadFailed(Object e) {
    return 'Upload failed: $e';
  }

  @override
  String get avatarEditUploadFailedTryAgain =>
      'Upload failed, please try again later';

  @override
  String get avatarEditUploadedPendingReview => 'Uploaded, pending review';

  @override
  String get avatarEditValidUntil => 'Valid until';

  @override
  String get badgesPremiumMember => 'Premium member';

  @override
  String badgesRapport(Object p1) {
    return 'Rapport · $p1';
  }

  @override
  String badgesRapport2(Object next, Object p1, Object tacitnum) {
    return 'Rapport · $p1 ($tacitnum/$next)';
  }

  @override
  String get blocklistAdd => 'Add to blocklist';

  @override
  String get blocklistAdded => 'Added to blocklist';

  @override
  String get blocklistClear => 'Clear';

  @override
  String get blocklistClearAll => 'Clear blocklist';

  @override
  String get blocklistCleared => 'Cleared';

  @override
  String get blocklistEmpty => 'No blocked friends';

  @override
  String get blocklistEnterMiniIdToBlock => 'Enter the Mini ID to block';

  @override
  String blocklistFailedClear(Object e) {
    return 'Failed to clear: $e';
  }

  @override
  String blocklistMiniId(Object p1) {
    return 'Mini ID $p1';
  }

  @override
  String get blocklistMiniIdUin => 'Mini ID (Uin)';

  @override
  String get blocklistRemove => 'Remove from blocklist';

  @override
  String get blocklistRemoveAllFriends =>
      'Remove all friends from the blocklist?';

  @override
  String get blocklistRemoved => 'Removed from blocklist';

  @override
  String bubbleBubble(Object p1) {
    return 'Bubble #$p1';
  }

  @override
  String bubbleBubbleEquipped(Object id) {
    return 'Bubble #$id equipped';
  }

  @override
  String get bubbleBubbleNamesStylesDefined =>
      'Bubble names/styles are defined by the game\'s built-in config and cannot be shown by external clients,';

  @override
  String get bubbleBubbleUnequipped => 'Bubble unequipped';

  @override
  String get bubbleChatBubble => 'Chat bubble';

  @override
  String get bubbleExpired => 'Expired';

  @override
  String get bubbleNoBubblesAvailableYet => 'No bubbles available yet';

  @override
  String get bubbleOnlyEquipSwitchingAvailable =>
      'only equip switching is available.';

  @override
  String get bubblePermanent => 'Permanent';

  @override
  String get bubbleUnequip => 'Unequip';

  @override
  String bubbleValidUntil(Object dd, Object mo) {
    return 'Valid until $mo-$dd';
  }

  @override
  String get chatAnimatedEmoji => 'Animated emoji';

  @override
  String chatAuthor(Object p1) {
    return 'Author: $p1';
  }

  @override
  String get chatBack => 'Back';

  @override
  String get chatBackLatest => 'Back to latest';

  @override
  String get chatChooseAudioFile => 'Choose an audio file';

  @override
  String get chatChooseImageSend => 'Choose an image to send';

  @override
  String get chatChooseVoiceFileSend => 'Choose a voice file to send';

  @override
  String chatCopied(Object p1) {
    return 'Copied $p1';
  }

  @override
  String get chatCopySelected => 'Copy selected';

  @override
  String get chatCouldntFetchGroupMember =>
      'Couldn\'t fetch the group member list yet, try again later';

  @override
  String get chatEmoji => 'Emoji';

  @override
  String get chatEnterKeywordsSearchChat =>
      'Enter keywords to search this chat';

  @override
  String get chatExitSearch => 'Exit search';

  @override
  String get chatExportSelected => 'Export selected';

  @override
  String get chatExportSelectedMessages => 'Export selected messages';

  @override
  String chatExported(Object path) {
    return 'Exported to $path';
  }

  @override
  String chatFailedExport(Object e) {
    return 'Failed to export: $e';
  }

  @override
  String chatFailedForward(Object e) {
    return 'Failed to forward: $e';
  }

  @override
  String chatFailedLoadMoments(Object e) {
    return 'Failed to load moments: $e';
  }

  @override
  String chatFailedReadImage(Object e) {
    return 'Failed to read image: $e';
  }

  @override
  String chatFailedSend(Object e) {
    return 'Failed to send: $e';
  }

  @override
  String chatForwardChatHistory(Object text) {
    return 'Forward chat history:\n$text';
  }

  @override
  String get chatGift => 'Gift';

  @override
  String get chatGiftsSentFriendChats =>
      'Gifts can only be sent in friend chats';

  @override
  String get chatGreetingHi => 'Hi~';

  @override
  String get chatGroup => 'Group';

  @override
  String get chatGroupChat => 'Group chat';

  @override
  String get chatGroupDetails => 'Group details';

  @override
  String get chatGroupMembers => '@Group members';

  @override
  String get chatImage => 'Image';

  @override
  String get chatImageUploadFailedTry =>
      'Image upload failed, please try again later';

  @override
  String get chatInteractiveEmojiCurrentlyWork =>
      'Interactive emoji currently only work in friend chats';

  @override
  String get chatInvitesYouPlayFound =>
      'Invites you to play · Found a fun map, come join';

  @override
  String get chatInvitesYouPlayJoin =>
      'Invites you to play · Join the room in-game';

  @override
  String get chatJoinGame => '(Join in-game)';

  @override
  String get chatJoinRoomGame => 'Join the room in-game';

  @override
  String get chatJumpDate => 'Jump to a date';

  @override
  String get chatLetsPlayTogether => 'Let\'s play together';

  @override
  String get chatLoadEarlier => 'Load earlier';

  @override
  String get chatLoading => 'Loading…';

  @override
  String get chatMap => 'Map';

  @override
  String get chatMapShare => 'Map share';

  @override
  String get chatMe => 'Me';

  @override
  String get chatMessagesISent => 'Messages I sent';

  @override
  String chatMessagesNotSent(Object count) {
    return '$count messages not sent';
  }

  @override
  String chatMiniID(Object p1) {
    return 'Mini ID $p1';
  }

  @override
  String get chatNewMessagesBelow => 'New messages below';

  @override
  String get chatNoEarlierChatHistory => 'No earlier chat history';

  @override
  String get chatNoImageFilePath => 'No image file path in clipboard';

  @override
  String get chatNoMatchingMembers => 'No matching members';

  @override
  String get chatNoMessagesAroundDate => 'No messages around this date';

  @override
  String get chatNoMessagesYetSay => 'No messages yet, say hello 👋';

  @override
  String get chatNoTextContent => '(No text content)';

  @override
  String get chatOlderChatHistoryStored =>
      'Older chat history is stored locally';

  @override
  String get chatOpenMapGame => 'Open the map in-game';

  @override
  String get chatPasteImage => 'Paste image';

  @override
  String chatRapport(Object p1) {
    return 'Rapport +$p1';
  }

  @override
  String get chatRapportGift => 'Rapport gift';

  @override
  String get chatRecord => 'Record';

  @override
  String get chatRecordMicrophoneNow => 'Record with your microphone now';

  @override
  String get chatRedPacketsMustClaimed => 'Red packets must be claimed in-game';

  @override
  String chatResent(Object sent) {
    return 'Resent $sent';
  }

  @override
  String get chatRoom => 'Room';

  @override
  String get chatRoomInvite => 'Room invite';

  @override
  String chatRoomWithName(Object p1) {
    return 'Room: $p1';
  }

  @override
  String get chatSayHello => 'Say hello';

  @override
  String get chatSearchChat => 'Search this chat';

  @override
  String get chatSearchGroupMembers => 'Search group members';

  @override
  String get chatSearchMessages => 'Search messages';

  @override
  String chatSelected(Object p1) {
    return '$p1 selected';
  }

  @override
  String get chatSendFirstMessageStart =>
      'Send the first message to start your adventure';

  @override
  String get chatStillSentTryAgain => 'Still not sent, try again later';

  @override
  String get chatTheirMessages => 'Their messages';

  @override
  String get chatThem => 'Them';

  @override
  String get chatThisMessageTextForward =>
      'This message has no text to forward';

  @override
  String get chatThisMessageTextResend => 'This message has no text to resend';

  @override
  String get chatTypeMessage => 'Type a message…';

  @override
  String chatViewingHistory(Object p1, Object p2, Object p3) {
    return 'Viewing history from $p1-$p2-$p3';
  }

  @override
  String chatVoice(Object p1) {
    return '[Voice] $p1';
  }

  @override
  String get chatVoiceShort => '[Voice]';

  @override
  String get chatVoiceUploadFailedTry =>
      'Voice upload failed, please try again later';

  @override
  String get chatWhatYouUp => 'What are you up to';

  @override
  String get commonBestPartners => 'Best partners';

  @override
  String get commonConversations => 'Conversations';

  @override
  String commonFailedLoad(Object _error) {
    return 'Failed to load: $_error';
  }

  @override
  String commonFailedLoad2(Object e) {
    return 'Failed to load: $e';
  }

  @override
  String get commonFamily => 'Family';

  @override
  String get commonFollowed => 'Followed';

  @override
  String get commonFollowing => 'Following';

  @override
  String get commonFriend => 'Friend';

  @override
  String commonMiniID(Object p1) {
    return 'Mini ID $p1';
  }

  @override
  String commonMiniID2(Object uin) {
    return 'Mini ID $uin';
  }

  @override
  String get commonNotSignedIn => 'Not signed in';

  @override
  String commonOperationFailed(Object e) {
    return 'Operation failed: $e';
  }

  @override
  String get commonPin => 'Pin';

  @override
  String get commonPinned => 'Pinned';

  @override
  String get commonRefresh => 'Refresh';

  @override
  String get commonRetry => 'Retry';

  @override
  String get commonUnpin => 'Unpin';

  @override
  String get commonUnpinned => 'Unpinned';

  @override
  String get dataCanceled => 'Canceled';

  @override
  String get dataChatHistory => 'Chat history';

  @override
  String dataChatsFriends(Object p1, Object p2) {
    return '$p1 chats, $p2 friends';
  }

  @override
  String get dataChooseChatHistoryBackup => 'Choose a chat history backup file';

  @override
  String get dataCounting => 'Counting…';

  @override
  String get dataExistingRecordsSkippedAutomatically =>
      'Existing records are skipped automatically; local data is never deleted or overwritten. Continue?';

  @override
  String get dataExportChatHistory => 'Export chat history';

  @override
  String get dataExportCurrentAccountsMessages =>
      'Export the current account\'s messages, chats and friends to a JSON file';

  @override
  String get dataImport => 'Import';

  @override
  String get dataImportChatHistory => 'Import chat history';

  @override
  String dataImportCompleteMessages(Object p1) {
    return 'Import complete: $p1 messages,';
  }

  @override
  String dataImportFailed(Object e) {
    return 'Import failed: $e';
  }

  @override
  String get dataLocalData => 'Local data';

  @override
  String get dataMergeImportJSONBackup =>
      'Merge-import from a JSON backup (existing records are skipped automatically)';

  @override
  String dataMessagesChats(Object _messageCount, Object _sessionCount) {
    return '$_messageCount messages · $_sessionCount chats';
  }

  @override
  String get dataMessagesChatsFriendsBackup =>
      'Messages, chats and friends from the backup will be merged into the current account.';

  @override
  String get dataSignBeforeExporting => 'Sign in before exporting';

  @override
  String dynamicsAuthorMoments(Object p1) {
    return '$p1\'s moments';
  }

  @override
  String dynamicsCardAuthor(Object p1) {
    return 'Author $p1';
  }

  @override
  String get dynamicsCardEnded => 'Ended';

  @override
  String get dynamicsCardFailedForward => 'Failed to forward';

  @override
  String get dynamicsCardForwardedFriend => 'Forwarded to friend';

  @override
  String get dynamicsCardGiveaway => 'Giveaway';

  @override
  String get dynamicsCardGiveawayLoading => 'Giveaway (loading)';

  @override
  String get dynamicsCardNoFriendsShare => 'No friends to share with';

  @override
  String get dynamicsCardOngoing => 'Ongoing';

  @override
  String dynamicsCardOpenWorkMap(Object p1) {
    return 'Open work/map: $p1';
  }

  @override
  String get dynamicsCardOperationFailedTryAgain =>
      'Operation failed, please try again later';

  @override
  String dynamicsCardParticipants(Object p1) {
    return '$p1 participants';
  }

  @override
  String dynamicsCardPrizeX(Object p1) {
    return 'Prize x$p1';
  }

  @override
  String get dynamicsCardViewFullText => 'View full text';

  @override
  String get dynamicsCardVoteLoading => 'Vote (loading)';

  @override
  String dynamicsCardWinners(Object p1) {
    return '$p1 winners';
  }

  @override
  String dynamicsCategory(Object p1) {
    return 'Category $p1';
  }

  @override
  String get dynamicsDetailChangeVisibility => 'Change visibility';

  @override
  String dynamicsDetailChanged(Object p1) {
    return 'Changed to \"$p1\"';
  }

  @override
  String get dynamicsDetailCollapseReplies => 'Collapse replies';

  @override
  String get dynamicsDetailCommentActions => 'Comment actions';

  @override
  String get dynamicsDetailCommentPosted => 'Comment posted';

  @override
  String dynamicsDetailComments(Object p1) {
    return '$p1 comments';
  }

  @override
  String dynamicsDetailDAgo(Object p1) {
    return '$p1 d ago';
  }

  @override
  String get dynamicsDetailDefault => 'Default';

  @override
  String get dynamicsDetailDeleteComment => 'Delete comment';

  @override
  String get dynamicsDetailDeleteComment2 => 'Delete this comment?';

  @override
  String get dynamicsDetailDeleteFailed => 'Delete failed';

  @override
  String dynamicsDetailDeleteFailed2(Object e) {
    return 'Delete failed: $e';
  }

  @override
  String get dynamicsDetailDeleteMoment => 'Delete moment';

  @override
  String get dynamicsDetailDeleteReply => 'Delete reply';

  @override
  String get dynamicsDetailDeleteReply2 => 'Delete this reply?';

  @override
  String get dynamicsDetailDeleted => 'Deleted';

  @override
  String get dynamicsDetailFailedLoadVoteInfo => 'Failed to load vote info';

  @override
  String get dynamicsDetailFailedPublish => 'Failed to publish';

  @override
  String dynamicsDetailFailedPublish2(Object e) {
    return 'Failed to publish: $e';
  }

  @override
  String dynamicsDetailFailedShare(Object e) {
    return 'Failed to share: $e';
  }

  @override
  String get dynamicsDetailGiveawayDetailsOngoing =>
      'Giveaway details (ongoing)';

  @override
  String dynamicsDetailHrAgo(Object p1) {
    return '$p1 hr ago';
  }

  @override
  String get dynamicsDetailJustNow => 'Just now';

  @override
  String get dynamicsDetailLatest => 'Latest';

  @override
  String get dynamicsDetailLike => 'Like';

  @override
  String get dynamicsDetailLoadMoreComments => 'Load more comments';

  @override
  String dynamicsDetailMinAgo(Object p1) {
    return '$p1 min ago';
  }

  @override
  String dynamicsDetailMoAgo(Object p1) {
    return '$p1 mo ago';
  }

  @override
  String get dynamicsDetailMomentDeleted => 'Moment deleted';

  @override
  String get dynamicsDetailMomentDetails => 'Moment details';

  @override
  String get dynamicsDetailMomentManagement => 'Moment management';

  @override
  String get dynamicsDetailMultipleChoiceSubmitAfter =>
      'Multiple choice, submit after selecting';

  @override
  String get dynamicsDetailNoCommentsYet => 'No comments yet';

  @override
  String get dynamicsDetailNoFriendsShare => 'No friends to share with';

  @override
  String get dynamicsDetailNoRepliesYet => 'No replies yet';

  @override
  String get dynamicsDetailOperationFailed => 'Operation failed';

  @override
  String dynamicsDetailOption(Object p1) {
    return 'Option $p1';
  }

  @override
  String get dynamicsDetailPublish => 'Publish';

  @override
  String dynamicsDetailReplies(Object p1) {
    return '$p1 replies';
  }

  @override
  String get dynamicsDetailReply => 'Reply';

  @override
  String dynamicsDetailReply2(Object name) {
    return 'Reply to $name';
  }

  @override
  String dynamicsDetailReply3(Object name) {
    return 'Reply to @$name';
  }

  @override
  String get dynamicsDetailReplyActions => 'Reply actions';

  @override
  String get dynamicsDetailReplyPosted => 'Reply posted';

  @override
  String get dynamicsDetailShareChat => 'Share to chat';

  @override
  String get dynamicsDetailShareMoment => 'Share moment to…';

  @override
  String dynamicsDetailShared(Object picked) {
    return 'Shared with $picked';
  }

  @override
  String get dynamicsDetailSignVote => 'Sign in to vote';

  @override
  String get dynamicsDetailSingleChoiceTapSubmit =>
      'Single choice, tap to submit';

  @override
  String get dynamicsDetailSubmitting => 'Submitting…';

  @override
  String get dynamicsDetailTapWriteComment => 'Tap to write a comment';

  @override
  String get dynamicsDetailThisCannotUndoneDelete =>
      'This cannot be undone. Delete this moment?';

  @override
  String get dynamicsDetailUnlike => 'Unlike';

  @override
  String get dynamicsDetailVote => 'Vote';

  @override
  String get dynamicsDetailVoteFailed => 'Vote failed';

  @override
  String dynamicsDetailVoteFailed2(Object e) {
    return 'Vote failed: $e';
  }

  @override
  String dynamicsDetailVotes(Object p1) {
    return '$p1 votes';
  }

  @override
  String get dynamicsDetailWriteComment => 'Write a comment';

  @override
  String dynamicsDetailYrAgo(Object p1) {
    return '$p1 yr ago';
  }

  @override
  String get dynamicsLocal => 'Local';

  @override
  String get dynamicsMine => 'Mine';

  @override
  String get dynamicsMomentNotifications => 'Moment notifications';

  @override
  String get dynamicsNoMomentsYetPull => 'No moments yet, pull to refresh';

  @override
  String get dynamicsOfficial => 'Official';

  @override
  String get dynamicsPopular => 'Popular';

  @override
  String get dynamicsPostMoment => 'Post a moment';

  @override
  String get dynamicsTopicNoMomentsTopicYet =>
      'No moments in this topic yet, pull to refresh';

  @override
  String get dynamicsTopicNoTopicsYetPull => 'No topics yet, pull to refresh';

  @override
  String dynamicsTopicTopic(Object p1) {
    return 'Topic $p1';
  }

  @override
  String get dynamicsTopicTopics => 'Topics';

  @override
  String get emojiAddEmojiPack => 'Add emoji pack';

  @override
  String get emojiBasics => 'Basics';

  @override
  String get emojiEmojiPackManagementIsnt =>
      'Emoji pack management isn\'t available yet';

  @override
  String get emojiEmojiPackStoreIsnt => 'Emoji pack store isn\'t available yet';

  @override
  String get emojiEmojiSettings => 'Emoji settings';

  @override
  String get emojiInteractive => 'Interactive';

  @override
  String get emojiMember => 'Member';

  @override
  String get emojiNoEmojiPacksAvailable => 'No emoji packs available';

  @override
  String get familyAnnouncement => 'Announcement';

  @override
  String get familyApprove => 'Approve';

  @override
  String get familyApproved => 'Approved';

  @override
  String familyFailedLeave(Object e) {
    return 'Failed to leave: $e';
  }

  @override
  String get familyFamilyJoinRequests => 'Family join requests';

  @override
  String get familyFamilyMessages => 'Family messages';

  @override
  String familyJoinedFamilies(Object p1) {
    return 'Joined $p1 families';
  }

  @override
  String get familyLeader => 'Leader';

  @override
  String familyLeave(Object p1) {
    return 'Leave \"$p1\"?';
  }

  @override
  String get familyLeaveFamily => 'Leave family';

  @override
  String get familyMembers => 'Members';

  @override
  String get familyMembers2 => 'Members';

  @override
  String get familyMessageFamily => 'Message the family…';

  @override
  String get familyNoFamilyJoinRequests => 'No family join requests';

  @override
  String get familyNoFamilyMessages => 'No family messages';

  @override
  String familyRefreshHint(Object _error) {
    return '$_error\n\nTap the top-right corner to refresh';
  }

  @override
  String get familyRejected => 'Rejected';

  @override
  String get familyTransferLeadership => 'Transfer leadership';

  @override
  String get familyYouHaventJoinedAny => 'You haven\'t joined any family yet';

  @override
  String get favoritesContentGone => '(Content no longer on this device)';

  @override
  String get friendFilterFilter => 'Filter';

  @override
  String get friendFilterFriendsInvite => 'Friends to invite';

  @override
  String get friendFilterGeneral => 'General';

  @override
  String get friendFilterNewTag => 'New tag';

  @override
  String get friendFilterOnlineFriends => 'Online friends';

  @override
  String get friendFilterReset => 'Reset';

  @override
  String get friendFilterTagNameMax5 => 'Tag name (max 5 characters)';

  @override
  String get friendFilterTags => 'Tags';

  @override
  String get friendFilterYouHaventCreatedAny =>
      'You haven\'t created any tags yet';

  @override
  String get friendRequestAccept => 'Accept';

  @override
  String get friendRequestAddFriend => 'Add friend';

  @override
  String get friendRequestEnterTheirMiniID => 'Enter their Mini ID';

  @override
  String get friendRequestEnterValidMiniID => 'Enter a valid Mini ID';

  @override
  String friendRequestFailedApprove(Object e) {
    return 'Failed to approve: $e';
  }

  @override
  String friendRequestFailedReject(Object e) {
    return 'Failed to reject: $e';
  }

  @override
  String friendRequestFailedSendRequest(Object e) {
    return 'Failed to send request: $e';
  }

  @override
  String get friendRequestFriendAdded => 'Friend added';

  @override
  String friendRequestFriendRequestSent(Object uin) {
    return 'Friend request sent to $uin';
  }

  @override
  String get friendRequestFriendRequests => 'Friend requests';

  @override
  String friendRequestGroup(Object p1) {
    return 'Group $p1';
  }

  @override
  String get friendRequestGroupInvites => 'Group invites';

  @override
  String friendRequestInvitedMembers(Object p1, Object p2) {
    return 'Invited by $p1 · $p2 members';
  }

  @override
  String get friendRequestNoGroupInvites => 'No group invites';

  @override
  String get friendRequestNoPendingFriendRequests =>
      'No pending friend requests';

  @override
  String friendRequestOperationFailedRet(Object ret) {
    return 'Operation failed: ret=$ret';
  }

  @override
  String get friendRequestReject => 'Reject';

  @override
  String get friendRequestReject2 => 'Reject all';

  @override
  String get friendRequestRejectedFriendRequests =>
      'Rejected all friend requests';

  @override
  String get friendRequestRequestList => 'Request list';

  @override
  String get friendRequestSendRequest => 'Send request';

  @override
  String get friendTagAfterDeletionTagRemoved =>
      'After deletion, this tag will be removed from all friends.';

  @override
  String get friendTagClearTagsTheseFriends => 'Clear tags for these friends';

  @override
  String friendTagCreated(Object label) {
    return 'Created \"$label\"';
  }

  @override
  String get friendTagDeleteTag => 'Delete tag';

  @override
  String friendTagDeleteTag2(Object p1) {
    return 'Delete tag \"$p1\"';
  }

  @override
  String get friendTagDone => 'Done';

  @override
  String friendTagFriends(Object p1) {
    return '$p1 friends';
  }

  @override
  String friendTagServerDidntAcceptResult(Object code) {
    return 'Server didn\'t accept it (result=$code)';
  }

  @override
  String get friendTagTagDeleted => 'Tag deleted';

  @override
  String friendTagTagFriends(Object p1) {
    return 'Tag $p1 friends';
  }

  @override
  String get friendTagTagsApplied => 'Tags applied';

  @override
  String get friendTagTagsRemoved => 'Tags removed';

  @override
  String get friendsAddMiniID => 'Add by Mini ID';

  @override
  String get friendsAddTags => 'Add tags';

  @override
  String get friendsBlocklist => 'Blocklist';

  @override
  String get friendsBulkManagement => 'Bulk management';

  @override
  String get friendsClearTags => 'Clear tags';

  @override
  String get friendsCloseSearch => 'Close search';

  @override
  String get friendsDefaultFriendOrder => 'Default friend order';

  @override
  String get friendsExitBulkManagement => 'Exit bulk management';

  @override
  String get friendsFollowingFollowers => 'Following and followers';

  @override
  String get friendsGroupLeaveHistory => 'Group leave history';

  @override
  String get friendsGroups => 'Groups';

  @override
  String get friendsHighestRapportFirst => 'Highest rapport first';

  @override
  String friendsMiniID(Object gameText, Object p1) {
    return '$gameText · Mini ID $p1';
  }

  @override
  String get friendsMore => 'More';

  @override
  String get friendsMostRecentLoginFirst => 'Most recent login first';

  @override
  String get friendsMyFriends => 'My friends';

  @override
  String get friendsMyQRCode => 'My QR code';

  @override
  String get friendsNoFriendsMatchFilters => 'No friends match the filters';

  @override
  String get friendsNoFriendsYetPull =>
      'No friends yet\nPull to refresh or tap the top-right corner to add';

  @override
  String get friendsNoGroupChats => 'No group chats';

  @override
  String get friendsOffline => 'Offline';

  @override
  String get friendsOldestLoginFirst => 'Oldest login first';

  @override
  String get friendsOnline => 'Online';

  @override
  String friendsOnlineFriends(Object online, Object total) {
    return 'Online friends $online/$total';
  }

  @override
  String get friendsOnlineNotifications => 'Online notifications';

  @override
  String friendsOnlineNotificationsSetPeople(Object p1) {
    return 'Online notifications set ($p1 people)';
  }

  @override
  String get friendsPeopleNearby => 'People nearby';

  @override
  String get friendsSearch => 'Search';

  @override
  String friendsSearch2(Object _search) {
    return 'Search: $_search';
  }

  @override
  String get friendsSearchFriendNicknameMini =>
      'Search friend nickname / Mini ID…';

  @override
  String friendsSelected(Object count) {
    return '$count selected';
  }

  @override
  String friendsSort(Object p1) {
    return 'Sort by: $p1';
  }

  @override
  String get friendsSort2 => 'Sort by';

  @override
  String get friendsTagsCleared => 'Tags cleared';

  @override
  String get friendsTapOpenGroupChat => 'Tap to open the group chat';

  @override
  String get friendsViewProfile => 'View profile';

  @override
  String giftBuyIntoInventoryFirst(Object p1, Object p2) {
    return 'Buy into inventory first, costs $p1 $p2';
  }

  @override
  String get giftBuySend => 'Buy and send';

  @override
  String giftBuyThenSend(Object _num) {
    return 'Buy $_num then send';
  }

  @override
  String get giftCouldntLoadGiftConfig =>
      'Couldn\'t load gift config (or no gifts available)';

  @override
  String giftDailyRapportCap(Object p1) {
    return 'Daily rapport cap $p1';
  }

  @override
  String giftDeductsInventoryFreeInventory(Object p1) {
    return 'Deducts inventory, free; inventory x$p1';
  }

  @override
  String giftFailedSendGift(Object e) {
    return 'Failed to send gift: $e';
  }

  @override
  String get giftFree => 'Free';

  @override
  String get giftGiftSent => 'Gift sent';

  @override
  String giftInventoryX(Object owned) {
    return 'Inventory x$owned';
  }

  @override
  String get giftQuantity => 'Quantity';

  @override
  String giftRapport(Object p1) {
    return 'Rapport +$p1';
  }

  @override
  String giftRapport2(Object p1) {
    return 'Rapport +$p1';
  }

  @override
  String get giftSendAfterWatchingAd => 'Send after watching the ad';

  @override
  String giftSendFree(Object _num) {
    return 'Send $_num free';
  }

  @override
  String get giftSendFree2 => 'Send for free';

  @override
  String giftSendGift(Object _displayName) {
    return 'Send a gift to $_displayName';
  }

  @override
  String get giftSendGiftInventory => 'Send from gift inventory';

  @override
  String giftSendInventoryFree(Object _num) {
    return 'Send $_num from inventory (free)';
  }

  @override
  String giftSendInventoryInventoryFail(Object _num, Object p1) {
    return 'Send $_num from inventory (only $p1 in inventory; this will fail)';
  }

  @override
  String get giftUseTodaysFreeSend => 'Use today\'s free send allowance';

  @override
  String get giftWatchAd => 'Watch ad';

  @override
  String giftWatchAdSend(Object _num) {
    return 'Watch an ad to send $_num';
  }

  @override
  String get giftWatchAdSend2 => 'Watch ad and send';

  @override
  String get groupDetailAllRejected => 'All rejected';

  @override
  String get groupDetailBlockMembersMessages => 'Block this member\'s messages';

  @override
  String get groupDetailChooseFriendsInvite => 'Choose friends to invite';

  @override
  String get groupDetailChooseNewGroupOwner => 'Choose a new group owner';

  @override
  String get groupDetailClear => 'Clear';

  @override
  String get groupDetailDisbandGroup => 'Disband group';

  @override
  String get groupDetailEditGroupName => 'Edit group name';

  @override
  String groupDetailFailedClear(Object e) {
    return 'Failed to clear: $e';
  }

  @override
  String groupDetailFailedDisband(Object e) {
    return 'Failed to disband: $e';
  }

  @override
  String groupDetailFailedInvite(Object e) {
    return 'Failed to invite: $e';
  }

  @override
  String groupDetailFailedPin(Object e) {
    return 'Failed to pin: $e';
  }

  @override
  String groupDetailFailedTransfer(Object e) {
    return 'Failed to transfer: $e';
  }

  @override
  String groupDetailFailedUpdate(Object e) {
    return 'Failed to update: $e';
  }

  @override
  String groupDetailGroup(Object gid) {
    return 'Group $gid';
  }

  @override
  String groupDetailGroup2(Object p1) {
    return 'Group $p1';
  }

  @override
  String get groupDetailGroupDataCannotRecovered =>
      'Group data cannot be recovered after disbanding. Disband anyway?';

  @override
  String get groupDetailGroupDisbanded => 'Group disbanded';

  @override
  String get groupDetailGroupID => 'Group ID';

  @override
  String get groupDetailGroupName => 'Group name';

  @override
  String get groupDetailGroupNameUpdated => 'Group name updated';

  @override
  String get groupDetailGroupNotificationsMuted => 'Group notifications muted';

  @override
  String get groupDetailGroupNotificationsUnmuted =>
      'Group notifications unmuted';

  @override
  String get groupDetailGroupOwner => 'Group owner';

  @override
  String get groupDetailGroupPinned => 'Group pinned';

  @override
  String get groupDetailInvitationSent => 'Invitation sent';

  @override
  String get groupDetailInvite => 'Invite';

  @override
  String get groupDetailInviteFriendsGroup => 'Invite friends to the group';

  @override
  String get groupDetailLeaveGroup => 'Leave group';

  @override
  String get groupDetailLeaveGroup2 => 'Leave this group?';

  @override
  String get groupDetailLeftGroup => 'Left the group';

  @override
  String get groupDetailMemberRemoved => 'Member removed';

  @override
  String get groupDetailMembersMessagesBlocked => 'Member\'s messages blocked';

  @override
  String get groupDetailMuteGroupNotifications => 'Mute group notifications';

  @override
  String get groupDetailMuteMember => 'Mute this member';

  @override
  String get groupDetailMuted => 'Muted';

  @override
  String groupDetailNameWithMe(Object name) {
    return '$name (me)';
  }

  @override
  String get groupDetailNoFriendsInvite => 'No friends to invite';

  @override
  String get groupDetailNoGroupLeaveHistory => 'No group leave history';

  @override
  String get groupDetailNoMemberInfoYet =>
      'No member info yet (may not have loaded)';

  @override
  String get groupDetailNoMembersTransfer => 'No members to transfer to';

  @override
  String get groupDetailPinGroup => 'Pin group';

  @override
  String get groupDetailRecordsCleared => 'Records cleared';

  @override
  String get groupDetailReject => 'Reject all';

  @override
  String get groupDetailRejectJoinRequests => 'Reject all join requests';

  @override
  String get groupDetailRejectPendingJoinRequests =>
      'Reject all pending join requests for this group?';

  @override
  String get groupDetailRemoveGroup => 'Remove from group';

  @override
  String groupDetailRemoveGroup2(Object p1) {
    return 'Remove $p1 from this group?';
  }

  @override
  String get groupDetailRemoveGroupMember => 'Remove group member';

  @override
  String get groupDetailReportMember => 'Report this member';

  @override
  String get groupDetailReportSubmitted => 'Report submitted';

  @override
  String get groupDetailSave => 'Save';

  @override
  String groupDetailSelected(Object p1) {
    return '$p1 selected';
  }

  @override
  String get groupDetailTransferGroupOwnership => 'Transfer group ownership';

  @override
  String groupDetailTransferGroupOwnership2(Object p1) {
    return 'Transfer group ownership to $p1?';
  }

  @override
  String get groupDetailTransferred => 'Transferred';

  @override
  String get groupDetailUnblockMember => 'Unblock this member';

  @override
  String get groupDetailUnblocked => 'Unblocked';

  @override
  String get groupDetailUnmuteGroup => 'Unmute group';

  @override
  String get groupDetailUnmuteMember => 'Unmute this member';

  @override
  String get groupDetailUnmuted => 'Unmuted';

  @override
  String get groupDetailUnpinGroup => 'Unpin group';

  @override
  String get groupDetailYouLeftGroup => 'You left the group';

  @override
  String get groupDetailYouWereRemovedGroup =>
      'You were removed from the group';

  @override
  String get homeLayoutUnknownModule => 'Unknown module';

  @override
  String get lockEnterAppLockPassword => 'Enter the app lock password';

  @override
  String get lockWrongPassword => 'Wrong password';

  @override
  String get loginAddAccount => 'Add account';

  @override
  String get loginBackAccountList => 'Back to account list';

  @override
  String get loginChooseAccount => 'Choose account';

  @override
  String get loginEnterPassword => 'Enter your password';

  @override
  String loginMiniID(Object p1) {
    return 'Mini ID $p1';
  }

  @override
  String get loginMiniWorldExternalChat =>
      'Mini World external chat · choose an account to sign in';

  @override
  String get loginNoSavedAccountsYet => 'No saved accounts yet';

  @override
  String get loginPassword => 'Password';

  @override
  String get loginRemove => 'Remove';

  @override
  String get loginRemoveAccount => 'Remove account';

  @override
  String get loginSign => 'Sign in';

  @override
  String get loginSignAdd => 'Sign in and add';

  @override
  String get loginSignAutomaticallyNextTime =>
      'Sign in automatically next time';

  @override
  String get loginSigning => 'Signing in…';

  @override
  String get loginUinMiniID => 'Uin / Mini ID';

  @override
  String get mailAll => 'All';

  @override
  String get mailAttachments => 'Attachments';

  @override
  String get mailClaimAttachments => 'Claim attachments';

  @override
  String get mailClaimed => 'Claimed';

  @override
  String mailDAgo(Object p1) {
    return '$p1 d ago';
  }

  @override
  String get mailDeleteRead => 'Delete read';

  @override
  String get mailDetails => 'Details';

  @override
  String get mailFailedFollow => 'Failed to follow';

  @override
  String get mailFailedMarkRead => 'Failed to mark as read';

  @override
  String get mailFilterType => 'Filter by type';

  @override
  String mailFrom(Object p1) {
    return 'From $p1';
  }

  @override
  String get mailFromMiniWorldOfficial => 'From Mini World official';

  @override
  String get mailGo => 'Go';

  @override
  String mailHrAgo(Object p1) {
    return '$p1 hr ago';
  }

  @override
  String mailItem(Object p1) {
    return 'Item $p1';
  }

  @override
  String get mailLink => 'Link';

  @override
  String get mailMarkRead => 'Mark all read';

  @override
  String get mailMessageCenter => 'Message center';

  @override
  String get mailMessageDetails => 'Message details';

  @override
  String mailMinAgo(Object p1) {
    return '$p1 min ago';
  }

  @override
  String get mailNoContent => '(No content)';

  @override
  String get mailNoMessages => 'No messages';

  @override
  String get mailThisLinkTypeIsnt => 'This link type isn\'t supported yet';

  @override
  String get mailThisMomentDoesntExist =>
      'This moment doesn\'t exist or was deleted';

  @override
  String get mailUnclaimed => 'Unclaimed';

  @override
  String get mailUntitled => '(Untitled)';

  @override
  String get nearbyDistanceUnknown => 'Distance unknown';

  @override
  String get nearbyEnterValidLatitudeLongitude =>
      'Enter valid latitude and longitude first';

  @override
  String nearbyFailedSave(Object e) {
    return 'Failed to save: $e';
  }

  @override
  String nearbyKilometers(Object p1) {
    return '$p1 km';
  }

  @override
  String nearbyKilometersRounded(Object p1) {
    return '$p1 km';
  }

  @override
  String get nearbyLatitudeExample => 'e.g. 39.9042';

  @override
  String get nearbyLatitudeLabel => 'Latitude';

  @override
  String get nearbyLetPeopleNearbyAdd => 'Let people nearby add me';

  @override
  String get nearbyLongitudeExample => 'e.g. 116.4074';

  @override
  String get nearbyLongitudeLabel => 'Longitude';

  @override
  String nearbyMeters(Object p1) {
    return '$p1 m';
  }

  @override
  String nearbyMiniID(Object p1, Object p2) {
    return 'Mini ID $p1 · $p2';
  }

  @override
  String get nearbyNoOneFoundNearby => 'No one found nearby';

  @override
  String nearbyPeopleFirstPage(Object p1) {
    return '$p1 people (first page only)';
  }

  @override
  String nearbyQueryFailed(Object _error) {
    return 'Query failed: $_error';
  }

  @override
  String get nearbyReading => 'Reading…';

  @override
  String get nearbyReportLocationFindPeople =>
      'Report location and find people nearby';

  @override
  String get nearbyThisExternalClientSystem =>
      'This external client has no system location access. Enter latitude and longitude manually, then search.';

  @override
  String get nearbyWhenEnabledPeopleNearby =>
      'When enabled, people nearby can find and add you';

  @override
  String partnerAlias(Object p1) {
    return 'Alias #$p1';
  }

  @override
  String partnerBestPartnerSlotsLeft(Object remaining) {
    return 'Best partner slots left x $remaining';
  }

  @override
  String partnerDaysRelation(Object p1) {
    return 'Days in relation: $p1';
  }

  @override
  String get partnerNoBestPartnersYet => 'No best partners yet';

  @override
  String get partnerPartnerSlots => 'Partner slots';

  @override
  String partnerRapport(Object p1) {
    return 'Rapport $p1';
  }

  @override
  String partnerRapport2(Object next, Object p1) {
    return 'Rapport $p1/$next';
  }

  @override
  String partnerRapport3(Object p1) {
    return 'Rapport · $p1';
  }

  @override
  String partnerRapport4(Object next, Object p1, Object p2) {
    return 'Rapport · $p1 ($p2/$next)';
  }

  @override
  String partnersAfterDaysWithoutInteracting(
    Object kPartnerDecayPerDay,
    Object kPartnerStaleDays,
  ) {
    return 'After $kPartnerStaleDays days without interacting, rapport drops $kPartnerDecayPerDay per day';
  }

  @override
  String get partnersFailedLoadRecentPlaymates =>
      'Failed to load recent playmates';

  @override
  String get partnersFindPeopleYouPlayed =>
      'Find people you played with even after leaving the room';

  @override
  String get partnersMyPartners => 'My partners';

  @override
  String get partnersNoPartnersYet => 'No partners yet';

  @override
  String get partnersNoPlaymatesYet => 'No playmates yet';

  @override
  String get partnersPartner => 'Partner';

  @override
  String get partnersPeopleYouPlayedAppear =>
      'People you played with will appear here after joining a room';

  @override
  String partnersRapport(Object tacit) {
    return 'Rapport $tacit';
  }

  @override
  String partnersRapportDropWithoutInteraction(Object floor, Object tacit) {
    return 'Rapport $tacit → will drop to $floor without interaction';
  }

  @override
  String partnersRapportNextLevel(Object next, Object tacit) {
    return 'Rapport $tacit / next level $next';
  }

  @override
  String get partnersRapportRelationLevelServer =>
      'Rapport and relation level (server data)';

  @override
  String get partnersReach100RapportFriend =>
      'Reach 100 rapport with a friend in-game to become partners';

  @override
  String get partnersRecentPlaymates => 'Recent playmates';

  @override
  String get partnersRecentlyPlayed => 'Recently played with';

  @override
  String get partnersRefreshRecentPlaymates => 'Refresh recent playmates';

  @override
  String get partnersTimeInteract => 'Time to interact';

  @override
  String get playerInfoAddFriend => 'Add friend';

  @override
  String playerInfoAdventurer(Object adv) {
    return 'Adventurer: $adv';
  }

  @override
  String get playerInfoFriendRequestSent => 'Friend request sent';

  @override
  String get playerInfoMyProfile => 'My profile';

  @override
  String playerInfoRapport(Object tacit) {
    return 'Rapport: $tacit';
  }

  @override
  String get playerInfoRequestFailedTryAgain =>
      'Request failed, please try again later';

  @override
  String get playerInfoSend => 'Send';

  @override
  String get profileAlreadyBlocked => 'Already blocked';

  @override
  String profileAndMaps(Object p1) {
    return 'and $p1 maps';
  }

  @override
  String get profileArtwork => 'Artwork';

  @override
  String get profileAvatarFrame => 'Avatar frame';

  @override
  String get profileAvatarFrameUpdated => 'Avatar frame updated';

  @override
  String get profileBlock => 'Block';

  @override
  String get profileCharm => 'Charm';

  @override
  String get profileCouldntLoadProfileLayout => 'Couldn\'t load profile layout';

  @override
  String get profileCreditScore => 'Credit score';

  @override
  String get profileEdit => 'Edit';

  @override
  String get profileEditAvatar => 'Edit avatar';

  @override
  String get profileEditLayout => 'Edit layout';

  @override
  String profileFamily(Object familyName) {
    return 'Family: $familyName';
  }

  @override
  String get profileFavoritesCreated => 'Favorites created';

  @override
  String get profileFollowers => 'Followers';

  @override
  String get profileFriendBio => 'Friend bio';

  @override
  String profileIPRegion(Object p1) {
    return 'IP region: $p1';
  }

  @override
  String get profileLayoutSaved => 'Layout saved';

  @override
  String get profileLightChaseProject => 'Light Chase Project';

  @override
  String get profileMedals => 'Medals';

  @override
  String get profileMedalsEarned => 'Medals earned';

  @override
  String get profileMiniIDCopied => 'Mini ID copied';

  @override
  String get profileMiniTraces => 'Mini Traces';

  @override
  String profileMomentsPublished(Object postingCount) {
    return '$postingCount moments published';
  }

  @override
  String get profileMyFavorites => 'My favorites';

  @override
  String get profileNoFriendBioSet => 'No friend bio set yet';

  @override
  String get profileNoOwnedSkinsArtwork =>
      'No owned skins or artwork fetched yet';

  @override
  String get profileNoPublishedMapWorks => 'No published map works yet';

  @override
  String get profileNoTitleEquipped => 'No title equipped';

  @override
  String profileOwnAvatarFrames(Object p1) {
    return 'Own $p1 avatar frames';
  }

  @override
  String profileOwnStylesLocalIcons(Object skinModuleCount) {
    return 'Own $skinModuleCount styles (no local icons yet)';
  }

  @override
  String get profilePersonalInfo => 'Personal info';

  @override
  String get profilePersonalStyle => 'Personal style';

  @override
  String get profilePhotosShownProfile => 'Photos shown on profile';

  @override
  String get profilePopularity => 'Popularity';

  @override
  String get profileProfile => 'Profile';

  @override
  String get profilePublishWork => 'Publish work';

  @override
  String get profileRecentVisitors => 'Recent visitors';

  @override
  String get profileRemoveThemBlocklist => 'Remove them from your blocklist?';

  @override
  String get profileStylesCollected => 'Styles collected';

  @override
  String get profileThisExternalClientDoesnt =>
      'This external client doesn\'t display moment text';

  @override
  String get profileThisExternalClientHasnt =>
      'This external client hasn\'t fetched this data yet';

  @override
  String get profileTitle => 'Title';

  @override
  String get profileTotalCharmReceivedGifts =>
      'Total charm from received gifts';

  @override
  String get profileUnfollowed => 'Unfollowed';

  @override
  String get profileUnnamed => 'Unnamed';

  @override
  String get profileUse => 'Use';

  @override
  String get profileUseArtwork => 'Use this artwork';

  @override
  String get profileUseArtworkAvatar => 'Use this artwork as your avatar?';

  @override
  String get profileUseAvatar => 'Use this avatar';

  @override
  String get profileUseAvatarFrame => 'Use this avatar frame';

  @override
  String profileUseAvatarFrame2(Object id) {
    return 'Use avatar frame #$id?';
  }

  @override
  String get profileUseSkinAvatar => 'Use this skin as your avatar?';

  @override
  String get profileViewMoments => 'View my moments';

  @override
  String get profileYouWontSeeTheir =>
      'You won\'t see their moments or messages after blocking. Continue?';

  @override
  String get publishDynamicsAVoteNeedsTitle =>
      'A vote needs a title and at least 2 options';

  @override
  String get publishDynamicsAllowMultipleChoice => 'Allow multiple choice';

  @override
  String get publishDynamicsAttachVote => 'Attach a vote';

  @override
  String get publishDynamicsChooseFriends => 'Choose friends';

  @override
  String get publishDynamicsChooseImage => 'Choose image';

  @override
  String get publishDynamicsDeadline => 'Deadline';

  @override
  String get publishDynamicsDeadlineMustLeast30 =>
      'Deadline must be at least 30 minutes from now';

  @override
  String get publishDynamicsDeleteImage => 'Delete image';

  @override
  String get publishDynamicsEnterSomeContent => 'Enter some content';

  @override
  String publishDynamicsFailedChooseImage(Object e) {
    return 'Failed to choose image: $e';
  }

  @override
  String get publishDynamicsFailedCreateVote => 'Failed to create vote';

  @override
  String publishDynamicsFailedDeleteImage(Object e) {
    return 'Failed to delete image: $e';
  }

  @override
  String publishDynamicsFailedPublishRet(Object p1, Object p2) {
    return 'Failed to publish: ret=$p1 $p2';
  }

  @override
  String get publishDynamicsFriends => '@Friends';

  @override
  String get publishDynamicsFriendsVoteAfterYou =>
      'Friends can vote after you publish';

  @override
  String publishDynamicsImageUploadFailed(Object p1) {
    return 'Image upload failed: $p1';
  }

  @override
  String publishDynamicsImageUploadFailed2(Object e) {
    return 'Image upload failed: $e';
  }

  @override
  String publishDynamicsImages(Object _maxPics, Object p1) {
    return 'Images ($p1/$_maxPics)';
  }

  @override
  String get publishDynamicsNoFriends => 'No friends to @';

  @override
  String publishDynamicsOption(Object p1) {
    return 'Option $p1';
  }

  @override
  String get publishDynamicsPublished => 'Published';

  @override
  String get publishDynamicsSearchTopics => 'Search topics';

  @override
  String get publishDynamicsShareSomethingNew => 'Share something new…';

  @override
  String get publishDynamicsSomeImagesHaventFinished =>
      'Some images haven\'t finished uploading';

  @override
  String get publishDynamicsTopicOptional => 'Topic (optional)';

  @override
  String get publishDynamicsUploadingImagesWait =>
      'Uploading images, please wait';

  @override
  String get publishDynamicsVisibility => 'Visibility';

  @override
  String get publishDynamicsVoteTitle => 'Vote title';

  @override
  String publishDynamicsYouUploadMostImages(Object _maxPics) {
    return 'You can upload at most $_maxPics images';
  }

  @override
  String get qrAskThemEnterNumber =>
      'Ask them to enter this number under Friends → Add by Mini ID';

  @override
  String get qrCopyMiniID => 'Copy Mini ID';

  @override
  String get qrMyMiniID => 'My Mini ID';

  @override
  String relationFollowers(Object p1) {
    return 'Followers $p1';
  }

  @override
  String relationFollowing(Object p1) {
    return 'Following $p1';
  }

  @override
  String get relationNoFollowersYet => 'No followers yet';

  @override
  String get relationNotFollowingAnyoneYet => 'Not following anyone yet';

  @override
  String get requestErrorCopyURL => 'Copy URL';

  @override
  String get requestErrorFailedRequests => 'Failed requests';

  @override
  String get requestErrorNoFailureRecordsYet => 'No failure records yet';

  @override
  String get requestErrorNoUrl => '(No request URL)';

  @override
  String get requestErrorRequestURLCopied => 'Request URL copied';

  @override
  String requestErrorRequestsFailed(Object total) {
    return '$total requests failed';
  }

  @override
  String get sessionMenuCancelDoDisturb => 'Cancel do not disturb';

  @override
  String get sessionMenuCancelOnlineNotification =>
      'Cancel online notification';

  @override
  String get sessionMenuDeleteFriend => 'Delete friend';

  @override
  String sessionMenuDeleteFriend2(Object p1) {
    return 'Delete friend \"$p1\"?';
  }

  @override
  String get sessionMenuDoDisturb => 'Do not disturb';

  @override
  String get sessionMenuDoDisturb2 => 'Do not disturb on';

  @override
  String get sessionMenuDoDisturbOff => 'Do not disturb off';

  @override
  String get sessionMenuEnterNoteNameLeave =>
      'Enter a note name; leave blank to clear';

  @override
  String get sessionMenuFailedNudge => 'Failed to nudge';

  @override
  String get sessionMenuFriendDeleted => 'Friend deleted';

  @override
  String get sessionMenuNote => 'Note';

  @override
  String get sessionMenuNoteName => 'Note name';

  @override
  String get sessionMenuNoteSaved => 'Note saved';

  @override
  String get sessionMenuNudge => 'Nudge';

  @override
  String get sessionMenuNudged => 'Nudged';

  @override
  String get sessionMenuOnlineNotification => 'Online notification on';

  @override
  String get sessionMenuOnlineNotificationOff => 'Online notification off';

  @override
  String get sessionMenuRemoveConversation => 'Remove conversation';

  @override
  String get sessionsConversationRemoved => 'Conversation removed';

  @override
  String sessionsFriend(Object p1) {
    return 'Friend $p1';
  }

  @override
  String sessionsGroup(Object p1) {
    return 'Group $p1';
  }

  @override
  String get sessionsNoConversationsPeopleYou =>
      'No conversations\nPeople you chat with will appear here';

  @override
  String get sessionsNoMatchingConversations => 'No matching conversations';

  @override
  String get sessionsOnlyConversationsChattedDevice =>
      'Only conversations chatted on this device are kept';

  @override
  String get sessionsSearchConversationsNicknameMini =>
      'Search conversations (nickname or Mini ID)';

  @override
  String get sessionsSearchMiniIDNickname => 'Search by Mini ID or nickname';

  @override
  String get settingsAboutAbout => 'About';

  @override
  String settingsAboutAlreadyUpDate(Object kAppVersion) {
    return 'Already up to date ($kAppVersion)';
  }

  @override
  String get settingsAboutAppPrivateDirectoryAuto =>
      'App-private directory (auto-rotated)';

  @override
  String settingsAboutCheckFailedYouAlso(Object p1) {
    return 'Check failed: $p1\n\nYou can also check the Releases page directly:\n';
  }

  @override
  String get settingsAboutCheckLatestBuildGitHub =>
      'Check the latest build on GitHub';

  @override
  String get settingsAboutCheckUpdates => 'Check for updates';

  @override
  String get settingsAboutChecking => 'Checking…';

  @override
  String get settingsAboutClearLogs => 'Clear logs';

  @override
  String get settingsAboutDeleteRotatedLogFiles =>
      'Delete all rotated log files';

  @override
  String get settingsAboutExportDiagnostics => 'Export diagnostics';

  @override
  String settingsAboutFailedClear(Object e) {
    return 'Failed to clear: $e';
  }

  @override
  String settingsAboutFailedCollectDiagnostics(Object e) {
    return 'Failed to collect diagnostics: $e';
  }

  @override
  String get settingsAboutGotIt => 'Got it';

  @override
  String get settingsAboutLogFiles => 'Log files';

  @override
  String get settingsAboutLogsCleared => 'Logs cleared';

  @override
  String get settingsAboutMnChat => 'About MnChat';

  @override
  String settingsAboutNewVersionAvailableCurrent(
    Object kAppVersion,
    Object p1,
    Object p2,
  ) {
    return 'New version $p1 available (current $kAppVersion)\n\n$p2';
  }

  @override
  String get settingsAboutNewVersionFound => 'New version found';

  @override
  String get settingsAboutNoLogsYet => 'No logs yet';

  @override
  String get settingsAboutNone => '(None)';

  @override
  String get settingsAboutOpenSourceLicenses => 'Open-source licenses';

  @override
  String get settingsAboutOther => 'Other';

  @override
  String get settingsAboutRecentRequestFailures => '## Recent request failures';

  @override
  String get settingsAboutThirdPartyDependenciesLicenses =>
      'Third-party dependencies and licenses';

  @override
  String get settingsAboutVersion => 'Version';

  @override
  String get settingsAboutVersionPlatformTableCounts =>
      'Version / platform / table counts / log tail / recent request failures';

  @override
  String get settingsAccount => 'Account';

  @override
  String get settingsAccountAccountSecurity => 'Account and security';

  @override
  String get settingsAccountAppLock => 'App lock';

  @override
  String get settingsAccountAppLockDisabled => 'App lock disabled';

  @override
  String get settingsAccountAppLockEnabled => 'App lock enabled';

  @override
  String get settingsAccountAutoSign => 'Auto sign-in';

  @override
  String get settingsAccountAutoSignDisabled => 'Auto sign-in disabled';

  @override
  String get settingsAccountAutoSignEnabledCredentials =>
      'Auto sign-in enabled (credentials will be saved on next sign-in)';

  @override
  String get settingsAccountDigits48 => '4-8 digits';

  @override
  String get settingsAccountDigits68 => '6-8 digits';

  @override
  String get settingsAccountEnterAppLockPassword =>
      'Enter the app lock password';

  @override
  String get settingsAccountPasswordLength => 'Password must be 6-8 digits';

  @override
  String get settingsAccountPasswordsDontMatch => 'Passwords don\'t match';

  @override
  String get settingsAccountProfile => 'Profile';

  @override
  String get settingsAccountReEnterPassword => 'Re-enter password';

  @override
  String get settingsAccountRequirePasswordLaunchReturning =>
      'Require a password on launch / returning to foreground';

  @override
  String get settingsAccountSecurity => 'Security';

  @override
  String get settingsAccountSetAppLockPassword => 'Set app lock password';

  @override
  String get settingsAccountSetBioWantLike => 'Set my bio (Want / Like)';

  @override
  String get settingsAccountSignAutomaticallyNextLaunch =>
      'Sign in automatically next launch (sign in once first to save credentials)';

  @override
  String get settingsAccountSocialTags => 'Social tags';

  @override
  String get settingsAccountViewAvatarEditNickname =>
      'View avatar / edit nickname / avatar frame';

  @override
  String get settingsAppLock => 'App lock on';

  @override
  String get settingsDark => 'Dark';

  @override
  String get settingsFollowSystem => 'Follow system';

  @override
  String get settingsFriendRequestLimitsVisit =>
      'Friend request limits / visit traces / chat history / storage usage';

  @override
  String get settingsGeneralAppearance => 'Appearance';

  @override
  String get settingsGeneralAvatarFrameAnimation => 'Avatar frame animation';

  @override
  String get settingsGeneralCloseTray => 'Close to tray';

  @override
  String get settingsGeneralConversationOrder => 'Conversation order';

  @override
  String get settingsGeneralDesktop => 'Desktop';

  @override
  String get settingsGeneralGeneralAppearance => 'General and appearance';

  @override
  String get settingsGeneralLightDarkModeAccent =>
      'Light/dark mode / accent color / chat text size';

  @override
  String get settingsGeneralMinimizeSystemTrayInstead =>
      'Minimize to the system tray instead of quitting when closing the window';

  @override
  String get settingsGeneralMinimizeTrayWhenClosing =>
      'Minimize to tray when closing the window';

  @override
  String get settingsGeneralNoSystemTrayAvailable =>
      'No system tray is available on this desktop, so closing the window quits (automatically disabled)';

  @override
  String get settingsGeneralQuitWhenClosingWindow =>
      'Quit when closing the window';

  @override
  String get settingsGeneralSwitchBetweenOwnedChat =>
      'Switch between owned chat bubbles';

  @override
  String get settingsGeneralThemeDisplaySettings => 'Theme display settings';

  @override
  String get settingsGeneralWhenOffStaticAvatar =>
      'When off, only static avatar frames are shown to save power and data';

  @override
  String get settingsLight => 'Light';

  @override
  String get settingsNotificationAdd => 'Add';

  @override
  String get settingsNotificationAddPhrase => 'Add phrase';

  @override
  String get settingsNotificationAddQuickPhrase => 'Add quick phrase';

  @override
  String get settingsNotificationBackgroundConnectionDisabled =>
      'Background connection disabled';

  @override
  String get settingsNotificationBackgroundConnectionEnabled =>
      'Background connection enabled';

  @override
  String get settingsNotificationBackgroundNotificationsArentSupported =>
      'Background notifications aren\'t supported on this platform';

  @override
  String get settingsNotificationClearUnreadMarkerWhen =>
      'Clear the unread marker when a conversation is opened';

  @override
  String get settingsNotificationDoDisturbEnds => 'Do not disturb ends';

  @override
  String get settingsNotificationDoDisturbHours => 'Do not disturb hours';

  @override
  String get settingsNotificationDoDisturbHoursUpdated =>
      'Do not disturb hours updated';

  @override
  String get settingsNotificationDoDisturbStarts => 'Do not disturb starts';

  @override
  String get settingsNotificationEnterPhraseContent => 'Enter phrase content';

  @override
  String get settingsNotificationHideNotificationContent =>
      'Hide notification content';

  @override
  String get settingsNotificationInsertQuicklyWhenSending =>
      'Insert quickly when sending (matches the game\'s built-in SecretQuickMsg)';

  @override
  String get settingsNotificationKeepConnectionBackground =>
      'Keep connection in background';

  @override
  String get settingsNotificationLongPressConversationList =>
      'Long-press a conversation in the list to set';

  @override
  String get settingsNotificationMarkReadOpen => 'Mark as read on open';

  @override
  String get settingsNotificationMessages => 'Messages';

  @override
  String get settingsNotificationMessagesNotifications =>
      'Messages and notifications';

  @override
  String get settingsNotificationNewMessageNotifications =>
      'New message notifications';

  @override
  String get settingsNotificationNewMessageNotificationsDisabled =>
      'New message notifications disabled';

  @override
  String get settingsNotificationNewMessageNotificationsEnabled =>
      'New message notifications enabled';

  @override
  String get settingsNotificationNoPhrasesYet => 'No phrases yet';

  @override
  String get settingsNotificationNotificationSound => 'Notification sound';

  @override
  String get settingsNotificationNotificationVibration =>
      'Notification vibration';

  @override
  String get settingsNotificationNotifications => 'Notifications';

  @override
  String get settingsNotificationOnDesktopPressEnter =>
      'On desktop, press Enter to send and Shift+Enter for a new line';

  @override
  String get settingsNotificationOnlyAlertMeMentions =>
      'Only alert me for @mentions in groups';

  @override
  String get settingsNotificationPerConversationMutePin =>
      'Per-conversation mute / pin';

  @override
  String get settingsNotificationPhraseAlreadyExistsInvalid =>
      'Phrase already exists or is invalid';

  @override
  String get settingsNotificationQuickPhrases => 'Quick phrases';

  @override
  String get settingsNotificationSendEnter => 'Send with Enter';

  @override
  String get settingsNotificationShowNewMessageAlert =>
      'Show only a new-message alert on the lock screen / notification bar, without content';

  @override
  String get settingsNotificationShowSystemNotificationNew =>
      'Show a system notification for new messages when the app is in the background';

  @override
  String get settingsNotificationTheForegroundServiceKeeps =>
      'The foreground service keeps the connection alive so new messages arrive in the background';

  @override
  String get settingsNotificationVibrateWhenNewMessage =>
      'Vibrate when a new message arrives';

  @override
  String get settingsNotificationWhenGroupMessagesNotify =>
      'When on, group messages notify only when they mention me (text contains my @nickname); direct chats are unaffected';

  @override
  String get settingsNotificationWhenOffNotificationsArrive =>
      'When off, notifications arrive silently (they still appear)';

  @override
  String get settingsNotificationYouWontReceiveSystem =>
      'You won\'t receive system notifications while the app is in the background.';

  @override
  String settingsNotificationsDoDisturb(Object p1) {
    return 'Notifications on · Do not disturb $p1';
  }

  @override
  String get settingsNotificationsDoDisturb2 =>
      'Notifications on · No do not disturb';

  @override
  String get settingsNotificationsOff => 'Notifications off';

  @override
  String get settingsPreferences => 'Preferences';

  @override
  String get settingsPrivacyAllowOthersAddMe =>
      'Allow others to add me to groups';

  @override
  String get settingsPrivacyAutomaticallyJoinInvitedGroups =>
      'Automatically join invited groups';

  @override
  String get settingsPrivacyBlockFriendRequestsStrangers =>
      'Block friend requests from strangers';

  @override
  String get settingsPrivacyClearImageCache => 'Clear image cache';

  @override
  String get settingsPrivacyClearing => 'Clearing…';

  @override
  String get settingsPrivacyCounting => 'Counting…';

  @override
  String get settingsPrivacyData => 'Privacy and data';

  @override
  String get settingsPrivacyData2 => 'Data';

  @override
  String get settingsPrivacyDatabaseSizeRetentionClear =>
      'Database size / retention / clear by conversation / VACUUM';

  @override
  String get settingsPrivacyDeletesCachedAvatarsMoment =>
      'Deletes cached avatars and moment images; they\'ll be downloaded again when displayed. Chat history is unaffected.';

  @override
  String get settingsPrivacyDisabledStrangersAddMe =>
      'Disabled: strangers can add me';

  @override
  String get settingsPrivacyEnabledStrangersCantAdd =>
      'Enabled: strangers can\'t add me';

  @override
  String get settingsPrivacyExportImportChatData =>
      'Export / import chat data backup';

  @override
  String get settingsPrivacyImageCacheCleared => 'Image cache cleared';

  @override
  String get settingsPrivacyLeaveTraceWhenVisiting =>
      'Leave a trace when visiting profiles';

  @override
  String get settingsPrivacyPrivacy => 'Privacy';

  @override
  String get settingsPrivacyStorageManagement => 'Storage management';

  @override
  String settingsPrivacyUsingAvatarsMomentImages(Object p1) {
    return 'Using $p1 (avatars and moment images)';
  }

  @override
  String get settingsPrivacyWhenIJoinAutomatically =>
      'When on, I join automatically when invited';

  @override
  String get settingsPrivacyWhenOffInvitationsOthers =>
      'When off, invitations from others are declined';

  @override
  String get settingsPrivacyWhenOffViewingSomeones =>
      'When off, viewing someone\'s profile won\'t appear in their visitor list';

  @override
  String get settingsPrivacyWhenStrangersCantAdd =>
      'When on, strangers can\'t add me as a friend';

  @override
  String get settingsProfileSocialTagsAuto =>
      'Profile / social tags / auto sign-in';

  @override
  String get settingsSettings => 'Settings';

  @override
  String get settingsSignOut => 'Sign out';

  @override
  String get settingsSignOut2 => 'Sign out';

  @override
  String get settingsSignOutCurrentAccount =>
      'Sign out of the current account?';

  @override
  String settingsThemeTextSizeBubbles(Object p1) {
    return '$p1 · Theme / text size / bubbles / conversation order';
  }

  @override
  String settingsVCheckUpdatesOpen(Object kAppVersion) {
    return 'v$kAppVersion · Check for updates / open-source licenses / diagnostics export';
  }

  @override
  String get shellFriendsGroupChatsRoom =>
      'Friends / group chats · no room needed';

  @override
  String get shellMoments => 'Moments';

  @override
  String get shellSelectConversationStartChatting =>
      'Select a conversation to start chatting';

  @override
  String get signFailedSave => 'Failed to save';

  @override
  String signFailedSave2(Object e) {
    return 'Failed to save: $e';
  }

  @override
  String get signLike => 'Like…';

  @override
  String get signMyCard => 'My card';

  @override
  String get signNotSet => 'Not set';

  @override
  String get signNotSet2 => 'Not set';

  @override
  String get signSaved => 'Saved';

  @override
  String get signWant => 'Want…';

  @override
  String get storageAutoCleanup => 'Auto cleanup';

  @override
  String storageCleanupFailed(Object e) {
    return 'Cleanup failed: $e';
  }

  @override
  String get storageClearConversation => 'Clear by conversation';

  @override
  String get storageClearConversationHistory => 'Clear conversation history';

  @override
  String get storageConversationHistoryCleared =>
      'Conversation history cleared';

  @override
  String storageDeleteLocalChatHistory(Object p1) {
    return 'Delete all local chat history for \"$p1\" (server records are unaffected). This cannot be undone.';
  }

  @override
  String get storageDeleteOlderLocalRecords => 'Delete older local records';

  @override
  String storageDeletedRecords(Object removed) {
    return 'Deleted $removed records';
  }

  @override
  String storageKeepLastDays(Object days) {
    return 'Keep only the last $days days';
  }

  @override
  String storageMessagesConversations(Object _messageCount, Object p1) {
    return '$_messageCount messages · $p1 conversations';
  }

  @override
  String storageMessagesDotSessions(Object p1, Object p2) {
    return '$p1 · $p2';
  }

  @override
  String get storageNoLocalChatHistory => 'No local chat history yet';

  @override
  String storagePermanentlyDeleteLocalChat(Object days) {
    return 'Permanently delete local chat history older than $days days (server records are unaffected). This cannot be undone.';
  }

  @override
  String get storageProcessing => 'Processing…';

  @override
  String storageReclaimFailed(Object e) {
    return 'Reclaim failed: $e';
  }

  @override
  String get storageReclaimFreeSpace => 'Reclaim free space';

  @override
  String get storageReclaimedFreeSpace => 'Reclaimed free space';

  @override
  String get storageStorageUsed => 'Storage used';

  @override
  String get storageVACUUMRunAfterDeleting =>
      'VACUUM (run after deleting records)';

  @override
  String get themeSettingsAccentColor => 'Accent color';

  @override
  String get themeSettingsAndroidFollowsWallpaperLinux =>
      'Android follows the wallpaper, Linux follows the desktop theme; when on, the accent color above is ignored';

  @override
  String get themeSettingsChatTextSize => 'Chat text size';

  @override
  String get themeSettingsExampleMessageScalesText =>
      'Example: this message scales with the text size.';

  @override
  String get themeSettingsGotReply => 'Got it! This is my reply.';

  @override
  String get themeSettingsHiSampleMessageOther =>
      'Hi, this is a sample message from the other person.';

  @override
  String get themeSettingsHighContrast => 'High contrast';

  @override
  String get themeSettingsIncreaseForegroundBackgroundContrast =>
      'Increase foreground/background contrast (M3 high-contrast level) for low vision or bright light';

  @override
  String get themeSettingsLivePreview => 'Live preview';

  @override
  String get themeSettingsOnlyAppliesDarkMode =>
      'Only applies in dark mode (currently light mode)';

  @override
  String get themeSettingsPureBlackModeAMOLED => 'Pure black mode (AMOLED)';

  @override
  String get themeSettingsResetDefault => 'Reset to default';

  @override
  String get themeSettingsShowRawTextRich => 'Show raw text for rich text';

  @override
  String get themeSettingsThemeMode => 'Theme mode';

  @override
  String get themeSettingsUsePureBlackBackgrounds =>
      'Use pure black backgrounds in dark mode for lower OLED power use and a deeper look';

  @override
  String get themeSettingsUseSystemColors => 'Use system colors';

  @override
  String get themeSettingsWhenGameTagsLike =>
      'When on, game tags like [i][color][b] are shown as-is instead of rendering colors, bold or emoji';

  @override
  String videoUnablePlay(Object error) {
    return 'Unable to play: $error';
  }

  @override
  String get videoVideo => 'Video';

  @override
  String get visitorsNoVisitorsYet => 'No visitors yet';

  @override
  String get visitorsVisitorRecords => 'Visitor records';

  @override
  String get voiceNoMicrophonePermissionDevice =>
      'No microphone permission, or the device is unavailable';

  @override
  String voicePlayingVoiceSeconds(Object total) {
    return 'Playing voice, $total seconds';
  }

  @override
  String get voiceStopSend => 'Stop and send';

  @override
  String get voiceVoicePlaybackIsntSupported =>
      'Voice playback isn\'t supported on this platform yet';

  @override
  String get bubbleNameStyleNote =>
      'Bubble names/styles are defined by the game\'s built-in config and cannot be shown by external clients, so only equip switching is available.';

  @override
  String chatRoomNameInGame(Object p1) {
    return 'Room: $p1 (Join in-game)';
  }

  @override
  String get dataImportMergeConfirm =>
      'Messages, chats and friends from the backup will be merged into the current account. Existing records are skipped automatically; local data is never deleted or overwritten. Continue?';

  @override
  String dataImportSummary(Object p1, Object p2, Object p3) {
    return 'Import complete: $p1 messages, $p2 chats, $p3 friends';
  }

  @override
  String settingsAboutCheckFailedWithUrl(Object p1, Object p2) {
    return 'Check failed: $p1\n\nYou can also check the Releases page directly:\n$p2';
  }

  @override
  String settingsAboutClientLine(Object p1, Object p2, Object p3) {
    return 'Mini World external chat client · Client $p1 ($p2) · $p3';
  }

  @override
  String settingsAboutLogSizeNote(Object p1) {
    return '$p1 KB · App-private directory (auto-rotated)';
  }

  @override
  String storageMessagesAndSessions(Object p1, Object p2) {
    return '$p1 messages · $p2 conversations';
  }

  @override
  String storageFreePagesNote(Object p1) {
    return ' · $p1 free pages reclaimable';
  }

  @override
  String chatFoundCount(Object p1) {
    return 'Found $p1';
  }

  @override
  String get chatRecent100Only => ' (showing the latest 100 only)';

  @override
  String loginRemoveAccountConfirm(Object p1) {
    return 'Remove $p1?\n(Game account is not affected)';
  }

  @override
  String playerInfoTitleWithValue(Object p1) {
    return 'Title: $p1';
  }

  @override
  String chatAmountYuan(Object p1) {
    return 'Amount ¥$p1';
  }

  @override
  String get dataExportEncrypted => 'Export (encrypted)';

  @override
  String get dataExportEncryptedHint =>
      'Protect the backup with a passphrase (AES-256-GCM)';

  @override
  String get dataPassphraseEmpty => 'Passphrase cannot be empty';

  @override
  String get dataPassphraseMismatch => 'Passphrases do not match';

  @override
  String get dataSetBackupPassphrase => 'Set backup passphrase';

  @override
  String get dataEnterBackupPassphrase => 'Enter backup passphrase';

  @override
  String get dataPassphrase => 'Passphrase';

  @override
  String get dataPassphraseHint =>
      'At least 6 characters; unrecoverable if forgotten';

  @override
  String get dataPassphraseAgain => 'Repeat passphrase';

  @override
  String get dataConfirm => 'OK';

  @override
  String get settingsAboutDownloadUpdate => 'Download and install';

  @override
  String get settingsAboutDownloading => 'Downloading update';

  @override
  String get settingsAboutNoPackageForPlatform =>
      'No package for this platform in that release';

  @override
  String get settingsAboutUpdateOpened => 'Opened the installer';

  @override
  String get settingsAboutUpdateSaved =>
      'Downloaded; install it from your file manager';

  @override
  String get settingsAboutUpdateDownloadFailed =>
      'Download failed; check your network and retry';

  @override
  String get chatDropImageHere => 'Drop to send the image';

  @override
  String get chatDropOnlyImages => 'Only image files can be dropped';

  @override
  String get chatImageReadFailed => 'Failed to read the image';
}
