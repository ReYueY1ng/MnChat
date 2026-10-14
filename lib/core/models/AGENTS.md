# lib/core/models

**Score: 12** — 13 .dart files / 3,645 LOC, ~40 external importers. `messages.dart` is the widest-imported core file (46 import lines repo-wide).

## OVERVIEW
Data classes and lenient parsers for server payloads. Shape-and-parse only: no Dio, no Drift, no Flutter.

## WHERE TO LOOK
| Task | File |
|------|------|
| Chat message / session / contact shapes | messages.dart (606) — `ChatMessage`, `ChatSession`, `ChatMsgType`, `decodeChatExtendData` |
| Emoji (pack, pic, IMFC) | emoji_catalog.dart (493) — `parseImfc`, `parseEmojiCodeRefs`, `emojiSendCode` |
| Homepage modules / stats | homepage_modules.dart (527) — `kHomeModuleNames`, `homeLayout`, `HomeWork` |
| Skins / roles / rides | skin_head_catalog.dart (617) — `headIconAsset`, `roleIconAsset`, `rideIconAsset` |
| Head frames | head_frame_catalog.dart (435), animated_frames.dart (103, `kAnimatedFrameIds`) |
| Medals / gifts / inventory | medal_catalog.dart (153), gift_catalog.dart (286, `parseGiftCatalog`), account_inventory.dart (136, `AccountInventory`) |
| Nickname & rich text | nickname.dart (118) — `plainNickname`, `plainContent`, `hasRichMarkup` |
| Session key format | session_key.dart (28) — `sessionKeyOf` / `sessionKeyFor`；全仓唯一定义，其它位置一律转调 |
| Friend tags / mentions | friend_tag.dart (106, `encodeFriendLabel`/`decodeFriendLabel`), mention.dart (37, `textMentions`) |

## CONVENTIONS
- Parsers are top-level functions; classes only for stateful or UI types.
- Every parser skips malformed data and returns null/0/empty lists — explicitly documented: "任何脏数据只跳过，绝不抛异常".
- Static catalogs (skin, head frame, medal, animated frames, emoji codes) are `k`-prefixed const Map/Set tables generated from decompiled game CSVs — update the table, not the code.
- New models need no build step; parsers are plain Dart. (Contrast with storage/, which does.)
- Imports stay minimal and deliberate: a model may pull a pure helper (`../services/title_config.dart` `extractLuaBlock`, `../services/social_sign.dart` `SocialDeclaration`, `../crypto/encoding.dart` `lenientBase64Decode`) but never a `*Client`, a Dio or a Drift type.

## ANTI-PATTERNS
- Do not make a model constructor or parser throw on dirty input.
- Do not add a class where a `k`-const table fits.
- Do not add network or IO to models. These files are consumed from both services/ and state/; keep them free of Dio or Drift imports.
