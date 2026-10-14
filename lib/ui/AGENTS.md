# lib/ui

Score 12 (distinct domain): 48 top-level `.dart` files / 17,698 LOC, 32 `*_page.dart` libraries. Distinct from `lib/core` (services/models) and `lib/state` (provider graph) — pages own only local view state and project providers.

## OVERVIEW
App UI layer: `MainShell` is the entry widget imported by `main.dart` (`show MainShell`), plus one screen per file (`*_page.dart`). Only two subdirectories — shared page-agnostic widgets in `widgets/` (own AGENTS.md) and tokens/theme in `theme/` (own AGENTS.md).

## WHERE TO LOOK
| Task | Location |
|------|----------|
| Entry shell, 3 tabs (会话/好友/动态), responsive rail vs bar | `home_shell.dart` (`MainShell`, 427 LOC) |
| Chat screen | `chat_page.dart` (902) + parts `chat_page_composer` (291) / `chat_page_bubbles` (607) / `chat_page_message_row` |
| Own / other player profile | `profile_page.dart` (448) + parts `profile_page_state_base` (565) / `_state_actions` (278) / `_widgets` (579) / `_widgets_compact` (290); `player_home_page.dart` (23) delegates to `ProfilePage(targetUin:)` |
| Session list + sort | `session_list_page.dart` (560) |
| Social graph: friends / family / partner / requests / relations | `friends_page.dart` (44) + `friends_page_state` (854) + `friends_page_list` (262); `family_page.dart` (505), `partner_page.dart`, `friend_request_page.dart` (470), `relation_page.dart` |
| Mail / message centre | `mail_page.dart` (137 — declares `MailPage`, `MailDetailPage`, `MailSelection`) + parts `mail_page_state` (1238) / `_widgets` (272) / `_detail` (137) |
| Dynamics feed / detail / publish | `dynamics_page.dart` (400), `dynamics_detail_page.dart` (62) + `_state` (1025) / `_post` (490) / `_comments` (574), `publish_dynamics_page.dart` (715), `dynamics_topic_page.dart` |
| Settings — top level is the account card + 5 `SettingsNavTile` entries + logout only | `settings_page.dart` + `settings_account/_general/_notification/_privacy/_about_page.dart`; `theme_settings_page.dart` (337) is pushed from `settings_general_page.dart` |
| Auth / lock | `login_page.dart`, `lock_page.dart` |
| Groups, visitors, QR, blacklist, sign-in, data, bubbles | `group_detail_page.dart` (711), `visitor_list_page.dart`, `my_qr_page.dart`, `blacklist_page.dart`, `social_sign_page.dart`, `data_page.dart`, `bubble_page.dart`, `quit_group_page.dart` |

## CONVENTIONS
- Settings is two levels: `settings_page.dart` is only the account card + 5 group entries + logout; each entry pushes a `settings_*_page.dart` sub-page (shared row widgets live in `widgets/settings_tiles.dart` — `SettingsSectionHeader` / `SettingsNavTile` / `SettingsSwitchTile` / `SettingsInfoTile` / `showSettingsToast`). Put a new setting in the matching sub-page, never back on the top level.
- One screen per file with `_page.dart` suffix; one public `XxxPage` widget per file; private helper widgets are `_PascalCase` in the same file.
- When a page outgrows ~600 lines, split it with `part` / `part of` — the library and its public symbols (including test-locator keys and `MailSelection`) stay identical, so no importer changes. Split today: `chat_page` (3 parts), `dynamics_detail_page` (3), `mail_page` (3), `profile_page` (4), `friends_page` (2); `widgets/avatar_edit_dialog.dart` uses the same pattern.
- Opening/closing a chat never happens by navigation — mutate `activeSessionProvider.notifier` (`open` / `close`) and let `MainShell` react.
- Chat state is preserved by `MainShell._chatInstance`, keyed `ValueKey(sessionKeyOf(type, id))` (format defined in `core/models/session_key.dart`); `IndexedStack` swaps list vs chat on narrow widths.
- Responsive checks come from `theme/app_tokens.dart` (`isCompactWidth`, `adaptiveDensity`), not raw `MediaQuery` arithmetic.
- Clamp content width with `AppSizes.narrowContent` (760) for single-column settings/detail/profile pages and `AppSizes.listContent` (1000) for list pages; never hard-code widths.
- 服务端昵称带富文本标记（`[i][color][b]顾念`）与反斜杠转义（`我\n的轨迹`）。**不走富文本的地方必须先过 `plainNickname`**（`core/models/nickname.dart`）：AppBar 标题、各种名牌、确认弹窗、列表行、赠送面板标题都算。需要富文本的地方用 `RichTextView`（内部会做转义归一），`AvatarView` 内部已自带清洗。
  这个坑反复出现——同一屏里头卡渲染正常、标题却是 `[i][color][b]顾念`。排查方式：`grep -n "'\$name" lib/ui` 与 `grep -rn 'Text(\(widget\.\)\?name' lib/ui`，逐个看是不是人昵称。已知修过：主页 AppBar / 名牌、赠送面板标题、删除好友确认框（两处）、好友选择器与群成员选择器、家族成员列表。

## ANTI-PATTERNS
- **Never start the foreground keep-alive service from `MainShell`** — it only stops it. Starting on foreground entry shows a permanent notification the user explicitly rejected; start/stop belongs to the app lifecycle callbacks.
- Clearing a session must also null `MainShell._chatInstance`; otherwise the wide chat panel keeps showing the previous conversation with only the selection highlight gone, and the user cannot tell it closed.
- Don't reintroduce a divergent "mini" other-player profile view. `PlayerHomePage` is a 23-line delegate over `ProfilePage(targetUin:)` kept only because many callers already pass `targetUin`.
- Preserve `MainShell._conversations` filtering: friends appear in the session list only when `lastMessage != null`, groups always. Loosening it changes the session tab's meaning.
- Put shared components in `widgets/` (has its own AGENTS.md) or tokens in `theme/`, not alongside the pages.
