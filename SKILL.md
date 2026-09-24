---
name: free-llm-gateway
description: |
  在 macOS 上一键搭建本地 LiteLLM 网关，把多个免费 LLM API 渠道（智谱 BigModel、
  SiliconFlow、OpenRouter、NVIDIA NIM、Agnes AI、SenseNova、dots.ai 等）聚合为一个
  OpenAI 兼容端点。任一渠道限流（429）、超时或报错时自动冷却并切换到下一个渠道，
  客户端（WorkBuddy / Claude Code / 任意 OpenAI 兼容工具）只需配置一个模型。
  This skill should be used when 用户要求"免费模型自动切换""多免费渠道聚合""限流
  自动换渠道""本地 LLM 网关"，或需要安装/配置/排障 LiteLLM proxy、编写渠道配置、
  注册 launchd 常驻服务。
version: 1.0.0
agent_created: true
---

# 免费 LLM 渠道聚合网关（LiteLLM）

把多个免费 LLM 渠道聚合成一个本地 OpenAI 兼容端点。架构：

```
客户端（只配一个模型）
   → 本地 LiteLLM 网关 http://127.0.0.1:<port>/v1
      → 渠道A / 渠道B / 渠道C ...（429/超时自动冷却 30s 并切换）
```

## 自动化边界（先读）

| 环节 | 能否自动化 | 说明 |
|---|---|---|
| 创建 venv + 安装 LiteLLM | ✅ `scripts/setup_gateway.sh` | 含清华镜像 + 仅预编译 wheel + fastapi 钉版本 |
| 生成 config.yaml | ✅ 同上 | 交互式询问各渠道 key，留空即跳过该渠道 |
| launchd 常驻注册 | ⚠️ 半自动 | 脚本会尝试注册；**在 Agent/沙箱会话里必失败**，需用户在 Terminal 重跑 |
| 各平台注册账号、拿 API key | ❌ 手工 | 每家平台各自注册，见 `references/channels.md`（含直达链接与坑） |
| 客户端（WorkBuddy）图形界面配置 | ❌ 手工 | 4 个字段照抄，见下文「客户端配置」 |

## 快速路径（推荐顺序）

### 1. 拿 key（手工，约 10 分钟）

打开 `references/channels.md`，按渠道清单逐个注册并复制 API key。
最少配 2-3 个渠道即可起步；key 拿到后**以文本方式粘贴保存**（截图转录易混淆 l/I/1）。

### 2. 一键安装（Terminal 里跑）

```bash
bash <skill目录>/scripts/setup_gateway.sh
```

脚本行为：建 venv → 装 `litellm[proxy]`（仅 wheel + 清华镜像）→ 钉 fastapi 版本 →
交互式询问各渠道 key（回车跳过）→ 生成 `~/.free-llm-gateway/config.yaml`（600 权限）→
写 launchd plist 并尝试注册 → 健康检查 → 发一条真实 chat 验证。

也支持非交互模式（CI/脚本场景）：

```bash
BIGMODEL_API_KEY=xxx OPENROUTER_API_KEY=yyy bash setup_gateway.sh --non-interactive
```

### 3. 验证

```bash
bash <skill目录>/scripts/verify.sh
```

依次检查：models 列表 200 / chat 请求 / tool calling 透传 / embeddings。
任何一项 FAIL 时，按 `references/troubleshooting.md` 对应条目排障。

### 4. 客户端配置（以 WorkBuddy 为例，手工）

设置 ⚙ → 模型管理 → 自定义模型 → 添加模型：

| 字段 | 值 |
|---|---|
| 提供商 | Custom / OpenAI 兼容 |
| 接口地址 | `http://127.0.0.1:4010/v1`（必须带 `/v1`） |
| API Key | 任意非空字符串（网关不校验） |
| 模型 ID | `free-chat`（文本）/ `free-vision`（带图）/ `free-embed`（向量） |
| 高级选项 | 勾选「工具调用」 |

保存后**完全退出客户端再重开**（后台进程也退）才生效。

## 渠道运维

- **加渠道 / 换 key**：编辑 `~/.free-llm-gateway/config.yaml`（同名 `model_name` 重复
  N 次 = 一个故障转移池），然后 `launchctl kickstart -k gui/$(id -u)/com.free-llm-gateway`
  或重跑 setup 脚本（已检测到服务存在时只重启不重装）。
- **看某次请求实际走了哪个渠道**：`tail ~/.free-llm-gateway/gateway.log`。
- **接渠道前必做**：用真实 chat 请求验证 key（不是只拉 `/v1/models`——NVIDIA 的 key
  能列全模型但缺 "Public API Endpoints" scope 时推理全 403）。渠道模型会 EOL，
  接入前确认模型 ID 仍有效。

## 已知坑速查（详见 references/troubleshooting.md）

1. `pip install litellm[proxy]` 走默认源会卡死大 wheel → 必须 `--only-binary :all:`
   + 清华镜像。
2. fastapi ≥0.141 删除 `get_flat_dependant`，litellm 1.97.0 会 ImportError →
   钉 `fastapi==0.136.3`。
3. Agent/沙箱会话内 `launchctl bootstrap` 恒报 `5: Input/output error`，`crontab`
   报 operation not permitted → 常驻注册必须由用户在 Terminal 执行。
4. `nohup <venv>/bin/<console-script>` 可能报 ENOENT → 改用
   `nohup <venv>/bin/python <venv>/bin/<script>`。
5. dots.ai 认证头是 `api-key:` 不是 Bearer（同时带 Authorization 可容忍）。
6. NVIDIA 免费政策 2026 起为 ~40 rpm 限流（非 credit 制）；glm-5.3-flash 等模型
   托管侧未就绪时会 180s 零字节——超时 ≠ 限流，别反复重试。
