# lib/core/services

**Score: 13** — 33 files / 14,456 LOC + the `chat/` subdir (own AGENTS.md); `ChatService` alone is referenced 93 times across 33 files, `PlayerProfile` across 27.

## OVERVIEW
HTTP service clients plus the realtime chat pipeline. Every `/miniw/*` and `/server/*` request exits through `gateway.dart`.

## WHERE TO LOOK
| Task | File |
|------|------|
| Build a signed /miniw/ URL | gateway.dart (181) — `GatewayClient`, `buildFriendRequestUrl`, `buildGroupUrl`, `buildMiniwParamMd5Url`, `decodeGatewayResponse`; all params incl. `cmd`/`msg` sign |
| Chat I/O entry point | chat_service.dart (1,421) — owns all `chat/*` wiring and `SessionSnapshot` |
| Feed / dynamics | dynamics.dart (2,155) — `DynamicsClient` + typed result models (`DynamicsAck`, `DynamicsTopic`, `DynamicsVoteInfo`, `DynamicsRedpointNotice`) |
| Contacts | profile.dart (975, `ProfileClient`/`PlayerProfile`), partner.dart (860, `PartnerClient`), friend.dart (657, `FriendClient`), group.dart (403), family.dart (422) |
| Own profile / home | player_home.dart (545), title_config.dart (406), social_sign.dart (325) |
| Mail & notify | message_center.dart (672), msg_box.dart (683), notification_service.dart (334) |
| Realtime push | chatpush.dart (446) → chat/push_dispatcher.dart |
| Login | auth.dart (393) — `MiniAuth`, `LoginClient`, `MiniAuthError` |
| Error surface | request_errors.dart (272) — `RequestErrorBus`, `RequestFailure`, `reportIfFailed`, `describeRequestCode` |
| Desktop tray | tray_service.dart (305) → sni_tray.dart (hand-rolled D-Bus SNI) / sni_tray_stub.dart no-op fallback |
| Image / media cache | image_disk_cache.dart (331), rich_media.dart (350), emoji_store.dart (357) |

## CONVENTIONS
- One `*Client` or `*Service` class per file with constructor-injected deps (`Dio? dio`, cache instances) for testability.
- HTTP always through `../net/http_factory.dart` → `createDio()` (22 importing files), never `Dio()`.
- Response decode is layered: 14 files import `../protocol/lua_table.dart` and call `decodeHttpResponse`; `gateway.dart`'s `decodeGatewayResponse(text, url: …)` decodes JSON → LuaTable, and on `LuaTableDecodeError` reports to `RequestErrorBus` instead of silently returning `{}`.
- Doc comments cite the ported Lua range, e.g. `friendservice.lua:947-1010`.
- `dynamics.dart` is the pilot for typed returns: its methods hand back models, never `Map<String, Object?>` (lenient null/0/empty degradation still applies). The other clients still return raw maps — follow dynamics.dart when you touch them next.
- chat/reconnect_policy.dart and chat/online_notify.dart are deliberately side-effect-free; `ReconnectPolicy`'s RNG is constructor-injected.

## ANTI-PATTERNS
- Do not hand a raw `Map<String, Object?>` to the UI: it leaks server field names into pages and gets indexed with `['key']` there. `dynamics.dart` shows the target shape (typed models + parsing in the client); the remaining clients are still on the old shape and should be migrated opportunistically, not in one sweep.
- No DI container. Clients are built by hand in state/providers.dart — new dependencies must be threaded through there.
- A response body that is neither JSON nor LuaTable used to be swallowed into `{}` by `decodeGatewayResponse` — callers could not tell "empty" from "unparsable". That hole is closed (it reports to `RequestErrorBus`). Don't open a new one: if you add a decode path, surface the failure rather than returning an empty map.
- sni_tray_stub.dart mirrors `SniTray`'s API but no-ops; platform-check before `start()`/`stop()`.
- `/server/friend` 的信封是 `{"result":N}`，那个 N 是**好友服务自己的**码表；网关码表（`errorcode.lua`，2 = UNKNOW_SERVICE）只适用于 `code`/`ret`。别把 `result:2` 读成「服务未注册」去改地址 —— 实测该 cmd 是**被识别的**（回业务信封），而把 cmd 拼错时回的是**空 body**。那张码表在 `friendservice.lua:300`（`2=sign_error`、`3=no_src_uin`、`5=to_self`、`7=has_apply`、`12=no_apply`）。**签名子集逐 cmd 不同**：服务端按「收到的参数 − 该 cmd 的 notAuth 表」重算 md5，**多签一个键就回 2、少发一个键不挂**；notAuth 是 `addparam(name, value, url_escape, notAuth)` 的**第 4 参**（第 3 参是 url_escape，`addparam("msg", text, true)` 不表示 notAuth）。改签名形状前先对该 cmd 的反编译行，别照隔壁 cmd 对称改。
- Zero `TODO`/`FIXME`/`// ignore:` markers in scope today; don't add the first one.
