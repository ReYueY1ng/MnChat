# MnChat

迷你世界（Mini World）外部聊天客户端 — Flutter/Dart 实现。

支持 Linux 桌面与 Android（另有 Windows runner），**不支持 Web**（已移除）。

## 功能

- **登录**：`login_v3` 协议（端口池随机负载均衡）+ WebSocket 心跳取 s2/s2t 令牌
- **好友聊天**：实时推送 + 离线历史拉取（buddysvr chat_query）
- **群聊**：实时推送 + 缓存历史
- **离线缓存**：Drift SQLite 本地持久化，启动即恢复（多账号数据隔离）
- **头像与头像框**：网络头像 + 内存/磁盘 LRU 缓存（按用途独立配额）、静态与动画头像框
- **社交**：动态（发布/详情/通知）、家族、伙伴、称号、访客、黑名单
- **消息与资料**：邮件（msg_box）、玩家主页、二维码名片、富文本 / 表情
- **通知**：Android 前台服务常驻通知、Linux DBus 通知；按会话聚合、点击直达会话
- **桌面集成**：系统托盘（关闭到托盘）
- **应用锁**：PIN 解锁
- **数据**：聊天记录导出 / 合并导入（JSON）
- **协议**：XXTEA + rotate-XOR 加密、LuaTable 响应解析、msgpack 编解码

## 技术栈

- Flutter 3.47.2（FVM，见 `.fvmrc`）
- Riverpod 3.x 状态管理
- Drift 离线存储（SQLite，schema v9；热点查询已建索引）
- Dio + `web_socket_channel` 通信
- `material_ui`（Flutter 官方从框架拆出的独立 Material 库）+ `flutter_chat_ui` 2.12.0

## 构建与检查

```sh
fvm flutter pub get
fvm flutter analyze      # 基线：0 error / 0 warning
fvm flutter test         # 基线：全部通过
fvm flutter run -d linux # 或： fvm flutter build apk
```

CI（`.github/workflows/ci.yml`）在推送 / PR 时跑 `analyze` + `test`；
Flutter 版本取自 `.fvmrc`。注意当前 `origin` 为自建服务器，该 workflow
仅在推送到 GitHub 镜像时生效。

## 安全模型

- **保存的账号密码**：AES-CBC + 随机 IV + HMAC-SHA256 认证标签加密后落盘，
  密钥由固定盐与账号 uin 派生。目标是「数据库文件被读取 / 备份泄露时密码不明文可见」。
- **应用锁 PIN**：加盐哈希存储，绝不保存明文。
- 明确的局限：这是客户端逆向项目，**能拿到源码的攻击者总能提取密钥**，
  因此不是防 root / 调试器的银行级安全。

## 已知限制

- 仅支持口令登录，不支持微信 / QQ 登录
- 平台：不支持 Web / iOS / macOS
- 生产服务器需直连（请自行配置网络代理）
