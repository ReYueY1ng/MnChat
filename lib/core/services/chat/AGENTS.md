# lib/core/services/chat

**Score: 10** — 11 files / 1,992 LOC; distinct domain (realtime push) versus the HTTP clients one level up.

## OVERVIEW
WebSocket side of chat: push dispatch, WS lifecycle, reconnect backoff, message upsert, and per-account display caches.

## WHERE TO LOOK
| Task | File |
|------|------|
| Push frame routing | push_dispatcher.dart (441) — `PushDispatcher`, driven by ../chat_service.dart |
| WS lifecycle | connection_manager.dart (162), ../miniw_extra.dart (409); channel config in ../chatpush.dart |
| Backoff | reconnect_policy.dart (72) — pure; RNG constructor-injected |
| Reconnect catch-up | reconnect_history.dart — pure `reconnectHistoryTargets`（只挑掉线窗口内有动静/未读的会话） |
| Persist & reload | message_store.dart, message_upserter.dart, session_loader.dart (358), offline_cache.dart (166) |
| Display caches | profile_cache.dart (216), group_name_cache.dart (81) |
| Commands | command_client.dart (208) |
| Online state | online_notify.dart (17) — pure `onlineFriendUins`, `newlyOnlineFriends` |

## CONVENTIONS
- Persistence goes through `../../storage/chat_mapper.dart` + `app_database.dart`; never touch drift tables directly from here.
- Session data shape comes from `../../models/messages.dart` (7 of 11 files import it); the `SessionSnapshot` type is defined in ../chat_service.dart, not here.
- Cross-account isolation follows the storage convention: every key carries ownerUin.
- Pure-logic modules stay pure on purpose: reconnect_policy.dart, online_notify.dart and reconnect_history.dart exist so unit tests can run without a socket.
- chat/ has no Riverpod providers; state lives in `SessionSnapshot` objects owned by `ChatService`. Do not lift chat/ state into state/ without routing it through the WS pipeline first.

## ANTI-PATTERNS
- Don't reintroduce side effects into reconnect_policy.dart or online_notify.dart — their tests depend on determinism.
- profile_cache and group_name_cache are in-memory per-account only; do not persist them into Drift.
- `sessionKeyOf` lives in `../../models/session_key.dart`; `message_store.dart` only forwards to it. Never re-implement the `'${type.name}_$id'` format here — there is exactly one definition and no copy to keep in sync.
- push_dispatcher.dart (441 LOC) is the second hotspot after chat_service.dart; route new push types through it rather than adding parallel dispatch.
