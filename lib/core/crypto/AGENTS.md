# lib/core/crypto

**Score: 9** — 7 files / 694 LOC; the pinned sign chain. `md5_sign.dart` is reached by 15 files (14 in lib/), the widest import here.

## OVERVIEW
Signing (md5_sign, s7_sign), symmetric ciphers (xxtea, chatpush_cipher, credential_cipher), and Lua-compatible encodings (encoding.dart).

## WHERE TO LOOK
| Task | File |
|------|------|
| HTTP param signatures | md5_sign.dart (189) — `httpGetParamMd5`, `httpGetParamKey`, `httpGetS1`/`S2`, `httpGetRealNameMobileSum`, `md5Sign`/`md5Token`; 15 importing files |
| S7 URL/token | s7_sign.dart (76) — `kS7Alphabet`, `encodeS7Url`, `s7Token`; reached from services/partner.dart |
| Login/room payload cipher | xxtea.dart (158) — `xxteaEncryptZip`/`xxteaEncrypt`/`xxteaDecrypt` |
| Chatpush WS channel | chatpush_cipher.dart (32) — rotate-XOR + JSON (the XXTEA/msgpack pair lives in net/msgpack.dart, not here) |
| Stored-password-at-rest | credential_cipher.dart (77) — `encryptPassword`/`decryptPassword`, HMAC-SHA256 keyed per uin; used only by storage/settings_store.dart |
| Lua-compatible url/base64 | encoding.dart (119) — `luaUrlEncode`, `lenientBase64Decode`, `urlsafeB64Urlencode/Urldecode`; shared with models/messages.dart |

## CONVENTIONS
- Two channel encodings, do not mix: the login_v3 payload is XXTEA + msgpack (via net/msgpack.dart), the chatpush WS channel is rotate-XOR + JSON. Each has its own file, and net/msgpack.dart holds both despite its name.
- Protocol constants (`kS7Alphabet`, `loginAuthKey`, `roomAuthKey`, `chatpushAuthKey`, `httpGetParamKey`, `xxteaKey`) live in protocol_keys.dart and are re-exported through md5_sign.dart.
- md5_sign.dart aggregates the sign chain (it depends on encoding.dart's `luaUrlEncode`) and is the module services import.
- Verify sign-chain edits against the golden tests before committing: `sign_golden_test.dart`, `s7_sign_test.dart`, `credential_cipher_test.dart`.
- This directory has no direct `package:mnchat/` importers; it is reached only via relative paths from services/ and storage/.

## ANTI-PATTERNS
- s7_sign.dart implements only the V1 fallback ("本客户端不参与那段握手"). Do not add a V2 handshake.
- The credential_cipher scheme is explicitly documented as "not bank-grade". Do not reuse it for anything beyond the one stored-password field.
- md5_sign.dart has one variant per endpoint family (`httpGetParamMd5`, `httpGetParamMd5RoomServer`, `httpGetS1`/`S2`, `httpGetS1GuardMap`, `httpGetRealNameMobileSum`). Do not collapse variants or reuse one key across families.
- Do not mix `xxteaKey` and `chatpushXorKey`: each channel has its own cipher and its own key constant.
- No `TODO`/`FIXME` markers exist in this chunk; a new one would be the first.
- A pinned-constant change here breaks signing silently — there is no server-side validation loop in this repo. Run `fvm flutter test` before committing any sign-chain change.
