# lib/state

Score 11 (distinct domain): the app-wide Riverpod graph — 7 files / 1,273 LOC, 56 provider fields, imported by 66 files repo-wide (46 of them inside `lib/`). No other directory defines providers.

## OVERVIEW
`providers.dart` is a 39-line `library;` whose six `part` files hold everything the UI can watch: service singletons, auth/session state, `ChatService` streams, persisted settings and the per-feature client providers.

## STRUCTURE
| Part | LOC | Owns |
|------|-----|------|
| `providers_core.dart` | 31 | `databaseProvider` (throws on purpose), `settingsProvider`, `chatServiceProvider`, `chatBridgeProvider` — singletons built once and `ref.onDispose`d |
| `providers_account.dart` | 328 | `authProvider`, `activeSessionProvider`, `myUinProvider`, `myAvatarInfoProvider` (+ `AuthState`) |
| `providers_chat.dart` | 71 | `sessionListProvider`, `contactsProvider`, `friendRequestStreamProvider`, `friendRequestCountProvider`, `sessionSortModeProvider` |
| `providers_settings.dart` | 484 | theme / accent / font scale / notifications / DND / keep-alive / tray / lock toggles — 30 `SettingsKeys` reads+writes live here |
| `providers_social.dart` | 270 | message-centre, msg-box, dynamics, profile, map-info and partner clients; `requestErrorBusProvider`, friend tags, partner trio (`partnerDirectory` / `myPartnerList` / `partnerSlot`) |
| `providers_media.dart` | 50 | `emojiStoreProvider`, `giftCatalogProvider`, `giftInventoryProvider`, `ownedSkinIdsProvider` |

## CONVENTIONS
- Riverpod 3.x `Notifier` API only — `StateNotifier`/`StateProvider` are gone in 3.x (12 `Notifier` subclasses today); singletons are `Provider`s, service streams `StreamProvider`s, one-shot fetches `FutureProvider`s.
- One import surface: `import '../state/providers.dart';` inside `lib/`, `package:mnchat/state/providers.dart` in `test/` (20 files). A new provider goes into the matching `part` — never a new top-level file.
- Dependency direction is one-way: `lib/state` imports `lib/core` and `lib/chat`; it never imports `lib/ui` (measured 0).
- Persisted setting pattern: `NotifierProvider<XNotifier, T>` whose `build()` reads `settingsProvider` asynchronously, guards the late write with `ref.mounted`, and whose setter writes back through `SettingsStore`.
- `sessionListProvider` / `contactsProvider` project `ChatService.sessionStream` — stream data is projected, never duplicated into a second cache here.
- `databaseProvider` throws `UnimplementedError`; `main.dart` supplies the real `AppDatabase` via `ProviderScope(overrides: [databaseProvider.overrideWithValue(db)])`.
- `AuthState` implements `==` deliberately: without it, each login blip (`authenticating → connectingChatPush → connected`) re-runs every `watch(authProvider)` client provider and duplicates requests. Keep it.

## ANTI-PATTERNS
- No Flutter UI imports — only `dart:ui show Color` for colour values (`providers_settings.dart`). A widget or `BuildContext` here is a layering bug.
- Don't touch drift tables or service internals from a provider; go through the service singletons (`chatServiceProvider`, `settingsProvider`).
- Don't re-implement session keys or message ids here — `sessionKeyOf` lives in `core/models/session_key.dart`.
- Don't add another provider entry file or barrel: 66 importers rely on `providers.dart` being the single surface.
