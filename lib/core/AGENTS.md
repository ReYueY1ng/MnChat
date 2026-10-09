# lib/core

**Score: 11** — 7 subdirs, the distinct framework layer. `services/`, `models/`, `storage/`, `crypto/` own their own AGENTS.md; `net/`, `protocol/`, `utils/` are covered here (each under 8 points on its own).

## OVERVIEW
Framework layer of MNChat: HTTP/WS clients, data models, SQLite storage, signing, endpoint config. Faithful ports of a legacy Lua/Python Mini World client.

## STRUCTURE
```
lib/core/
├── services/        # 30 HTTP service clients + WS chat pipeline (own AGENTS.md)
├── models/          # data classes + lenient parsers (own AGENTS.md)
├── storage/         # Drift schema + settings KV store (own AGENTS.md)
├── crypto/          # signatures, XXTEA, base64/urlencode (own AGENTS.md)
├── net/             # endpoint config, backend env switch, Dio factory, duplicate-request counter
├── protocol/        # lua_table.dart — Lua-table/JSON hybrid response decoder
├── utils/           # log.dart (`log`/`redactUrl`) + request_cache.dart (single-flight + TTL)
├── emoticon.dart    # sprite-table emoticons + 4 image widgets (563 LOC)
├── chat_emoji.dart  # kChatEmoji game-code → Unicode map
└── app_info.dart    # kAppVersion
```

## WHERE TO LOOK
| Task | Location |
|------|----------|
| Change a server endpoint / env | net/config.dart — `kDefaultBase`, `backendLogin()`, `backendChatpush(env)`, `kLoginPorts` (16 importers) |
| Get an HTTP client | net/http_factory.dart → `createDio()` (15 importers). Never `Dio()` inline |
| Spot repeated requests | net/duplicate_request_monitor.dart → `DuplicateRequestMonitor.instance.repeats`（`createDio()` 每次请求都记指纹，time/s2t/md5 等每次都变的参数已排除） |
| Coalesce a repeated fetch | utils/request_cache.dart → `RequestCache.run(key, fetch)`（单飞 + TTL；`cacheable` 可让业务失败不进缓存） |
| Decode a response body | protocol/lua_table.dart → `decodeHttpResponse`, `decodeLuaTable` (14 importers) |
| Shared log / URL redaction | utils/log.dart → `log`, `LogLevel`, `redactUrl` |
| Emoticon sprite lookup | emoticon.dart → `EmoticonImage`, `ImfcEmojiImage`, `rectForCode` |
| Emoji-code text rendering | chat_emoji.dart → `kChatEmoji`, `decodeEmojiCodes` |
| Wire all service clients | ../state/providers.dart (single construction point) |

## CONVENTIONS
- Relative imports only inside core (`../net/config.dart`); consumers use `../../core/...`. No `package:mnchat/` self-imports.
- Every parser is lenient: skip dirty data, return null/0/empty. Never throw.
- Static catalogs are `k`-prefixed const Map/Set tables generated from decompiled game CSVs — not Dart classes.
- Every file opens with a Chinese `///` doc comment; ports cite the source Lua line range.
- Riverpod 3.x `Notifier` classes only (10 in repo, zero `@riverpod` codegen).
- `material_ui` ^1.4.0 replaces `flutter/material.dart` (48 files import it, 0 import flutter/material).

## ANTI-PATTERNS
- No barrel/index.dart anywhere in core. Importers name files directly; do not add one.
- Never let a model constructor or parser throw on malformed server data.
- Never log raw URLs containing s2/s2t/md5 — use `redactUrl` with `sensitiveQueryKeys`.
- Protocol constants (`kS7Alphabet`, `protocol_keys.dart`) are pinned; changing one breaks signing silently.
- Never import `flutter/material.dart` — it collides with `material_ui` symbols.
