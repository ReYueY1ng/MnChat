# lib/ui/widgets

Score ~24 (distinct domain, high complexity): 26 self-contained modules, 7078 LOC. Root covers general lib/ui conventions.

## OVERVIEW
Shared, page-agnostic popup/dialog/panel widget modules. Each file is a self-contained unit: public symbols, its own private `_` helpers, and usually a top-level `Future show*(BuildContext, ...)` launcher.

## STRUCTURE
Flat directory — no subdirectories. No barrel file; consumers import per-file paths, usually with `show`: `import 'widgets/emoji_picker.dart' show showEmojiPicker;`.

## WHERE TO LOOK
| Task | File |
|------|------|
| Anchor panel popup primitive (bottom sheet on narrow, centered on wide ≥600) | `floating_panel.dart` (`showFloatingPanel<T>`, `kFloatingPanelWideWidth`) |
| Rich text / UBB parsing (`@` mentions, `#[cC]RRGGBB` colors, `[mdemo]`, `@IMFC&`) | `rich_text_view.dart` (`buildRichSpans`, `RichTextView`) |
| Avatar editor, 5 tabs (头像/头像框/昵称/称号/家族) | `avatar_edit_dialog.dart` (317 LOC library + 5 `part` files; loader typedefs `FamilyListLoader`, `TitleLoader`, `DiyAvatarUploader`, `FrameTopToggler`) |
| Player home / friend info sheet | `player_info_sheet.dart` (`showPlayerInfoSheet`, `showFriendMenu`) |
| Shared player-info model + fetch cache + content pieces | `player_info_common.dart` (`SessionPlayerInfo`, `playerInfoOf`, `PlayerInfoHeader` / `PlayerInfoStats` / `PlayerCircleAction`) |
| Per-player home popup (anchored, not a sheet) | `session_player_info_popup.dart` (`showSessionPlayerInfoPopup` — 26 call sites) |
| Dynamics feed card | `dynamics_card.dart` (`DynamicsCard` + 9 private sub-widgets) |
| Emoji / gift pickers | `emoji_picker.dart`, `gift_picker.dart` (each built on `showFloatingPanel`) |
| Head frame + avatar | `head_frame.dart` (`headFrameAsset`, `headFrameStaticAsset`, `HeadFrameOverlay`), `avatar_view.dart` |
| Partner name badges | `partner_badges.dart` (`LevelBadge`, `VipBadge`, `PartnerNameBadges`) |
| Menus / filters / image viewer | `session_menu.dart`, `friend_filter_dialog.dart`, `friend_tag_dialog.dart`, `account_menu.dart`, `image_viewer.dart` |

## CONVENTIONS
- Popups are launched by top-level `show*` functions; the widget class is often private and returned via `showDialog` / `showModalBottomSheet` / `showFloatingPanel`.
- Test-locator `Key` values are public top-level consts with a `...Key` suffix in camelCase (e.g. `avatarEditNavKey`, `avatarViewAvatarBoxKey`) — keep them; `test/*_test.dart` files import them.
- Fire-and-forget event handlers use `unawaited(...)` (import `dart:async show unawaited`).
- Spacing always from `../theme/app_tokens.dart` `AppSpacing` / `AppRadius`; raw numbers discouraged.
- The two player-info views (bottom sheet vs anchored popup) share ONE model, ONE fetch/cache path and the shared content widgets in `player_info_common.dart`; homepage field parsing comes from `core/models/homepage_modules.dart`. Do not re-implement either in a new view.
- Oversized modules split with `part` / `part of` (`avatar_edit_dialog.dart` + 5 parts) so the library identity and public symbols are unchanged.
- Head frame assets hard-coded to `assets/headframes/<id>.webp`; ids in `kAnimatedFrameIds` go to `assets/headframes_anim/` instead.

## ANTI-PATTERNS
- **No `OverflowBox` for avatar / leading widgets** — it inflates to the parent's max width and trips ListTile's `Leading widget consumes the entire tile width` assertion (runtime crash in `friends_page`); see the warning on `kAvatarListTileDensity` in `head_frame.dart`.
- No `// ignore:`, `// TODO:`, `// FIXME:`, `print` in this directory (CI baseline 0 warnings); do not introduce them.
- Unrecognized UBB markers in `buildRichSpans` are intentionally dropped, never rendered — do not "fix" them to show raw text.
- `dynamics_card_test.dart`, `avatar_edit_dialog_test.dart`, `emoji_picker_test.dart`, etc. all import these files directly; renaming public symbols breaks tests — check `test/` before renaming.
