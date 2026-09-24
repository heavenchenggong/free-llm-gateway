# 免费渠道清单（注册直达 + 模型 ID + 已知坑）

> 更新于 2026-09。免费政策变动频繁，接入前务必先用真实 chat 请求验证（不是只拉 models 列表）。

## 智谱 BigModel

- 注册: https://open.bigmodel.cn （免费 GLM-Flash 系列额度）
- Key 页: 控制台 → API Keys
- 模型: `GLM-4.7-Flash`（文本）、`glm-4.6v-flashx`（视觉）
- 坑: 无特殊认证头，标准 Bearer。GLM 默认输出带 `reasoning_content`，正常现象。

## OpenRouter（免费共享池）

- 注册: https://openrouter.ai
- Key 页: https://openrouter.ai/settings/keys
- 模型（`:free` 后缀 = 免费共享池）: `z-ai/glm-5.2:free`、`nvidia/nemotron-3.5-lightning:free`、
  `inclusionai/ling-3.0-flash-fin:free`、`liquid/lfm-2.5-embedding-350m:free`（embedding）
- 坑: 共享池高峰期 429 频繁——这正是需要多渠道池的原因；502 属上游抖动，重试即可。
- Key 常以 `export OPENROUTER_API_KEY=...` 形式存在 `~/.zshrc`，可 `source ~/.zshrc` 后取。

## SiliconFlow 硅基流动

- 注册: https://siliconflow.cn
- 模型: `Qwen/Qwen3.5-4B`（文本+视觉）
- 坑: 并发限制较严，池中当补充渠道合适，别当唯一渠道。

## NVIDIA NIM（build.nvidia.com）

- 注册: https://build.nvidia.com （邮箱即可，2026 起免费政策为 ~40 rpm 限流，非 credit 制）
- Key 页: https://build.nvidia.com/settings/api-keys
- 模型（2026-09 实测可用）: `moonshotai/kimi-k3`、`openai/gpt-oss-20b`、
  `nvidia/nemotron-3.5-lightning-30b-a3b`、`nvidia/nemotron-3-nano-omni-30b-a3b-reasoning`
- 实测不可用: `z-ai/glm-5.3-flash`、`deepseek-ai/deepseek-v4.1-flash`（180s 零字节，托管侧问题）
- 🔴 两个大坑:
  1. **建 key 必须勾选 "Public API Endpoints" scope**——缺此 scope 的 key 能列全模型目录，
     但所有推理请求 403 Authorization failed，极易误判成"额度用完"。
  2. 模型回收频繁：不少 llama/deepseek 老模型已 EOL（请求返 410 Gone）。接入前用
     `/v1/models` 确认模型 ID 还在；但 models 列表 ≠ 可调用，仍需真实 chat 验证。

## Agnes AI

- 注册: https://agnes-ai.com → 控制台 https://platform.agnes-ai.com （Google/GitHub 登录）
- Key 页: Settings → API Keys（key 只在创建时显示一次）
- Base URL: **`https://apihub.agnes-ai.com/v1`**（官方口径；`api.agnes-ai.cn` 是偏门镜像，
  报"无效的令牌"不代表 key 坏）
- 模型: `agnes-2.5-flash`

## SenseNova 商汤日日新

- 注册: https://platform.sensenova.cn （手机号）
- Key 页: https://platform.sensenova.cn/console/keys （最多 20 个 key）
- Base URL: **`https://token.sensenova.cn/v1`**（旧路径 `api.sensenova.cn/compatible-mode` 会 Forbidden）
- 模型: `sensenova-6.8-flash-lite`
- 坑: Forbidden 还可能是账号未开通服务；2026-08-28 起启用双积分制（通用积分 +
  Flash-Lite 专属积分），注意额度页口径。

## dots.ai（点点）

- 注册: https://dots.ai
- Base URL: **`https://note3-prev-api.askdiandian.com/v1`**（域名是 askdiandian「点点」，
  极易误读成 askdianidian）
- 模型: `dots3-note-prev`（文本+视觉）
- 🔴 坑: **认证头是 `api-key: <key>`，不是标准 Bearer**；但同时带 Authorization 头可容忍。
  LiteLLM 配置需加:
  ```yaml
  extra_headers:
    api-key: <key>
  ```
- 偶发 403 "Request processing error" 为瞬时故障，重试即恢复。

## 通用注意事项

1. **key 转录**：从截图抄 key 极易混淆 `l/I/1`、`0/O`——优先复制文本或导出 key 文件。
   曾有案例"换新 key 后好了"，逐字符对比发现新旧 key 仅差 2 个易混字符，根因是抄写错位。
2. **验证姿势**：`GET /v1/models` 多数平台不校验推理权限，只能证明 key 格式对；
   必须发一条 max_tokens 较小的真实 chat 才算数。
3. 拼接类 key（截图分两屏）先拼好再验，401 = 拼错，410 = 模型 EOL，403 = 权限/scope，
   429 = 限流（换渠道重试）。
