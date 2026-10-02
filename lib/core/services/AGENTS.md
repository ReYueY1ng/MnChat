# lib/core/services

**Score: 13** — 30 files / 11,629 LOC, 30 external importers, `ChatService` alone referenced 48 times.

## OVERVIEW
HTTP service clients plus the realtime chat pipeline. Every `/miniw/*` and `/server/*` request exits through `gateway.dart`.

## WHERE TO LOOK
| Task | File |
|------|------|
| Build a signed /miniw/ URL | gateway.dart — `buildFriendRequestUrl`, `buildGroupUrl`, `buildMiniwParamMd5Url`; all params incl. `cmd`/`msg` sign |
| Chat I/O entry point | chat_service.dart (1,193 LOC) — owns chat/* wiring, `SessionSnapshot` |
| Feed / dynamics | dynamics.dart (1,044 LOC) — `DynamicsClient`, 8+ UI importers |
| Contacts | partner.dart (757), friend.dart (582), group.dart (329), family.dart (298) |
| Own profile / home | profile.dart (752), player_home.dart (485), title_config.dart |
| Mail & notify | message_center.dart (600), msg_box.dart (542), notification_service.dart (319) |
| Realtime push | chatpush.dart (435) → chat/push_dispatcher.dart |
| Login | auth.dart — `AuthClient` |
| Linux tray | sni_tray.dart (hand-rolled D-Bus SNI); sni_tray_stub.dart is the no-op fallback |
| Image / media cache | image_disk_cache.dart (331), rich_media.dart, emoji_store.dart |

## CONVENTIONS
- One `*Client` or `*Service` class per file with constructor-injected deps (`Dio? dio`, cache instances) for testability.
- HTTP always through `../net/http_factory.dart` → `createDio()` (15 importers), never `Dio()`.
- Response decode is layered: 11 files `show`-import `../protocol/lua_table.dart` `decodeHttpResponse`; `gateway.dart`'s `decodeGatewayResponse` adds JSON → LuaTable → empty-map fallback.
- Doc comments cite the ported Lua range, e.g. `friendservice.lua:947-1010`.
- chat/reconnect_policy.dart and chat/online_notify.dart are deliberately side-effect-free; `ReconnectPolicy`'s RNG is constructor-injected.

## ANTI-PATTERNS
- Monoliths: chat_service.dart and dynamics.dart mix I/O, state, and business logic. Split new logic rather than adding more.
- No DI container. Clients are built by hand in state/providers.dart — new dependencies must be threaded through there.
- `decodeGatewayResponse` swallows `LuaTableDecodeError` into `{}`: callers cannot tell empty from unparsable. Don't add more silent fallbacks.
- sni_tray_stub.dart mirrors `SniTray`'s API but no-ops; platform-check before `start()`/`stop()`.
- Zero `TODO`/`FIXME`/`// ignore:` markers in scope today; don't add the first one.
