# free-llm-gateway

本地 LiteLLM 网关，把多个免费 LLM API 渠道聚合成一个 OpenAI 兼容端点——任一渠道
限流（429）、超时或报错时自动冷却 30 秒并切换下一个，客户端只配一个模型。

[English] A local LiteLLM gateway that aggregates multiple free LLM API providers
(Zhipu BigModel, SiliconFlow, OpenRouter, NVIDIA NIM, Agnes AI, SenseNova, dots.ai)
behind one OpenAI-compatible endpoint with automatic failover on 429/timeout.

## 它解决什么问题

免费渠道各自单独配在客户端里，一个限流就要手动换模型。装了这个网关：

```
客户端（只配一个模型）
   → 本地网关 http://127.0.0.1:4010/v1
      → 渠道A / 渠道B / 渠道C ...（失败自动冷却并切换）
```

## 快速开始

```bash
# 1. 拿 key（2-3 个渠道即可起步，注册直达链接见 references/channels.md）

# 2. 一键安装（macOS，Terminal 里跑）
bash scripts/setup_gateway.sh

# 3. 验证
bash scripts/verify.sh

# 4. 客户端配置（WorkBuddy / Claude Code / 任意 OpenAI 兼容工具）
#    接口地址: http://127.0.0.1:4010/v1
#    API Key:  free（任意非空）
#    模型 ID:  free-chat / free-vision / free-embed
```

## 安装为 WorkBuddy / Claude Code skill

把整个目录放进 `~/.workbuddy/skills/`（WorkBuddy）或 `~/.claude/skills/`（Claude Code），
对话里说"帮我装免费模型网关"即可触发。

## 文档

| 文件 | 内容 |
|---|---|
| `SKILL.md` | 安装/配置主流程 + 自动化边界 |
| `references/channels.md` | 7 家免费渠道注册直达链接、模型 ID、每家的坑 |
| `references/troubleshooting.md` | 安装/常驻/运行三阶段踩坑全集 + 状态码速查 |

## 已知限制

- launchd 常驻注册需在用户自己的 Terminal 执行（Agent/沙箱会话会被系统拒绝，脚本会自动降级并提示）
- 免费渠道高峰期可能多个同时 429，重试耗尽后单次请求仍可能失败——重发即可
- 各平台免费政策变动频繁（2026-09 口径），接入前先用真实 chat 请求验证 key

## License

MIT
