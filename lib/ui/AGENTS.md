# lib/ui

Score 11 (distinct domain): navigation hub + 24 screens, 13185 LOC across 27 files. Distinct from `lib/state`, `lib/chat`, `lib/core` — pages hold no state of their own, they project providers.

## OVERVIEW
App UI layer: `MainShell` is the entry widget imported by `main.dart`, plus one screen per file (`*_page.dart`). Shared, page-agnostic widgets live in `widgets/` (has its own AGENTS.md); design tokens live in `theme/`.

## WHERE TO LOOK
| Task | Location |
|------|----------|
| Entry shell, 3 tabs (会话/好友/动态), responsive rail vs bar | `home_shell.dart` (`MainShell`) |
| Chat screen | `chat_page.dart` (1439 LOC) |
| Own / other player profile | `profile_page.dart` (450 LOC library + 4 `part` files), `player_home_page.dart` (delegate, 23 LOC) |
| Session list + sort | `session_list_page.dart` |
| Friends / family / partner social graph | `friends_page.dart` (1125), `family_page.dart`, `partner_page.dart` |
| Mail | `mail_page.dart` (1296; also owns `MailDetailPage`) |
| Dynamics feed | `dynamics_page.dart`, `dynamics_detail_page.dart` (938), `publish_dynamics_page.dart` |
| Settings incl. theme + keep-alive toggles | `settings_page.dart`, `theme_settings_page.dart`, `message_settings_page.dart` |
| Auth / lock | `login_page.dart`, `lock_page.dart` |
| Groups, visitors, QR, blacklist, sign-in, data | `group_detail_page.dart`, `visitor_list_page.dart`, `my_qr_page.dart`, `blacklist_page.dart`, `social_sign_page.dart`, `data_page.dart` |

## CONVENTIONS
- One screen per file with `_page.dart` suffix; one public `XxxPage` widget per file; private helper widgets are `_PascalCase` in the same file.
- When a page outgrows ~600 lines, split it with `part` / `part of` — the library and its public symbols (including test-locator keys and shared tiles like `HomePartnerTile`) stay byte-identical, so no importer changes. `profile_page.dart` = `profile_page_state_base/state_actions/widgets/widgets_compact.dart`; the same pattern is used for `widgets/avatar_edit_dialog.dart`.
- Opening/closing a chat never happens by navigation — mutate `activeSessionProvider.notifier` (`open` / `close`) and let `MainShell` react.
- Chat state is preserved by `MainShell._chatInstance`, keyed `ValueKey(sessionKeyOf(type, id))` (format defined in `core/models/session_key.dart`); `IndexedStack` swaps list vs chat on narrow widths.
- Responsive checks come from `theme/app_tokens.dart` (`isCompactWidth`, `adaptiveDensity`), not raw `MediaQuery` arithmetic.
- Clamp content width with `AppSizes.narrowContent` (760) for single-column settings/detail/profile pages and `AppSizes.listContent` (1000) for list pages; never hard-code widths.
- 服务端昵称带富文本标记（`[i][color][b]顾念`）与反斜杠转义（`我\n的轨迹`）。**不走富文本的地方必须先过 `plainNickname`**（`utils/…`→ `core/models/nickname.dart`）：AppBar 标题、各种名牌、列表行都算。需要富文本的地方用 `RichTextView`（它内部会做转义归一）。两处都漏过同一个坑：主页头卡渲染正常、标题却是 `[i][color][b]顾念`。

## ANTI-PATTERNS
- **Never start the foreground keep-alive service from `MainShell`** — it only stops it. Starting on foreground entry shows a permanent notification the user explicitly rejected; start/stop belongs to the app lifecycle callbacks.
- Clearing a session must also null `MainShell._chatInstance`; otherwise the wide chat panel keeps showing the previous conversation with only the selection highlight gone, and the user cannot tell it closed.
- Don't reintroduce a divergent "mini" other-player profile view. `PlayerHomePage` is a 23-line delegate over `ProfilePage(targetUin:)` kept only because many callers already pass `targetUin`.
- Preserve `MainShell._conversations` filtering: friends appear in the session list only when `lastMessage != null`, groups always. Loosening it changes the session tab's meaning.
- Put shared components in `widgets/` (has its own AGENTS.md) or tokens in `theme/`, not alongside the pages.
