#!/bin/bash
# free-llm-gateway 功能验证脚本
# 用法: bash verify.sh   （环境变量 GATEWAY_PORT 可改端口，默认 4010）

set -u
PORT="${GATEWAY_PORT:-4010}"
BASE="http://127.0.0.1:$PORT"
PASS=0; FAIL=0

check() { # $1=名称 $2=期望grep $3=实际输出
  if echo "$3" | grep -q "$2"; then
    echo "✅ $1"; PASS=$((PASS+1))
  else
    echo "❌ $1"; echo "   响应: $(echo "$3" | head -c 200)"; FAIL=$((FAIL+1))
  fi
}

echo "── 1. models 列表 ──"
R=$(curl -sS --noproxy '*' -m 5 "$BASE/v1/models" -H "Authorization: Bearer free" 2>&1)
check "models 200 且含 free-chat" '"free-chat"' "$R"

echo "── 2. chat 请求 ──"
R=$(curl -sS --noproxy '*' -m 120 "$BASE/v1/chat/completions" \
  -H "Content-Type: application/json" -H "Authorization: Bearer free" \
  -d '{"model":"free-chat","messages":[{"role":"user","content":"reply with exactly: ok"}],"max_tokens":300}' 2>&1)
check "chat 返回 choices" '"choices"' "$R"

echo "── 3. tool calling 透传 ──"
R=$(curl -sS --noproxy '*' -m 120 "$BASE/v1/chat/completions" \
  -H "Content-Type: application/json" -H "Authorization: Bearer free" \
  -d '{"model":"free-chat","messages":[{"role":"user","content":"上海天气如何"}],"max_tokens":300,"tools":[{"type":"function","function":{"name":"get_weather","description":"查询天气","parameters":{"type":"object","properties":{"city":{"type":"string"}},"required":["city"]}}}]}' 2>&1)
check "返回 tool_calls" 'tool_calls' "$R"

echo "── 4. embeddings（如配置了 free-embed）──"
R=$(curl -sS --noproxy '*' -m 60 "$BASE/v1/embeddings" \
  -H "Content-Type: application/json" -H "Authorization: Bearer free" \
  -d '{"model":"free-embed","input":"hello world"}' 2>&1)
if echo "$R" | grep -q '"embedding"'; then
  echo "✅ embeddings 正常"; PASS=$((PASS+1))
elif echo "$R" | grep -qi "not found\|doesn't exist\|no deployed"; then
  echo "⏭️  未配置 free-embed，跳过"; 
else
  echo "❌ embeddings 异常"; echo "   响应: $(echo "$R" | head -c 200)"; FAIL=$((FAIL+1))
fi

echo ""
echo "结果: $PASS 通过 / $FAIL 失败"
[ "$FAIL" = "0" ] && echo "🎉 全部通过" || echo "排障见 skill 的 references/troubleshooting.md"
exit "$FAIL"
