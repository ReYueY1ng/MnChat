# MnChat

迷你世界（Mini World）外部聊天客户端 — Flutter/Dart 实现。

## 功能

- **HTTP 登录**：`login_v3` 协议 + WebSocket 心跳取 s2/s2t 令牌
- **好友聊天**：实时推送 + 离线历史拉取（buddysvr chat_query）
- **群聊**：实时推送 + 缓存历史
- **离线缓存**：Drift SQLite 本地持久化，启动恢复
- **协议**：XXTEA + rotate-XOR 加密、LuaTable 响应解析、msgpack 编解码

## 技术栈

- Flutter 3.47 (FVM)
- Riverpod 3.x 状态管理
- Drift 离线存储
- Dio + WebSocket 通信

## 已知限制

- 仅支持口令登录，不支持微信/QQ 登录
- 头像暂用首字占位（批量拉取接口存在但依赖好友列表接口稳定）
- 生产服务器需直连（已禁用系统代理）
