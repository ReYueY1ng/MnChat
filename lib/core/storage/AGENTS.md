# lib/core/storage

**Score: 10** — 4 files / 4,517 LOC (3,595 of them generated); the only Drift layer in the repo — a distinct persistence domain.

## OVERVIEW
Drift (SQLite) database v9 + settings KV store + model-to-row mappers.

## WHERE TO LOOK
| Task | File |
|------|------|
| Schema / migrations | app_database.dart (302) — `AppDatabase`, tables `ChatMessages`/`ChatSessions`/`Friends`/`SettingsTable`, full inline v1→v9 history |
| Generated code | app_database.g.dart (3,595) — drift codegen output, committed; `part` of app_database.dart |
| Record mappers | chat_mapper.dart (148) — `chatMessageFromRecord`, `friendDisplayName`, re-exports `sessionKeyOf` |
| Settings KV | settings_store.dart (472) — `SettingsStore`, `SettingsKeys`, `SavedCredentials`, `SavedAccount` |

## CONVENTIONS
- **Never hand-edit app_database.g.dart.** It is drift codegen output committed to the repo; regenerate with `fvm dart run build_runner build` and commit both `.dart` and `.g.dart` together.
- `schemaVersion => 9`; DB name `kDbName = 'mnchat'`, opened via `driftDatabase(name:, native: DriftNativeOptions(databaseDirectory: getApplicationSupportDirectory))` — deliberately not the default Documents dir.
- Table classes live in app_database.dart with `@DataClassName` (`ChatMessageRecord`, `ChatSessionRecord`, `FriendRecord`, `SettingRecord`); the generated accessors (`chatMessages`, `chatSessions`, `friends`, `settings`) live in the `.g.dart`.
- `sessionKeyOf(type, id)` = `'${type.name}_$id'`, defined once in `../models/session_key.dart` and re-exported from chat_mapper.dart — import it, never re-copy the format string.
- Read-path sanitization over migration: `friendDisplayName` fixes stored garbage on read — "不修库、不加迁移".
- `SettingsStore` wraps the same `AppDatabase` instance (settings table); do not open a second handle for key-value data.
- Cross-account isolation: PKs / hot indexes all carry ownerUin (`idx_chat_messages_owner_session_time`, `idx_chat_messages_owner_time`).
- DND / pinned state in the settings table is keyed by the same session key: `SettingsKeys.sessionKey` forwards to `../models/session_key.dart` `sessionKeyFor`.

## ANTI-PATTERNS
- Do not add a `// ignore:` or a new schema migration just to mask a bad row; fix on the read path.
- Do not import this directory from models/ — direction of dependency is models ← storage.
- Migrations in v6→v7 used `addColumn` on a composite PK (a known past bug noted in the comments); v7→v8 rebuilt via `alterTable`. Read the inline migration history before touching composite keys.
- `credential_cipher.dart` (in crypto/, used here) is tamper-detection only, not a vault — it protects at-rest passwords, nothing more.
