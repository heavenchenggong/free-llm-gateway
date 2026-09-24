#!/bin/bash
# free-llm-gateway 一键安装脚本（macOS）
# 用法:
#   bash setup_gateway.sh                    # 交互式（逐渠道询问 key，回车跳过）
#   BIGMODEL_API_KEY=xxx ... bash setup_gateway.sh --non-interactive
#   bash setup_gateway.sh --force            # 覆盖已有 config.yaml
# 环境变量: GATEWAY_HOME(默认 ~/.free-llm-gateway) GATEWAY_PORT(默认 4010)
#           BIGMODEL_API_KEY OPENROUTER_API_KEY SILICONFLOW_API_KEY NVIDIA_API_KEY
#           AGNES_API_KEY SENSENOVA_API_KEY DOTS_API_KEY PIP_INDEX_URL

set -u

GATEWAY_HOME="${GATEWAY_HOME:-$HOME/.free-llm-gateway}"
PORT="${GATEWAY_PORT:-4010}"
LABEL="com.free-llm-gateway"
SKILL_DIR="$(cd "$(dirname "$0")/.." && pwd)"
NON_INTERACTIVE=0
FORCE=0
for arg in "$@"; do
  [ "$arg" = "--non-interactive" ] && NON_INTERACTIVE=1
  [ "$arg" = "--force" ] && FORCE=1
done

VENV="$GATEWAY_HOME/venv"
CONFIG="$GATEWAY_HOME/config.yaml"
LOG="$GATEWAY_HOME/gateway.log"
PLIST="$HOME/Library/LaunchAgents/$LABEL.plist"
PIP_INDEX="${PIP_INDEX_URL:-https://pypi.tuna.tsinghua.edu.cn/simple}"

log()  { echo "→ $*"; }
ok()   { echo "✅ $*"; }
warn() { echo "⚠️  $*"; }
die()  { echo "❌ $*"; exit 1; }

health() {
  curl -sS --noproxy '*' -m 3 -o /dev/null -w '%{http_code}' \
    "http://127.0.0.1:$PORT/v1/models" -H "Authorization: Bearer free" 2>/dev/null
}

mkdir -p "$GATEWAY_HOME"

# ---------- 0. 已在运行则只提示 ----------
if [ "$(health)" = "200" ] && [ "$FORCE" = "0" ]; then
  ok "网关已在运行 (http://127.0.0.1:$PORT/v1)，如需重装配置加 --force"
  exit 0
fi

# ---------- 1. python3 ----------
command -v python3 >/dev/null || die "未找到 python3，请先安装 Python 3.10+"
log "Python: $(python3 --version)"

# ---------- 2. venv + 安装 LiteLLM ----------
if [ ! -x "$VENV/bin/python" ]; then
  log "创建 venv: $VENV"
  python3 -m venv "$VENV" || die "venv 创建失败"
fi
PIP="$VENV/bin/pip"
if ! "$VENV/bin/python" -c "import litellm" 2>/dev/null; then
  log "安装 litellm[proxy]（仅预编译 wheel + 镜像源，首次约 2-5 分钟）..."
  "$PIP" install --only-binary :all: -i "$PIP_INDEX" 'litellm[proxy]' >>"$LOG" 2>&1 \
    || "$PIP" install --only-binary :all: 'litellm[proxy]' >>"$LOG" 2>&1 \
    || die "安装失败，详见 $LOG（代理网络建议保留清华镜像）"
  # fastapi>=0.141 删除了 get_flat_dependant，litellm 1.97.0 必崩，钉回兼容版本
  log "钉 fastapi==0.136.3（规避 litellm ImportError）..."
  "$PIP" install -i "$PIP_INDEX" 'fastapi==0.136.3' 'starlette>=1.0.1,<2.0' >>"$LOG" 2>&1 \
    || warn "fastapi 钉版本失败，启动若报 get_flat_dependant ImportError 请手动执行: $PIP install 'fastapi==0.136.3'"
fi
ok "LiteLLM 就绪: $("$VENV/bin/litellm" --version 2>/dev/null | tail -1)"

# ---------- 3. 收集 key ----------
ask_key() { # $1=渠道名 $2=env变量名 $3=说明  → 回显到 $KEY
  KEY=""
  if [ -n "${!2:-}" ]; then KEY="${!2}"; return; fi
  if [ "$NON_INTERACTIVE" = "1" ]; then return; fi
  printf "  %s key（%s，回车跳过）: " "$1" "$3"
  read -r KEY
}

# ---------- 4. 生成 config.yaml ----------
if [ -f "$CONFIG" ] && [ "$FORCE" = "0" ]; then
  log "config.yaml 已存在，跳过生成（--force 可覆盖）"
else
  log "生成 $CONFIG（逐渠道询问，回车=跳过该渠道）"
  CFG="$GATEWAY_HOME/config.yaml.tmp"
  : > "$CFG"
  cat >> "$CFG" <<'YAML'
model_list:
YAML

  add_chat() { # $1=model $2=api_base $3=key $4=extra_headers_yaml(可空)
    cat >> "$CFG" <<EOF
  - model_name: free-chat
    litellm_params:
      model: openai/$1
      api_base: $2
      api_key: $3
$4
EOF
  }
  add_vision() { # $1=model $2=api_base $3=key $4=extra_headers_yaml(可空)
    cat >> "$CFG" <<EOF
  - model_name: free-vision
    litellm_params:
      model: openai/$1
      api_base: $2
      api_key: $3
$4
EOF
  }

  echo "—— 渠道 key（免费注册地址见 references/channels.md）——"

  ask_key "智谱BigModel" BIGMODEL_API_KEY "open.bigmodel.cn"
  if [ -n "${KEY:-}" ]; then
    add_chat "GLM-4.7-Flash" "https://open.bigmodel.cn/api/paas/v4" "$KEY" ""
    add_vision "glm-4.6v-flashx" "https://open.bigmodel.cn/api/paas/v4" "$KEY" ""
  fi

  ask_key "OpenRouter" OPENROUTER_API_KEY "openrouter.ai（一个 key 带 3 个模型）"
  if [ -n "${KEY:-}" ]; then
    add_chat "z-ai/glm-5.2:free" "https://openrouter.ai/api/v1" "$KEY" ""
    add_chat "nvidia/nemotron-3.5-lightning:free" "https://openrouter.ai/api/v1" "$KEY" ""
    add_chat "inclusionai/ling-3.0-flash-fin:free" "https://openrouter.ai/api/v1" "$KEY" ""
    cat >> "$CFG" <<EOF
  - model_name: free-embed
    litellm_params:
      model: openai/liquid/lfm-2.5-embedding-350m:free
      api_base: https://openrouter.ai/api/v1
      api_key: $KEY
EOF
  fi

  ask_key "SiliconFlow" SILICONFLOW_API_KEY "siliconflow.cn"
  if [ -n "${KEY:-}" ]; then
    add_chat "Qwen/Qwen3.5-4B" "https://api.siliconflow.cn/v1" "$KEY" ""
    add_vision "Qwen/Qwen3.5-4B" "https://api.siliconflow.cn/v1" "$KEY" ""
  fi

  ask_key "NVIDIA" NVIDIA_API_KEY "build.nvidia.com（建 key 务必勾 Public API Endpoints scope）"
  if [ -n "${KEY:-}" ]; then
    add_chat "moonshotai/kimi-k3" "https://integrate.api.nvidia.com/v1" "$KEY" ""
    add_chat "openai/gpt-oss-20b" "https://integrate.api.nvidia.com/v1" "$KEY" ""
    add_chat "nvidia/nemotron-3.5-lightning-30b-a3b" "https://integrate.api.nvidia.com/v1" "$KEY" ""
  fi

  ask_key "Agnes AI" AGNES_API_KEY "agnes-ai.com"
  [ -n "${KEY:-}" ] && add_chat "agnes-2.5-flash" "https://apihub.agnes-ai.com/v1" "$KEY" ""

  ask_key "SenseNova" SENSENOVA_API_KEY "platform.sensenova.cn"
  [ -n "${KEY:-}" ] && add_chat "sensenova-6.8-flash-lite" "https://token.sensenova.cn/v1" "$KEY" ""

  ask_key "dots.ai" DOTS_API_KEY "askdiandian.com（注意域名是 diandian）"
  if [ -n "${KEY:-}" ]; then
    HDR="      extra_headers:\n        api-key: $KEY"
    add_chat "dots3-note-prev" "https://note3-prev-api.askdiandian.com/v1" "$KEY" "$HDR"
    add_vision "dots3-note-prev" "https://note3-prev-api.askdiandian.com/v1" "$KEY" "$HDR"
  fi

  cat >> "$CFG" <<'YAML'

litellm_settings:
  drop_params: true        # 渠道不支持的参数直接丢弃
  num_retries: 3           # 单次请求内最多跨渠道重试 3 次
  request_timeout: 45      # 单渠道 45s 无首包就切下一个（streaming 不受影响）
  set_verbose: false

router_settings:
  routing_strategy: simple-shuffle   # 健康渠道间分散，降低单渠道限流概率
  cooldown_time: 30        # 渠道失败后冷却 30s
  allowed_fails: 1         # 一次失败即冷却
  retry_after: 3
YAML

  grep -q "model_name" "$CFG" || die "一个 key 都没配，无法生成配置。至少注册一个渠道（见 references/channels.md）"
  mv "$CFG" "$CONFIG"
fi
chmod 600 "$CONFIG"
ok "配置文件: $CONFIG"

# ---------- 5. launchd 常驻 ----------
log "注册 launchd 常驻服务 ($LABEL)..."
cat > "$PLIST" <<EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>Label</key><string>$LABEL</string>
    <key>ProgramArguments</key>
    <array>
        <string>$VENV/bin/python</string>
        <string>$VENV/bin/litellm</string>
        <string>--config</string><string>$CONFIG</string>
        <string>--host</string><string>127.0.0.1</string>
        <string>--port</string><string>$PORT</string>
    </array>
    <key>RunAtLoad</key><true/>
    <key>KeepAlive</key><true/>
    <key>StandardOutPath</key><string>$LOG</string>
    <key>StandardErrorPath</key><string>$LOG</string>
    <key>EnvironmentVariables</key>
    <dict><key>HOME</key><string>$HOME</string></dict>
</dict>
</plist>
EOF

if launchctl print "gui/$(id -u)/$LABEL" >/dev/null 2>&1; then
  launchctl kickstart -k "gui/$(id -u)/$LABEL" && ok "已有服务已重启"
elif launchctl bootstrap "gui/$(id -u)" "$PLIST" 2>/dev/null; then
  ok "launchd 注册成功（开机自启 + 崩溃自动重启）"
else
  warn "launchd 注册失败（Agent/沙箱会话常见）。降级为后台常驻；"
  warn "建议稍后在自己的 Terminal 里重跑本脚本以启用开机自启。"
  nohup "$VENV/bin/python" "$VENV/bin/litellm" --config "$CONFIG" \
    --host 127.0.0.1 --port "$PORT" >> "$LOG" 2>&1 &
  disown 2>/dev/null
fi

# ---------- 6. 健康检查 + 功能验证 ----------
log "等待网关就绪..."
CODE=""
for i in $(seq 1 45); do
  CODE=$(health)
  [ "$CODE" = "200" ] && break
  sleep 2
done
[ "$CODE" = "200" ] || { tail -8 "$LOG"; die "网关未就绪，日志见 $LOG"; }
ok "网关就绪: http://127.0.0.1:$PORT/v1"

log "发送真实 chat 请求验证..."
RESP=$(curl -sS --noproxy '*' -m 90 "http://127.0.0.1:$PORT/v1/chat/completions" \
  -H "Content-Type: application/json" -H "Authorization: Bearer free" \
  -d '{"model":"free-chat","messages":[{"role":"user","content":"reply with exactly: ok"}],"max_tokens":300}' 2>&1)
echo "$RESP" | grep -q '"choices"' \
  && ok "chat 验证通过（池内 $(grep -c 'model_name: free-chat' "$CONFIG") 个渠道）" \
  || { echo "$RESP" | head -c 300; warn "chat 验证未通过，检查上方响应与 $LOG"; }

echo ""
echo "════════════════════════════════════════════"
echo " 客户端配置（WorkBuddy: 设置 → 模型管理 → 自定义模型）"
echo "   提供商:   Custom / OpenAI 兼容"
echo "   接口地址: http://127.0.0.1:$PORT/v1"
echo "   API Key:  free（任意）"
echo "   模型 ID:  free-chat / free-vision / free-embed"
echo "   高级:     勾选「工具调用」；保存后完全退出客户端重开"
echo "════════════════════════════════════════════"
