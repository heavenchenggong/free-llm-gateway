# Troubleshooting（2026-09 实战踩坑全集）

## 安装阶段

### pip install 卡死 / 超慢
- 症状: `pip install 'litellm[proxy]'` 在下载大 wheel（如 polars_runtime 43MB）时僵死 20+ 分钟。
- 根因: 代理网络下 PyPI 直连极慢。
- 解法: `--only-binary :all:` + 清华镜像:
  ```bash
  pip install --only-binary :all: -i https://pypi.tuna.tsinghua.edu.cn/simple 'litellm[proxy]'
  ```
  镜像源实测 1 分钟搞定（曾卡 46 分钟）。镜像没有的包会回退，此时再去掉 -i 重试。

### pip 尝试现场编译 Rust / maturin 报错
- 根因: 某依赖无 arm64 wheel，pip 回退源码编译还要下载 Rust 工具链。
- 解法: `--only-binary :all:` 强制全部用预编译 wheel。

### 升级 litellm 后启动报 `cannot import name 'get_flat_dependant'`
- 根因: fastapi 0.141 删除了 `get_flat_dependant`，而 litellm 1.97.0 仍在用（其声明的
  依赖区间 `fastapi>=0.136.3` 上沿就是雷）。镜像源会装到最新 fastapi 触发。
- 解法:
  ```bash
  pip install 'fastapi==0.136.3' 'starlette>=1.0.1,<2.0'
  ```
- 附: 升级 litellm 主包后 proxy 依赖可能缺失（启动即退），需重装 `'litellm[proxy]==<版本>'`。

## 常驻阶段

### `launchctl bootstrap` 报 `5: Input/output error`
- 场景: 在 Agent/AI 工具的沙箱会话里执行（即使关闭沙箱限制也一样）；用户自己的
  Terminal 里同一 plist 一次通过。
- 根因: 调用方 session 权限，不是 plist 问题。
- 解法: 由用户在 Terminal 执行。脚本已内置降级（nohup 后台）并打印提示。

### `crontab` 报 `operation not permitted`
- 同上，沙箱会话内 cron 兜底也不可用。

### `nohup <venv>/bin/litellm ...` 报 `No such file or directory`
- 根因: 部分环境下 exec 带 shebang 的 console script 被拦（ENOENT 掩盖真实原因）。
- 解法: 显式解释器执行:
  ```bash
  nohup <venv>/bin/python <venv>/bin/litellm --config ... &
  ```
- 附: AI 工具会话内 spawn 的后台进程会在工具调用结束时被回收——长期常驻必须 launchd。

### launchd 注册成功但 KeepAlive 疑似不工作
- 验证方法: `kill <pid>` 后等 5-10 秒，`launchctl print gui/$UID/<label> | grep pid`
  应出现新 pid 且 `runs` 计数 +1。实测 6 秒内拉活。

## 运行阶段

### 某渠道 429 透传给了客户端
- 场景: 单次请求内连续撞多个渠道 429（OpenRouter 共享池 + SiliconFlow 同时限流），
  重试次数耗尽。
- 调参: `num_retries: 3` + `allowed_fails: 1` + `cooldown_time: 30`（一次失败即冷却 30s）。
  免费池固有现象，重发即可；免费渠道高峰期同时 429 属正常。

### 请求偶发 >90s 超时
- 根因: 某渠道响应慢但未到网关超时线。
- 调参: `request_timeout: 45`（streaming 不受影响，只管首包/停顿）。

### 池内模型质量/速度不稳定
- 根因: `simple-shuffle` 在健康渠道间随机分发，池内既有旗舰（Kimi K3）也有小模型
  （Qwen3.5-4B）。
- 解法: 按质量分池——`free-chat` 只留旗舰，另建 `free-fast` 池放小快模型。

### 客户端改了配置不生效
- WorkBuddy 等 GUI 客户端必须**完全退出**（含后台进程）再重开。

## Key 排查速查表

| 状态码 | 含义 | 动作 |
|---|---|---|
| 401 | key 错/拼错 | 逐字符比对（l/I/1、0/O 高发） |
| 403 | 权限/scope 缺失 | NVIDIA 查 "Public API Endpoints"；商汤查是否开通服务 |
| 410 | 模型 EOL | 换当前代模型（先拉 /v1/models 确认） |
| 429 | 限流 | 正常现象，靠网关冷却+切换消化 |
| 502/503 | 上游抖动 | 重试，OpenRouter 免费池常见 |
| 长时间零字节 | 托管侧未就绪 | 别反复重试该模型（如 NVIDIA glm-5.3-flash），标记跳过 |
