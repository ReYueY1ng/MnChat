# lib/core/storage

**Score: 10** — 4 files / 4,363 LOC; distinct domain (SQLite persistence) and the only drift layer in the repo.

## OVERVIEW
Drift (SQLite) database v9 + settings KV store + model-to-row mappers.

## WHERE TO LOOK
| Task | File |
|------|------|
| Schema / migrations | app_database.dart (275) — `AppDatabase`, tables `ChatMessages`, `ChatSessions`, `Friends`, `SettingsTable`; migration history is inline doc |
| Generated code | app_database.g.dart (~3,595) — output of drift codegen, committed |
| Record mappers | chat_mapper.dart (146) — `chatMessageFromRecord`, `friendDisplayName`, `sessionKeyOf` |
| Settings KV | settings_store.dart (347) — `SettingsStore`, `SettingsKeys`, `SavedCredentials`, `SavedAccount` |

## CONVENTIONS
- **Never hand-edit app_database.g.dart.** It is drift codegen output committed to the repo; regenerate with `fvm dart run build_runner build` and commit both `.dart` and `.g.dart` together.
- The DB file is native-SQLite, not path_provider JSON — settings were deliberately migrated to a Drift key-value table for reliability.
- Table classes are declared in app_database.dart; the generated accessors (`chatMessages`, `chatSessions`, `friends`, `settings`) live in app_database.g.dart.
- `sessionKeyOf(type, id)` = `'${type.name}_$id'`, defined once in `../models/session_key.dart` and re-exported from chat_mapper.dart — import it, never re-copy the format string.
- Read-path sanitization over migration: `friendDisplayName` fixes stored garbage on read — "不修库、不加迁移".
- `ChatSessionRecord` and `ChatMessageRecord` data classes are named via `@DataClassName` on the Table classes in app_database.dart.
- `SettingsStore` wraps the same `AppDatabase` instance (settings table); do not open a second handle for key-value data.
- Cross-account isolation: PKs / hot indexes all carry ownerUin (`idx_chat_messages_owner_session_time`, `idx_chat_messages_owner_time`).

## ANTI-PATTERNS
- Do not add a `// ignore:` or a new schema migration just to mask a bad row; fix on the read path.
- Do not import this directory from models/ — direction of dependency is models ← storage.
- Migrations in v6→v7 used `addColumn` on a composite PK (a known past bug noted in the comments); v7→v8 rebuilt via `alterTable`. Read the inline migration history before touching composite keys.
- `credential_cipher.dart` (in crypto/, used here) is tamper-detection only, not a vault — it protects at-rest passwords, nothing more.
