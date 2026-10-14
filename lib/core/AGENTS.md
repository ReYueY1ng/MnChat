# lib/core

**Score: 11** — 7 subdirs; the framework layer between `lib/ui` and the network. `services/`, `models/`, `storage/`, `crypto/` and now `net/` own their own AGENTS.md; `protocol/` and `utils/` (score 6 each) are covered here.

## OVERVIEW
Framework layer of MNChat: HTTP/WS clients, data models, SQLite storage, signing, endpoint config, the Lua/JSON response decoder, and log/cache helpers. Faithful ports of a legacy Lua/Python Mini World client.

## STRUCTURE
```
lib/core/
├── services/        # 33 HTTP clients + WS chat pipeline, `chat/` subdir (own AGENTS.md)
├── models/          # data classes + lenient parsers (own AGENTS.md)
├── storage/         # Drift v9 schema + settings KV store (own AGENTS.md)
├── crypto/          # signatures, XXTEA, encodings (own AGENTS.md)
├── net/             # endpoint config, Dio factory, msgpack, upload, dup-request monitor (own AGENTS.md)
├── protocol/        # lua_table.dart (340) — Lua-table/JSON hybrid response decoder
├── utils/           # log.dart (`log`/`redactUrl`) + request_cache.dart (single-flight + TTL)
├── emoticon.dart    # sprite-table emoticons + image widgets (563)
├── chat_emoji.dart  # kChatEmoji game-code → Unicode map (76)
└── app_info.dart    # kAppVersion (2)
```

## WHERE TO LOOK
| Task | Location |
|------|----------|
| Decode any HTTP response body | protocol/lua_table.dart → `decodeHttpResponse` (18 files), `decodeLuaTable`, `LuaTableDecodeError` |
| Coalesce a repeated fetch | utils/request_cache.dart → `RequestCache.run(key, fetch)`（单飞 + TTL；`cacheable` 可让业务失败不进缓存） |
| Shared log / redact secrets | utils/log.dart → `log`, `LogLevel`, `redactUrl` (16 files) |
| Emoticon sprite lookup | emoticon.dart → `EmoticonImage`, `ImfcEmojiImage`, `rectForCode` |
| Emoji-code text rendering | chat_emoji.dart → `kChatEmoji`, `decodeEmojiCodes`, `emojiRepr` |
| App version string | app_info.dart → `kAppVersion` |
| Transport: endpoints, Dio, msgpack, upload | net/ (own AGENTS.md) |
| Wire every service client | ../state/providers.dart (the single construction point; no DI container) |

## CONVENTIONS
- Every file opens with a Chinese `///` doc comment citing its ported source (Lua line range or an MNClient `*.py`); files that carry one declare `library;`.
- `lib/core` is a leaf of the dependency graph: it imports packages and its own relatives, never `lib/ui` or `lib/state`.
- Static catalogs and path constants are `k`-prefixed const tables lifted from decompiled game CSVs — update the table, not the code.

## ANTI-PATTERNS
- Never log a raw URL carrying s2/s2t/md5 — route it through `redactUrl` (`sensitiveQueryKeys`); that is why it is the most-used helper in utils/.
- Protocol constants (`kS7Alphabet`, `protocol_keys.dart`) are pinned; a wrong one breaks signing silently — there is no server-side validation loop in this repo.
