# lib/core/models

**Score: 12** — 10 files / 3,313 LOC, 27 external importers. `messages.dart` (595 LOC) alone is referenced ~75 times — the widest-imported file in scope.

## OVERVIEW
Data classes and lenient parsers for server payloads. No network, no persistence — shape-and-parse only.

## WHERE TO LOOK
| Task | File |
|------|------|
| Chat message / session / contact shapes | messages.dart — `ChatMessage`, `ChatSession`, `ChatMsgType`, `decodeChatExtendData` |
| Emoji (pack, pic, IMFC) | emoji_catalog.dart (493) — `parseImfc`, `parseEmojiCodeRefs`, `emojiSendCode` |
| Homepage tiles / stats | homepage_modules.dart (483) — `kHomeModuleNames`, `HomeWork`, `homeLayoutEntries` |
| Skins / mounts | skin_head_catalog.dart (617) — `kSkinHeadIcon`, `roleIconAsset` |
| Head frames | head_frame_catalog.dart (435), animated_frames.dart |
| Medals / gifts | medal_catalog.dart, gift_catalog.dart — `parseGiftCatalog` |
| Nickname & rich text | nickname.dart — `plainNickname`, `hasRichMarkup` |
| Friend tags | friend_tag.dart — `FriendTag`, `encodeFriendLabel`, `decodeFriendLabel` |

## CONVENTIONS
- Parsers are top-level functions; classes only for stateful or UI types.
- Every parser skips malformed data and returns null/0/empty lists — explicitly documented: "任何脏数据只跳过，绝不抛异常".
- Static catalogs (skin, head frame, medal, animated frames, emoji codes) are `k`-prefixed const Map/Set tables generated from decompiled game CSVs — update the table, not the code.
- New models need no build step; parsers are plain Dart. (Contrast with storage/, which does.)

## ANTI-PATTERNS
- Do not make a model constructor or parser throw on dirty input.
- Do not add a class where a `k`-const table fits.
- Do not add network or IO to models. These files are consumed from both services/ and state/; keep them free of Dio or Drift imports.
- Do not add a barrel file here. 27 importers already use `show`/`hide` clauses; a barrel would break none of them but would duplicate what `show` already does.
