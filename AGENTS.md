# PROJECT KNOWLEDGE BASE

**Generated:** 2026-10-14T15:35:47Z
**Commit:** 2e70ab7
**Branch:** main

## OVERVIEW
MNChat — a Flutter/Dart cross-platform chat client (Mini World social app). Flutter 3.47.2 (fvm), Dart ^3.13.2, Riverpod 3.x (Notifier classes, no @riverpod codegen), Drift/SQLite persistence, dio networking.

## STRUCTURE
```
MNChat/
├── lib/main.dart         # entry; wires AppDatabase, SettingsStore, all service clients
├── lib/ui/               # MainShell + 32 *_page.dart libraries (48 files / 17,698 LOC) + widgets/ + theme/
├── lib/core/             # framework leaf: net/, protocol/, utils/, services/ (+chat/), models/, storage/, crypto/
├── lib/state/            # Riverpod graph: 7 files / 1,273 LOC / 56 providers; one import surface
├── lib/chat/             # 2 files / 417 LOC; sessionKey adapter, forwards to core/models/session_key.dart
├── test/                 # 94 self-contained test files / 16,074 LOC, no shared harness/fixtures
├── tool/                 # 4 live-server Dart CLIs; emoji_anim/ Spine→webp pipeline; mitm/ capture addon
├── assets/               # 5,226 webp (headframes, emoticon anim); every path declared in pubspec.yaml
├── design/logo/          # 5 SVGs, viewBox-scaled, brand fill #108850
├── android/ windows/ linux/  # platform shells; android holds the native MethodChannel bridge
└── .github/workflows/    # 3 build-only jobs (apk/linux/windows); no analyze/test job
```

## WHERE TO LOOK
| Task | Location | Notes |
|------|----------|-------|
| App startup / DI wiring | lib/main.dart | `databaseProvider` override with `AppDatabase(driftDatabase(name: 'mnchat'))`; provider throws by design |
| Main shell / tab layout | lib/ui/home_shell.dart MainShell | 3 tabs; bottom bar narrow, left rail wide; `_chatInstance` keyed by `ValueKey(sessionKeyOf(type, id))` |
| Open/close chat | `ref.read(activeSessionProvider.notifier).open/close` | NOT Navigator; MainShell reacts |
| HTTP services | lib/core/services/ (33 clients) | all via `createDio()` in net/http_factory.dart; no inline `Dio()` |
| WS chat pipeline | lib/core/services/chat/ | push dispatch, lifecycle, reconnect, caches |
| Data models + parsers | lib/core/models/ | lenient: skip dirty data, never throw |
| DB schema | lib/core/storage/ (Drift v9) | generated `app_database.g.dart` is committed; rebuild with `fvm dart run build_runner build` |
| Crypto / signing | lib/core/crypto/ | sign chain (md5_sign), XXTEA, chatpush cipher, Lua encodings |
| Riverpod graph | lib/state/providers.dart + 6 parts | 56 providers; imported by 66 files repo-wide (46 inside lib/) |
| Theme tokens | lib/ui/theme/app_tokens.dart + app_theme.dart | AppSpacing/AppRadius/AppColors/AppSizes/AppSemanticColors; extend semantic colors, never raw `Color()`/magic spacing in pages |
| Reusable UI widgets | lib/ui/widgets/ (26 modules / 7,785 LOC) | no barrel; consumers import per-file with `show` |
| Chat message adapter | lib/chat/message_adapter.dart | `sessionKey` forwards to `models/session_key.dart` — the one definition |
| Android native bridge | android/.../MainActivity.kt + lib/core/services/native_bridge.dart | MethodChannel `mnchat/native`, 1:1 with the Dart side |
| Acceptance / smoke tests | tool/*.dart | 4 live-server CLI scripts; creds from `MNC_UIN`/`MNC_PASSWD` env or local MNClient config |

## CODE MAP
| Symbol | Type | Location | Refs (hits / files) | Role |
|--------|------|----------|---------------------|------|
| AppSpacing | ThemeExtension tokens | lib/ui/theme/app_tokens.dart | 563 | design-token entry point; every styled widget |
| sessionKey | function | lib/chat/message_adapter.dart | 227 (112 excl. generated) | chat session keying; forwards to `sessionKeyOf` |
| PlayerProfile | class | lib/core/services/profile.dart | 148 / 26 | profile fetch + head/DIY models |
| ChatMessage | class | lib/core/models/messages.dart | 128 / 21 | central data class of the whole app |
| ChatSession | class | lib/core/models/messages.dart | 118 / 29 | session shape |
| ChatService | class | lib/core/services/chat_service.dart | 93 / 33 | WS pipeline + push dispatch owner |
| AvatarView | widget | lib/ui/widgets/avatar_view.dart | 66 | shared avatar renderer |
| decodeHttpResponse | function | lib/core/protocol/lua_table.dart | 65 / 18 | single decoder for every `/miniw/*` + `/server/*` reply |
| plainNickname | function | lib/core/models/nickname.dart | 56 / 17 | strip rich-text markup for non-rich-text surfaces |
| AppDatabase | class | lib/core/storage/app_database.dart | 55 / 21 | Drift DB; provider override in main.dart |
| createDio | function | lib/core/net/http_factory.dart | 51 / 22 | ONLY Dio factory in the repo; no inline `Dio()` |
| RichTextView | widget | lib/ui/widgets/rich_text_view.dart | 41 | UBB/rich-text renderer |
| sessionKeyOf | function | lib/core/models/session_key.dart | 24 / 8 | THE session-key definition; 5 sites forward to it |
| MainShell | widget | lib/ui/home_shell.dart | 19 | root ConsumerStatefulWidget, 3 tabs |
| buildRichSpans | function | lib/ui/widgets/rich_text_view.dart | 12 | UBB/rich-text: @mentions, #[cC]RRGGBB, #n, #A\d{3}, #\{...\}, [mdemo], @IMFC; |

## CONVENTIONS
- `material_ui` ^1.4.0 imported instead of `flutter/material.dart` — 58 lib files use it, zero import `flutter/material`
- No barrel files anywhere in lib/core; every import is file-name + show/hide
- Oversized pages/widgets are split with Dart `part` / `part of` so the library and its public surface stay identical: `profile_page.dart` (448) + 4 parts, `avatar_edit_dialog.dart` (317) + 5 parts. Private `_Widget` helpers live in the parts — importers need no change
- Relative imports inside lib/core; consumers use `../../core/...` paths
- All parsers lenient: skip dirty data, never throw (models/, services/, chat/, storage/chat_mapper.dart)
- Test convention: "never-throw" degradation (missing → 0/empty/null, numeric-string tolerance); inline real-traffic literals; no mocking framework. Only timing exception: `test/chat_service_test.dart` waits 1100 ms twice on the login-timeout window
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
- CI: `.github/workflows/` holds 3 **build-only** jobs — `build_apk.yml`, `build_linux.yml`, `build_windows.yml`; each `timeout-minutes: 45`, `concurrency.cancel-in-progress`, Flutter version read via `jq -r .flutter .fvmrc`. There is NO analyze/test job — analysis is a local/agent gate only

## COMMANDS
```bash
# SDK
fvm flutter pub get                    # resolve deps (fvm-pinned Flutter 3.47.2 via .fvmrc)
dart analyze --fatal-infos lib         # lib/ 基线：0 issue（info 也算失败）
fvm flutter analyze --no-fatal-infos   # 全仓基线：0 error / 0 warning
fvm flutter test                       # whole suite (94 files)
fvm dart run build_runner build        # regenerate app_database.g.dart after schema changes
fvm flutter run -d linux               # or: fvm flutter build apk --release

# Manual smoke tests (live server)
MNC_UIN=... MNC_PASSWD=... fvm dart run tool/acceptance_login.dart
fvm dart run tool/headless_chat_flow.dart   # also listen_push.dart, verify_send.dart

# sqlite3 是预编译 native asset（hook 下载 + sha256 校验），native-assets 环节不再需要 clang/libclang-dev
```

## NOTES
- Nested AGENTS.md (12) live at: `lib/core/`, `lib/core/{net,crypto,models,services,storage}/`, `lib/core/services/chat/`, `lib/state/`, `lib/ui/`, `lib/ui/{theme,widgets}/`, `test/`. `lib/core/services/` owns 33 HTTP clients + the chat/ WS subdirectory.
- Biggest hotspots (library LOC, incl. all `part` files): `core/services/dynamics.dart` 2,155; `core/services/chat_service.dart` 1,421; `ui/chat_page.dart` 902 + 3 parts; `ui/profile_page.dart` 448 + 4 parts; `ui/mail_page.dart` 137 + 3 parts; `ui/friends_page.dart` 44 + 2 parts. `lib/state/providers.dart` is a 39-line `library;` + 6 parts (1,273 LOC total)
- `sessionKeyOf` is defined exactly once, in `lib/core/models/session_key.dart`. `storage/chat_mapper.dart` imports + re-exports it, and `message_adapter.dart` / `message_store.dart` / `settings_store.dart` (`SettingsKeys.sessionKey`) / `home_shell.dart` all forward to it. It used to be 5 hand-copied string literals; do not reintroduce a copy — import the model instead (it pulls in no drift, no Flutter)
- App-lifecycle ownership: the `keep-alive` service (`notificationServiceProvider`) and Android `ChatBackgroundService.kt` (foreground service) are started/stopped by Dart app-lifecycle callbacks, not MainShell; the service's start window must never call `stopService()`
- Android build: `abiFilters = ["arm64-v8a"]` only; NDK pinned `28.2.13676358` (override `-Pmnchat.ndkVersion=<ver>`); `android.injected.testOnly=false` is pinned on purpose (an IDE-injected `true` makes the installer reject the build); `aapt2FromMavenOverride` + `enableResourceOptimizations=false` ship commented — uncomment for Termux/aarch64 local builds. Release signing via `android/key.properties` (template `key.properties.template`); a missing file falls back to the debug key; CI injects `ANDROID_KEYSTORE_BASE64`. Aliyun Maven mirrors in `settings.gradle.kts` + root `build.gradle.kts`; Java 17.
- `assets/`: 5,226 webp, every path declared in `pubspec.yaml`; `test/head_frame_test.dart` asserts each head-frame webp exists and decodes 128x128, so asset renames fail tests. `tool/emoji_anim/` is dev-only (Spine 3.8 → animated webp, needs an external `spine2webp`; runtime never vendored, non-commercial) and drops output into `assets/emoticon/anim/`
- `.gitignore` excludes `.omo/`, credentials, `*.log`, `session.json`, `config.yaml`, `.env`, sqlite files, `mncap/`. `analysis_options.yaml` includes `package:flutter_lints/flutter.yaml` and excludes `build/** android/** windows/** linux/**` (never analyzed)
- sqlite3 用 native asset 预编译：hook 下载 sqlite3 包对应 GitHub release 的库，按包内 asset_hashes.dart 校验 sha256，缓存在 `.dart_tool/hooks_runner/shared/sqlite3/`。仓库不再 vendored amalgamation；构建网络打不开 GitHub 时用 sqlite3 的 `url_pattern` user-define 指向镜像（校验仍然生效）
