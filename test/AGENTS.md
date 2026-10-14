# test/ — self-contained test suite

Earned its own file at score 8 (94 files / 16,074 LOC → file count 3x, code ratio 2x, symbol density 2x, own convention 1x). The root states the test rule in one line; this is how a test here is actually written.

## OVERVIEW
94 `*_test.dart`, 16,074 LOC, flat: no subdirectory, and no non-`*_test.dart` file exists in this directory — deliberately no harness, fixture file or shared helper. Every file is a standalone `void main()` (744 `test(`, 201 `group(`, 132 `testWidgets(`) that builds all its own data, so any single file runs alone. Tests see the app only as `package:mnchat/...` (92 of 94 files); nothing in `lib/` imports `test/`.

## WHERE TO LOOK
| Subject | Files |
|---|---|
| Crypto / sign chain (goldens) | `sign_golden_test`, `s7_sign_test`, `credential_cipher_test`, `lua_table_test`, `base64_lenient_test` |
| Storage / migration | `app_database_migration_test` (inlines v7/v8/v9 DDL) |
| Chat + WS pipeline | `chat_service_test`, `chat_bridge_test`, `chat_list_stability_test`, `connection_manager_test`, `chat_draft_test`, `message_*_test` |
| Lenient parsers — largest cluster | 14 `*parse_test` + `homepage_modules_test` |
| Widgets / pages | 2 `*_widget_test` + `widget_test.dart` smoke + 5 `*_page_test` (`friends_`, `mail_`, `partner_`, `profile_`, `settings_`) |

Biggest files: `homepage_modules_test.dart` 739, `dynamics_result_parse_test.dart` 590, `avatar_edit_dialog_test.dart` 556, `partner_parse_test.dart` 501.

## CONVENTIONS
- **Widget tests mount through a local `pumpX(tester, {...})` helper in the same file**: `ProviderScope(overrides: [...])` → `MaterialApp(theme: buildAppTheme(Brightness.light), home: Scaffold(body: ...))` → `await tester.pumpAndSettle()`. Wide-layout tests set `tester.view.physicalSize` and `addTearDown(tester.view.reset)` (`avatar_edit_dialog_test.dart`). `buildAppTheme` is what attaches the `AppSemanticColors` extension, so a bare `MaterialApp` is not enough.
- **No mocking package** — dev deps are `flutter_test` (sdk), `flutter_lints`, `drift_dev`, `build_runner` only. Two hand-written stand-ins carry every test:
  - `class _Fake<Subject> extends <RealClient>` overriding methods — 13 fakes in 8 files (`chat_service_test.dart`: `_FakeLoginClient` / `_FakeChatPushClient` / `_FakeFriendClient` / `_FakeGroupClient`; `account_avatar_cache_test.dart`: `_FakeChatService`).
  - `class _StubAdapter implements HttpClientAdapter` (dio) installed as `Dio()..httpClientAdapter = _StubAdapter(bodies)` to replay captured server bodies; recording variants are `_RecordingAdapter` / `_FakePostingAdapter`. When the test is about the interceptor chain itself it uses `createDio()..httpClientAdapter = ...` (`duplicate_request_monitor_test.dart`).
  - Provider injection: `overrides: [xProvider.overrideWithValue(v)]` / `overrideWith((_) => Stream.value(...))`; `UncontrolledProviderScope` when the app owns the container (`chat_page_display_test.dart`).
- **Singleton state is reset explicitly, never by test order**: `tearDown(RequestErrorBus.instance.clear)` in 5 files (`gateway_test`, `request_error_indicator_test`, `request_errors_test`, `dynamics_detail_widget_test`, `partner_request_coalescing_test`).
- **Engine binding when decoding images**: `TestWidgetsFlutterBinding.ensureInitialized()` at the top of `main()` (`head_frame_test.dart`, `tray_icon_test.dart`), or `TestWidgetsFlutterBinding.ensureInitialized().runAsync(...)` for real codec work (`emoji_render_test.dart`).
- **Temp files, never the repo**: `Directory.systemTemp.createTemp(...)` for store/temp-DB tests (`emoji_store_test.dart`, `emoji_picker_test.dart`); drift tests open a local SQLite via `drift/native.dart` (10 files).
- **Real-traffic literals inline** — captured payloads, `extend_data` strings and historic schema DDL sit in the test body; there are no fixture files.
- **Assets are asserted for real**: `head_frame_test.dart` checks every `kAnimatedFrameIds` webp exists, is non-empty, and decodes to 128x128 — dropping or renaming a packaged asset fails tests, not just rendering.
- **Timing**: one file waits on the wall clock — `chat_service_test.dart` has two 1100ms `Future.delayed` for the login-timeout window. Everything else synchronizes on a stream/event or `pumpAndSettle`; do not add sleeps.

## ANTI-PATTERNS (THIS DIRECTORY)
- Adding a shared harness / fixture / `test_helpers.dart` file — the standalone rule is the invariant; helpers live in the file that needs them.
- Adding `mockito` / `mocktail` (not declared in `pubspec.yaml`) — hand-written `_Fake*` and `HttpClientAdapter` stubs are the sanctioned mechanism.
- Reaching the live server from a test — real-account flows live in `tool/*.dart` CLI scripts only.
- Renaming a public `...Key` const or any `show`ed lib symbol — tests locate widgets and import lib symbols by those exact names.

## COMMANDS
```bash
fvm flutter test                            # whole suite
fvm flutter test test/head_frame_test.dart  # one file
```
`dart analyze --fatal-infos lib` does not cover `test/`; test files are only analyzed by repo-wide `fvm flutter analyze --no-fatal-infos`.
