# PROJECT KNOWLEDGE BASE

**Generated:** 2026-10-01T04:32:04Z
**Commit:** c88dd92
**Branch:** main

## OVERVIEW
MNChat — a Flutter/Dart cross-platform chat client (Mini World social app). Flutter 3.47.2 (fvm), Dart ^3.13.2, Riverpod 3.x (Notifier classes, no @riverpod codegen), Drift/SQLite persistence, dio networking.

## STRUCTURE
```
MNChat/
├── lib/main.dart          # entry; wires AppDatabase, SettingsStore, all service clients
├── lib/ui/               # MainShell + 24 screens + widgets/ modules; oversized pages split into `part` files
├── lib/core/             # framework-layer: net/, protocol/, utils/, services/, models/, storage/, crypto/
├── lib/chat/             # chat UI-adjacent adapters; sessionKey delegates to core/models/session_key.dart
├── test/                 # 63 self-contained test files, no shared harness/fixtures
├── tool/                 # 4 standalone dart-run acceptance scripts; emoji_anim/ Spine→webp dev pipeline
├── assets/               # headframes/headframes_anim webp; static not themed
└── design/logo/          # 5 SVGs, viewBox-scaled, brand fill #108850
```

## WHERE TO LOOK
| Task | Location | Notes |
|------|----------|-------|
| App startup / DI wiring | lib/main.dart | `databaseProvider` override with `AppDatabase(driftDatabase(name: 'mnchat'))`; provider throws by design |
| Main shell / tab layout | lib/ui/home_shell.dart MainShell | 3 tabs; bottom bar narrow, left rail wide; `_chatInstance` keyed by `ValueKey(sessionKeyOf(type, id))` |
| Open/close chat | `ref.read(activeSessionProvider.notifier).open/close` | NOT Navigator; MainShell reacts |
| HTTP services | lib/core/services/ (30 clients) | all via `createDio()` in net/http_factory.dart; no inline `Dio()` |
| WS chat pipeline | lib/core/services/chat/ | push dispatch, lifecycle, reconnect, caches |
| Data models + parsers | lib/core/models/ | lenient: skip dirty data, never throw |
| DB schema | lib/core/storage/ (Drift v9) | generated `app_database.g.dart` is committed; rebuild with `fvm dart run build_runner build` |
| Crypto / signing | lib/core/crypto/ | sign chain, XXTEA, chatpush cipher, encodings |
| Reusable UI widgets | lib/ui/widgets/ | no barrel; consumers import per-file with `show`; 10 test files import widgets directly |
| Theme tokens | lib/ui/theme/app_tokens.dart + app_theme.dart | AppSpacing/AppRadius/AppColors/AppSemanticColors; extend semantic colors, never raw `Color()`/magic spacing in pages |
| Chat message adapter | lib/chat/message_adapter.dart | `sessionKey` forwards to `models/session_key.dart` — the one definition |
| Acceptance / smoke tests | tool/*.dart | 4 CLI scripts; read creds from `MNC_UIN`/`MNC_PASSWD` env or local MNClient config |

## CODE MAP
| Symbol | Type | Location | Refs | Role |
|--------|------|----------|------|------|
| ChatMessage | class | lib/core/models/ | 75 | highest-centrality data class |
| AppDatabase | class | lib/core/storage/ | 66 | Drift DB; provider override in main.dart |
| ChatService | class | lib/core/services/chat/ | 48 | WS pipeline + push dispatch |
| createDio | function | lib/core/net/http_factory.dart | 31 | single HTTP factory; no inline Dio() anywhere |
| sessionKeyOf | function | lib/core/models/session_key.dart | — | the ONE session-key definition; chat_mapper re-exports it, message_adapter / message_store / settings_store / home_shell forward to it |
| MainShell | widget | lib/ui/home_shell.dart | — | root ConsumerStatefulWidget, 3 tabs |
| showFloatingPanel | function | lib/ui/widgets/floating_panel.dart | — | adaptive popup primitive; emoji_picker + gift_picker build on it |
| buildRichSpans | function | lib/ui/widgets/rich_text_view.dart | — | UBB/rich-text: @mentions, #[cC]RRGGBB, #n, #A\d{3}, #\{...\}, [mdemo], @IMFC; |

## CONVENTIONS
- `material_ui` ^1.4.0 imported instead of `flutter/material.dart` — 48 files use it, zero import `flutter/material`
- No barrel files anywhere in lib/core; every import is file-name + show/hide
- Oversized pages/widgets are split with Dart `part` / `part of` so the library and its public surface stay identical: `profile_page.dart` (450) + 4 parts, `avatar_edit_dialog.dart` (317) + 5 parts. Private `_Widget` helpers live in the parts — importers need no change
- Relative imports inside lib/core; consumers use `../../core/...` paths
- All parsers lenient: skip dirty data, never throw (models/, services/, chat/, storage/chat_mapper.dart)
- Test convention: "never-throw" degradation (missing → 0/empty/null, numeric-string tolerance); inline real-traffic literals; no mocking framework; zero async-timing assertions
- Test-locator Keys: public top-level consts with `...Key` suffix (e.g. `avatarEditNavKey`); keep names stable
- FVM-pinned Flutter 3.47.2; `/.fvmrc` is single source of truth, CI reads it via `jq -r .flutter .fvmrc`
- No TODO/FIXME/DEPRECATED markers anywhere in lib/core today

## ANTI-PATTERNS (THIS PROJECT)
- `OverflowBox` on leading/avatar widgets — inflates to parent max width, trips ListTile "Leading widget consumes the entire tile width" assertion (runtime crash in friends_page)
- Raw `Color()` or magic spacing numbers in pages — extend AppSemanticColors or add a seed const to AppColors
- Vendoring the Spine runtime into the app or using it commercially — tool/emoji_anim outputs ship as webp assets only
- Inline `Dio()` — always use `createDio()`
- Hardcoding credentials in tool/*.dart — always read from `MNC_UIN`/`MNC_PASSWD` env or local MNClient config
- Modifying generated `app_database.g.dart` by hand — rebuild with `fvm dart run build_runner build`

## UNIQUE STYLES
- `AppSemanticColors` (ThemeExtension) falls back to `fromBrightness` when `of(context)` doesn't find it — bare `MaterialApp` tests don't attach the extension, so test widgets must wrap in a provider or theme that includes it
- Tray/window init happens after `runApp`, not awaited — avoids hot-restart hang
- `player_home_page.dart` (23 lines) delegates to `ProfilePage(targetUin:)` — shared profile card is single source of truth for self/other views
- Head frame assets: static `assets/headframes/<id>.webp`, animated `assets/headframes_anim/<id>.webp` (`kAnimatedFrameIds`); hardcoded, not themed
- `isCompactWidth` (shortestSide < 600) drives NavigationBar vs NavigationRail; `showFloatingPanel` switches to bottom sheet below 600dp
- CI: single job `analyze-and-test` on push(main)/PR/manual; concurrency cancels in-progress same-branch runs; two analyze steps — `dart analyze --fatal-infos lib` (lib/ must be issue-free, infos included) and `flutter analyze --no-fatal-infos` repo-wide (tolerates only the `avoid_print` infos in `tool/*.dart`); 30-min timeout

## COMMANDS
```bash
# SDK
dart analyze --fatal-infos lib         # lib/ 基线：0 issue（info 也算失败）
fvm flutter analyze --no-fatal-infos   # 全仓基线：0 error / 0 warning
fvm flutter test                       # sign_golden_test, s7_sign_test, lua_table_test, etc.
fvm dart run build_runner build        # regenerate app_database.g.dart after schema changes

# Manual smoke tests
fvm dart run tool/acceptance_login.dart
fvm dart run tool/headless_chat_flow.dart

# CI deps (clang, ninja-build, libclang-dev) required for native asset compilation
# pubspec hooks.user_defines compiles tool/sqlite3/sqlite3.c from local source
```

## NOTES
- `lib/core/services/` owns 30 HTTP service clients + the chat/ WS subdirectory — AGENTS.md at services/, services/chat/, models/, storage/, crypto/
- Biggest hotspots: chat_page.dart (1439), mail_page.dart (1296), core/services/dynamics.dart (1275), core/services/chat_service.dart (1213), friends_page.dart (1125), state/providers.dart (994). profile_page.dart (2191→450) and avatar_edit_dialog.dart (2013→317) were split into `part` files — see lib/ui/AGENTS.md
- `sessionKeyOf` is defined exactly once, in `lib/core/models/session_key.dart`. `storage/chat_mapper.dart` imports + re-exports it, and `message_adapter.dart` / `message_store.dart` / `settings_store.dart` (`SettingsKeys.sessionKey`) / `home_shell.dart` all forward to it. It used to be 5 hand-copied string literals; do not reintroduce a copy — import the model instead (it pulls in no drift, no Flutter)
- `keep-alive` service (`notificationServiceProvider`) is only stopped in MainShell; start/stop is owned by app lifecycle callbacks, not the shell
- SQLite amalgamation sources live in `tool/sqlite3/` — vendored, compiled via pubspec hook, not tracked as app code
