#!/usr/bin/env python3
"""Mini World MITM 抓包插件（mitmproxy addon）—— 抓并就地解码迷你世界流量。

用途：定位「道具仓库 / 礼物仓库持有数」这类客户端从服务端取的数据到底走哪个请求。
（背景：`/miniw/*` 没有返回道具背包的 act，账号数据只在主账号长连接上；
需要一份**正向对照**——游戏客户端自己发的那次请求长什么样。）

抓什么：
- HTTP(S)：`/miniw/*`、`/server/*`、`/admin/*`、`/minilb/*`、`/minigate/*`
  → 打印脱敏后的 URL、参数、响应体（按 `mn_max_body` 截断）。
- WebSocket：主账号长连接（XXTEA+msgpack）与 ChatPush gate（rotate-XOR+JSON）
  → 解码成结构化文本；解不开的帧存原始字节备离线分析。

用法：
    # 常规代理（HTTP(S) 需要把 mitmproxy CA 装到游戏设备/模拟器上）
    mitmdump -p 8080 -s tool/mitm/mnworld_mitm.py --set mn_capture=/tmp/mncap

    # 只抓主账号 WS 的反向代理（不用改 DNS / 不用装 CA）
    mitmdump --mode reverse:http://cn-logic10.mini1.cn:4011 -p 4011 \
             -s tool/mitm/mnworld_mitm.py --set mn_capture=/tmp/mncap
    # 客户端指向 ws://127.0.0.1:4011/（WsConnection.fetchS2(wsUrl:) /
    # MainAccountConnection.connect(wsUrl:) 都能直接传）

事后翻账本：grep -n "ItemInfo\\|道具\\|get_gift" /tmp/mncap/flows.jsonl

配置项：mn_capture（输出目录，默认 mncap）、mn_all（不过滤，默认 false）、
mn_max_body（body 上限，默认 4096）、mn_raw（所有 WS 帧都存原始字节，默认 false）。

凭据脱敏：URL query 与帧里的 s2/s2t/token/jwt/auth/loginauth/md5/passwd 一律打码。
"""

from __future__ import annotations

import json
import os
import re
import struct
import time
import zlib
from typing import Any

import msgpack
from mitmproxy import ctx, http

DELTA = 0x9E3779B9
XXTEA_KEY = bytes.fromhex("b48e6ef44ed13eee606141750e729cf4")
CHATPUSH_XOR_KEY = (18, 35, 52, 69)

MINI_HOST_SUFFIXES = ("mini1.cn", "miniworldplus.com", "miniworldgame.com")
INTERESTING_PATH_MARKERS = (
    "/miniw/",
    "/server/",
    "/admin/",
    "/client/",
    "/minilb/",
    "/minigate/",
    "/update/",
)
SECRET_KEYS = frozenset(
    {
        "s2",
        "s2t",
        "pure_s2t",
        "token",
        "jwt",
        "auth",
        "loginauth",
        "md5",
        "passwd",
        "password",
        "sign",
    }
)
# 心跳帧的 token/签名都是位置参数（`[0, seq, <jwt>]`、ack 里的 `s2_s2t`），没有键可打，只能按形状认。
JWT_RE = re.compile(r"^eyJ[A-Za-z0-9_-]{8,}\.[A-Za-z0-9_-]{8,}")
SIGN_RE = re.compile(r"^[0-9a-fA-F]{32}_\d{6,}$")


def _pack(data: bytes) -> bytes:
    packed = struct.pack(f">I{len(data)}s", len(data), data)
    if len(packed) % 4:
        packed += b"\x00" * (4 - len(packed) % 4)
    return packed


def _unpack(data: bytes) -> bytes:
    length = struct.unpack(">I", data[:4])[0]
    return data[4 : length + 4]


def _xxtea_decrypt(data: bytes, key: bytes) -> bytes:
    n = len(data) // 4
    if n < 2:
        return data
    v = list(struct.unpack(f"<{n}I", data))
    k = list(struct.unpack("<4I", key[:16]))
    rounds = 6 + 52 // n
    y = v[0]
    total = (rounds * DELTA) & 0xFFFFFFFF
    while total != 0:
        e = (total >> 2) & 3
        for p in range(n - 1, 0, -1):
            z = v[p - 1]
            mx = ((z >> 5 ^ y << 2) + (y >> 3 ^ z << 4)) ^ (
                (total ^ y) + (k[(p & 3) ^ e] ^ z)
            )
            v[p] = (v[p] - mx) & 0xFFFFFFFF
            y = v[p]
        z = v[n - 1]
        mx = ((z >> 5 ^ y << 2) + (y >> 3 ^ z << 4)) ^ (
            (total ^ y) + (k[(0 & 3) ^ e] ^ z)
        )
        v[0] = (v[0] - mx) & 0xFFFFFFFF
        y = v[0]
        total = (total - DELTA) & 0xFFFFFFFF
    return struct.pack(f"<{n}I", *v)


def xxtea_decrypt(data: bytes) -> bytes:
    return _unpack(_xxtea_decrypt(data, XXTEA_KEY))


def xxtea_decrypt_unzip(data: bytes) -> bytes:
    return zlib.decompress(_unpack(_xxtea_decrypt(data, XXTEA_KEY)))


def chatpush_decrypt(data: bytes) -> bytes:
    out = bytearray(len(data))
    for i, b in enumerate(data):
        x = (b ^ CHATPUSH_XOR_KEY[i % 4]) & 0xFF
        out[i] = ((x << 5) + (x >> 3)) & 0xFF
    return bytes(out)


def _msgpack_decode(raw: bytes) -> Any:
    try:
        return msgpack.unpackb(raw, strict_map_key=False, raw=False)
    except Exception:
        return msgpack.unpackb(raw, strict_map_key=False, raw=True)


def decode_ws_payload(content: bytes, chatpush: bool) -> tuple[Any, str] | None:
    if not content:
        return None
    if chatpush:
        try:
            return json.loads(chatpush_decrypt(content).decode("utf-8")), "chatpush"
        except Exception:
            return None
    for plain, tag in (
        (xxtea_decrypt, "xxtea+msgpack"),
        (xxtea_decrypt_unzip, "xxtea+zlib+msgpack"),
    ):
        try:
            raw = plain(content)
        except Exception:
            continue
        try:
            return _msgpack_decode(raw), tag
        except Exception:
            continue
    try:
        return json.loads(content.decode("utf-8")), "json"
    except Exception:
        return None


def redact(value: Any, depth: int = 0) -> Any:
    if depth > 12:
        return value
    if isinstance(value, dict):
        out: dict[Any, Any] = {}
        for k, v in value.items():
            if isinstance(k, str) and k.lower() in SECRET_KEYS and isinstance(v, (str, bytes)):
                s = v.decode("utf-8", "replace") if isinstance(v, bytes) else v
                out[k] = f"<redacted:{len(s)}B>"
            else:
                out[k] = redact(v, depth + 1)
        return out
    if isinstance(value, list):
        return [redact(v, depth + 1) for v in value]
    if isinstance(value, bytes):
        return f"<bin:{len(value)}B>"
    if isinstance(value, str):
        if JWT_RE.match(value):
            return f"<redacted:jwt {len(value)}B>"
        if SIGN_RE.match(value):
            return f"<redacted:sign {len(value)}B>"
    return value


def render(value: Any, max_len: int = 2000, depth: int = 0, limit: int = 24) -> str:
    if depth > 8:
        return "…"
    if isinstance(value, dict):
        items = list(value.items())
        body = ", ".join(
            f"{k}={render(v, max_len, depth + 1, limit)}" for k, v in items[:limit]
        )
        if len(items) > limit:
            body += f", …(+{len(items) - limit})"
        return "{" + body + "}"
    if isinstance(value, list):
        body = ", ".join(render(v, max_len, depth + 1, limit) for v in value[:limit])
        if len(value) > limit:
            body += f", …(+{len(value) - limit})"
        return "[" + body + "]"
    if isinstance(value, bytes):
        return f"<bin:{len(value)}B>"
    text = str(value)
    if len(text) > max_len:
        return text[:max_len] + f"…(+{len(text) - max_len})"
    return text


def redact_url(url: str) -> str:
    if "?" not in url:
        return url
    head, _, query = url.partition("?")
    parts = []
    for pair in query.split("&"):
        key, sep, val = pair.partition("=")
        if sep and key.lower() in SECRET_KEYS:
            parts.append(f"{key}=<redacted:{len(val)}>")
        else:
            parts.append(pair)
    return head + "?" + "&".join(parts)


class MiniWorldMITM:
    def __init__(self) -> None:
        self._fh = None
        self._ws_dir = ""

    def load(self, loader) -> None:
        loader.add_option(
            "mn_capture", str, "mncap", "抓包输出目录（flows.jsonl + ws/）"
        )
        loader.add_option("mn_all", bool, False, "true = 不过滤域名/路径")
        loader.add_option("mn_max_body", int, 4096, "body 最多记录多少字符")
        loader.add_option("mn_raw", bool, False, "true = 所有 WS 帧都存原始字节")

    def running(self) -> None:
        out_dir = ctx.options.mn_capture
        os.makedirs(out_dir, exist_ok=True)
        self._ws_dir = os.path.join(out_dir, "ws")
        os.makedirs(self._ws_dir, exist_ok=True)
        self._fh = open(os.path.join(out_dir, "flows.jsonl"), "a", encoding="utf-8")
        ctx.log.info(f"[mnworld] 账本：{os.path.abspath(self._fh.name)}")

    def done(self) -> None:
        if self._fh is not None:
            self._fh.close()
            self._fh = None

    def _record(self, rec: dict[str, Any]) -> None:
        rec.setdefault("ts", round(time.time(), 3))
        line = json.dumps(rec, ensure_ascii=False, default=str)
        if self._fh is not None:
            self._fh.write(line + "\n")
            self._fh.flush()
        ctx.log.info(f"[mnworld] {line}")

    def _interesting(self, host: str, path: str) -> bool:
        if ctx.options.mn_all:
            return True
        if any(host.endswith(s) for s in MINI_HOST_SUFFIXES):
            return True
        return any(m in path for m in INTERESTING_PATH_MARKERS)

    def _save_raw(self, content: bytes, tag: str) -> str:
        name = f"{int(time.time() * 1000)}-{tag}-{len(content)}B.bin"
        path = os.path.join(self._ws_dir, name)
        with open(path, "wb") as fh:
            fh.write(content)
        return path

    def request(self, flow: http.HTTPFlow) -> None:
        if flow.request.headers.get("upgrade", "").lower() == "websocket":
            self._record(
                {
                    "kind": "ws-open",
                    "url": redact_url(flow.request.pretty_url),
                    "headers": {
                        k: v
                        for k, v in flow.request.headers.items()
                        if k.lower() not in {"cookie", "authorization"}
                    },
                }
            )

    def response(self, flow: http.HTTPFlow) -> None:
        req, resp = flow.request, flow.response
        if resp is None:
            return
        host = req.pretty_host
        if not self._interesting(host, req.path):
            return
        cap = int(ctx.options.mn_max_body)
        try:
            text = resp.get_text(strict=False) or ""
        except Exception:
            text = ""
        if text:
            body: Any = text if len(text) <= cap else text[:cap] + f"…(+{len(text) - cap})"
        else:
            body = f"<bin:{len(resp.raw_content or b'')}B>"
        self._record(
            {
                "kind": "http",
                "method": req.method,
                "url": redact_url(req.pretty_url),
                "status": resp.status_code,
                "len": len(resp.raw_content or b""),
                "body": body,
            }
        )

    def websocket_message(self, flow: http.HTTPFlow) -> None:
        if flow.websocket is None or not flow.websocket.messages:
            return
        msg = flow.websocket.messages[-1]
        host = flow.request.pretty_host
        path = flow.request.path
        if not self._interesting(host, path):
            return
        chatpush = "/minigate/gate" in path or "chatpush" in host
        content = msg.content
        decoded = decode_ws_payload(content, chatpush=chatpush)
        rec: dict[str, Any] = {
            "kind": "ws",
            "dir": "c->s" if msg.from_client else "s->c",
            "url": redact_url(flow.request.pretty_url),
            "len": len(content),
        }
        if decoded is not None:
            value, codec = decoded
            rec["codec"] = codec
            rec["msg"] = redact(value)
            ctx.log.alert(
                f"[mnworld] ws {rec['dir']} {codec} "
                f"{render(redact(value), max_len=600)}"
            )
        else:
            rec["codec"] = "raw"
            rec["head_hex"] = content[:32].hex()
            ctx.log.warn(f"[mnworld] ws {rec['dir']} 解不开（{len(content)}B），原始帧存盘")
        if ctx.options.mn_raw or decoded is None:
            rec["raw_file"] = self._save_raw(
                content, "c2s" if msg.from_client else "s2c"
            )
        self._record(rec)


addons = [MiniWorldMITM()]
