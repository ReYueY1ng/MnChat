# lib/core/net

**Score: 8** — 5 files / 379 LOC; distinct transport domain. `createDio` is the highest-centrality symbol in `lib/core` after the models (22 importing files), and this is where every endpoint and environment switch lives.

## OVERVIEW
Everything that knows about servers and bytes: endpoint/env constants, the single Dio factory, the two-channel codec helpers, chunked presigned upload, and the repeated-request detector.

## WHERE TO LOOK
| Task | File |
|------|------|
| Change an endpoint / environment | config.dart (69) — `kDefaultBase`, `kLoginHost`, `kLoginPorts`, `kWsConfigUrl`, `kChatpushLbUrls`, `kDefaultUrls`; helpers `backendLogin()`, `backendWsConfig()`, `backendShequ()`, `backendChatpush(env)` |
| Get an HTTP client | http_factory.dart (65) — `createDio()`: sets the `kUa` User-Agent and installs the DuplicateRequestMonitor interceptor |
| Spot a repeated request | duplicate_request_monitor.dart (115) — `DuplicateRequestMonitor.instance.repeats`, `requestFingerprint` |
| Encode/decode both channels | msgpack.dart (21) — `msgpackPack`/`msgpackUnpack` for the XXTEA login channel **and** `chatpushJsonDecode`/`chatpushJsonEncode` for the chatpush WS channel |
| Upload a chat image | photo_upload.dart (109) — `uploadPresignedFile`; 128 KiB chunks (`kUploadChunkSize`) |

## CONVENTIONS
- `createDio()` is the only Dio constructor in the repo (22 importing files); it wires the `kUa` header, 15 s connect/receive timeouts, and one interceptor.
- Transport failures (timeout / offline / 4xx / 5xx) are reported centrally to `RequestErrorBus`; business-code failures (HTTP 200 with `code != 0`) are reported by each client, since only the client sees the code.
- It deliberately does **not** force a proxy-free connection: dio's default `IOHttpClientAdapter` (system proxy) is kept.
- Endpoint strings are constants in config.dart, never literals at a call site; environment switching goes through the `backend*()` helpers.
- `kVolatileQueryKeys` (duplicate_request_monitor.dart) lists the per-call params (time/s2t/md5) stripped before fingerprinting — keep it in sync with any new volatile param, or `repeats` reports false positives.
- msgpack.dart intentionally carries both codecs despite its name: the login payload is XXTEA + msgpack, the chatpush channel is rotate-XOR + JSON.

## ANTI-PATTERNS
- Never add a second Dio factory, a proxy override, or an inline `Dio()` — `createDio()` is the single construction point.
- Do not split the chatpush JSON codec out of msgpack.dart on the strength of the file name; the pairing is deliberate.

## NOTES
- photo_upload.dart implements the v2 chunked-multipart direct upload byte-for-byte from captured traffic: `act=info` → `upload_begin` → `upload_step`×N → `upload_end`; each part is `fileUpload` with filename = the file's md5, and the `upload_end` reply (`ok:token=…`) supplies the sub_token. Any step failing returns `null` rather than throwing.
- The upload URL is pre-signed by the caller (services/miniw_extra.dart); this module never builds one.
