#!/bin/bash
# ============================================================================
# goosed agent 离线验证脚本
# 模拟 Gateway 的 InstanceManager 启动方式，测试模型是否通
#
# 用法:
#   bash test-goosed.sh --api-key <KEY> --host <URL> --model <MODEL>
#   bash test-goosed.sh --api-key abc --host http://10.0.0.1:8000/v1 --model qwen3-32b
#   bash test-goosed.sh --api-key abc --host https://open.bigmodel.cn/api/anthropic --model glm-5.1 --engine anthropic
#
# 也可用环境变量:
#   GOOSE_API_KEY=xxx GOOSE_HOST=xxx GOOSE_MODEL=xxx bash test-goosed.sh
#
# 参数:
#   --api-key   API Key (必需)
#   --host      模型服务地址 (必需)
#   --model     模型名称 (必需)
#   --engine    协议引擎 (openai/anthropic, 默认: openai)
#   --message   测试消息 (可选, 默认 "hello")
#   --help      显示帮助
# ============================================================================
set -e

# ---------------------------------------------------------------------------
# 默认值
# ---------------------------------------------------------------------------
ENGINE="${GOOSE_ENGINE:-openai}"
MODEL="${GOOSE_MODEL:-}"
HOST="${GOOSE_HOST:-}"
API_KEY="${GOOSE_API_KEY:-}"
MESSAGE="${GOOSE_TEST_MESSAGE:-hello}"

# ---------------------------------------------------------------------------
# 解析参数
# ---------------------------------------------------------------------------
show_help() {
    echo "用法: bash test-goosed.sh --api-key <KEY> --host <URL> --model <MODEL> [选项]"
    echo ""
    echo "必需参数:"
    echo "  --api-key <KEY>     API Key"
    echo "  --host <URL>        模型服务地址"
    echo "  --model <MODEL>     模型名称"
    echo ""
    echo "可选参数:"
    echo "  --engine <TYPE>     协议引擎 (openai/anthropic, 默认: openai)"
    echo "  --message <TEXT>    测试消息 (默认: hello)"
    echo ""
    echo "示例:"
    echo "  # 内网 OpenAI 兼容模型"
    echo "  bash test-goosed.sh --api-key mykey --host http://10.0.0.1:8000/v1 --model qwen3-32b"
    echo ""
    echo "  # GLM (Anthropic 兼容)"
    echo "  bash test-goosed.sh --api-key mykey --host https://open.bigmodel.cn/api/anthropic --model glm-5.1 --engine anthropic"
    echo ""
    echo "  # 环境变量方式"
    echo "  GOOSE_API_KEY=xxx GOOSE_HOST=http://10.0.0.1:8000/v1 GOOSE_MODEL=qwen3-32b bash test-goosed.sh"
    exit 0
}

while [ $# -gt 0 ]; do
    case "$1" in
        --api-key)  API_KEY="$2";  shift 2 ;;
        --host)     HOST="$2";     shift 2 ;;
        --model)    MODEL="$2";    shift 2 ;;
        --engine)   ENGINE="$2";   shift 2 ;;
        --message)  MESSAGE="$2";  shift 2 ;;
        --help|-h)  show_help ;;
        *) echo "未知参数: $1"; show_help ;;
    esac
done

# ---------------------------------------------------------------------------
# 校验
# ---------------------------------------------------------------------------
if [ -z "$API_KEY" ] || [ -z "$HOST" ] || [ -z "$MODEL" ]; then
    echo "ERROR: 缺少必需参数 --api-key, --host, --model"
    echo ""
    echo "用法: bash test-goosed.sh --api-key <KEY> --host <URL> --model <MODEL>"
    echo "帮助: bash test-goosed.sh --help"
    exit 1
fi

# 检查 goosed
if ! command -v goosed >/dev/null 2>&1; then
    echo "ERROR: goosed 不在 PATH 中"
    echo "请先安装: cp goosed /usr/local/bin/goosed && chmod +x /usr/local/bin/goosed"
    exit 1
fi

# 自定义 provider（和 Gateway custom_providers/*.json 一致）
PROVIDER_NAME="custom_test_provider"
API_KEY_ENV="CUSTOM_TEST_PROVIDER_API_KEY"

echo "========================================="
echo " goosed agent 离线验证"
echo "========================================="
echo ""
echo "  Engine:   $ENGINE"
echo "  Host:     $HOST"
echo "  Model:    $MODEL"
echo "  Message:  $MESSAGE"
echo ""

# ---------------------------------------------------------------------------
# 准备运行时目录
# ---------------------------------------------------------------------------
RUNTIME=/tmp/goosed-verify

# 清理上次残留进程和端口占用
kill $(pgrep -f "goosed agent") 2>/dev/null || true
kill $(lsof -ti:30001) 2>/dev/null || true
kill $(lsof -ti:18080) 2>/dev/null || true
kill $(pgrep -f "ssl-proxy") 2>/dev/null || true
sleep 1

rm -rf $RUNTIME
mkdir -p $RUNTIME/home/data
mkdir -p $RUNTIME/config/custom_providers

# 生成 custom provider JSON
cat > $RUNTIME/config/custom_providers/${PROVIDER_NAME}.json <<EOF
{
  "name": "${PROVIDER_NAME}",
  "engine": "${ENGINE}",
  "display_name": "Test Provider (${ENGINE})",
  "description": "Custom test provider",
  "api_key_env": "${API_KEY_ENV}",
  "base_url": "${HOST}",
  "models": [{"name": "${MODEL}", "context_limit": 128000}],
  "supports_streaming": true,
  "requires_auth": true
}
EOF

# 生成 config.yaml
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
if [ -f "$SCRIPT_DIR/config.yaml" ]; then
    grep -v "^GOOSE_PROVIDER:\|^GOOSE_MODEL:" "$SCRIPT_DIR/config.yaml" > $RUNTIME/config/config.yaml
else
    cp /dev/null $RUNTIME/config/config.yaml
fi
echo "GOOSE_PROVIDER: ${PROVIDER_NAME}" >> $RUNTIME/config/config.yaml
echo "GOOSE_MODEL: ${MODEL}" >> $RUNTIME/config/config.yaml

SECRET=$(openssl rand -hex 32)

# ---------------------------------------------------------------------------
# HTTPS 自签名证书处理
# goosed 是 Rust 程序（reqwest + rustls），rustls 使用内置 Mozilla 根证书
# 不读系统 CA 信任库，也不读 SSL_CERT_FILE 环境变量
# 解决方案：启动 Python 反向代理做 SSL 终结，goosed 通过 HTTP 连本地代理
# ---------------------------------------------------------------------------
SSL_PROXY_PID=""
GOOSE_HOST_CONFIG="$HOST"
if echo "$HOST" | grep -q "^https://"; then
    PROXY_PORT=18080
    PROXY_HOST="http://127.0.0.1:${PROXY_PORT}"

    # 启动 Python SSL 代理（后台）
    echo "  启动 SSL 代理: $HOST -> $PROXY_HOST ..."
    /usr/bin/python3 -c "
import http.server, ssl, urllib.request, json, sys

TARGET = '$HOST'
class ProxyHandler(http.server.BaseHTTPRequestHandler):
    def do_POST(self):
        length = int(self.headers.get('Content-Length', 0))
        body = self.rfile.read(length) if length else b''
        target_url = TARGET + self.path
        ctx = ssl.create_default_context()
        ctx.check_hostname = False
        ctx.verify_mode = ssl.CERT_NONE
        req = urllib.request.Request(target_url, data=body, method='POST')
        for h in ['Content-Type', 'x-api-key', 'anthropic-version', 'Authorization', 'Accept']:
            v = self.headers.get(h)
            if v: req.add_header(h, v)
        try:
            resp = urllib.request.urlopen(req, context=ctx, timeout=120)
            self.send_response(resp.status)
            for k, v in resp.getheaders():
                if k.lower() not in ('transfer-encoding', 'connection'):
                    self.send_header(k, v)
            self.end_headers()
            self.wfile.write(resp.read())
        except urllib.error.HTTPError as e:
            self.send_response(e.code)
            self.send_header('Content-Type', 'application/json')
            self.end_headers()
            self.wfile.write(e.read())
        except Exception as e:
            self.send_response(502)
            self.send_header('Content-Type', 'application/json')
            self.end_headers()
            self.wfile.write(json.dumps({'error': str(e)}).encode())
    def do_GET(self):
        self.do_POST()
    def log_message(self, *args):
        pass  # 静默
http.server.HTTPServer(('127.0.0.1', $PROXY_PORT), ProxyHandler).serve_forever()
" > $RUNTIME/ssl-proxy.log 2>&1 &
    SSL_PROXY_PID=$!
    sleep 2

    if kill -0 $SSL_PROXY_PID 2>/dev/null; then
        echo "  OK: SSL 代理已启动 (PID=$SSL_PROXY_PID)"
        # 把 base_url 从 https 替换为 http://localhost 代理
        GOOSE_HOST_CONFIG="$PROXY_HOST"
    else
        echo "  FAIL: SSL 代理启动失败"
        cat $RUNTIME/ssl-proxy.log
        exit 1
    fi
fi

# 重新生成 custom provider JSON（用代理地址替换原始 HTTPS 地址）
cat > $RUNTIME/config/custom_providers/${PROVIDER_NAME}.json <<EOF
{
  "name": "${PROVIDER_NAME}",
  "engine": "${ENGINE}",
  "display_name": "Test Provider (${ENGINE})",
  "description": "Custom test provider",
  "api_key_env": "${API_KEY_ENV}",
  "base_url": "${GOOSE_HOST_CONFIG}",
  "models": [{"name": "${MODEL}", "context_limit": 128000}],
  "supports_streaming": true,
  "requires_auth": true
}
EOF

echo "[1/7] 启动 goosed agent ..."
echo "  Port:   30001"
echo "  Secret: $SECRET"
echo "  Model:  ${GOOSE_HOST_CONFIG}"
echo ""

# 启动 goosed（XDG_CONFIG_HOME 指向 config 目录）
export ${API_KEY_ENV}="$API_KEY"

GOOSE_PORT=30001 \
GOOSE_HOST=127.0.0.1 \
GOOSE_SERVER__SECRET_KEY=$SECRET \
GOOSE_PATH_ROOT=$RUNTIME \
GOOSE_DISABLE_KEYRING=1 \
HOME=$RUNTIME/home \
XDG_CONFIG_HOME=$RUNTIME/config \
GOOSE_TLS=false \
RUST_LOG=info \
goosed agent > $RUNTIME/goosed.log 2>&1 &
GOOSED_PID=$!

sleep 5

# 检查进程
echo "[2/7] 检查进程 ..."
if kill -0 $GOOSED_PID 2>/dev/null; then
    echo "  OK: goosed agent 运行中 (PID=$GOOSED_PID)"
else
    echo "  FAIL: goosed agent 启动失败"
    echo ""
    echo "=== 日志 ==="
    cat $RUNTIME/goosed.log
    exit 1
fi
echo ""

# 健康检查
echo "[3/7] 健康检查 GET /status ..."
STATUS=$(curl -s -w "\n%{http_code}" http://127.0.0.1:30001/status 2>/dev/null || echo "连接失败")
HTTP_CODE=$(echo "$STATUS" | tail -1)
BODY=$(echo "$STATUS" | sed '$d')
echo "  HTTP: $HTTP_CODE"
echo "  Body: $BODY"
if [ "$HTTP_CODE" != "200" ]; then
    echo "  FAIL: /status 返回非 200"
    echo ""
    echo "=== 日志 ==="
    tail -30 $RUNTIME/goosed.log
    kill $GOOSED_PID 2>/dev/null
    exit 1
fi
echo ""

# 创建 session
echo "[4/7] 创建 session POST /agent/start ..."
RESP=$(curl -s -X POST http://127.0.0.1:30001/agent/start \
  -H "Content-Type: application/json" \
  -H "x-secret-key: $SECRET" \
  -d '{"working_dir":"'"$RUNTIME"'"}')
SESSION_ID=$(echo "$RESP" | /usr/bin/python3 -c "import sys,json;print(json.load(sys.stdin).get('id',''))" 2>/dev/null || echo "")

if [ -z "$SESSION_ID" ]; then
    echo "  FAIL: 未获取到 session id"
    echo "  Response: $RESP"
    kill $GOOSED_PID 2>/dev/null
    exit 1
fi
echo "  OK: SessionId=$SESSION_ID"
echo ""

# 加载 provider 和 extensions（关键步骤！）
echo "[5/7] 加载模型和扩展 POST /agent/resume ..."
RESUME_RESP=$(curl -s --max-time 30 -X POST http://127.0.0.1:30001/agent/resume \
  -H "Content-Type: application/json" \
  -H "x-secret-key: $SECRET" \
  -d '{"session_id":"'"$SESSION_ID"'","load_model_and_extensions":true}')
# 检查 resume 是否成功：只看顶层 {"message": "..."} 错误，忽略 extension_results 内的错误
RESUME_ERROR=$(echo "$RESUME_RESP" | /usr/bin/python3 -c "
import sys, json
try:
    d = json.load(sys.stdin)
    if 'message' in d:
        print(d['message'])
except: pass
" 2>/dev/null || echo "")
if [ -n "$RESUME_ERROR" ]; then
    echo "  FAIL: resume 失败"
    echo "  Error: $RESUME_ERROR"
    kill $GOOSED_PID 2>/dev/null
    exit 1
fi
echo "  OK: 模型和扩展加载完成"
echo ""

# 订阅 SSE 事件流
curl -s -N --max-time 120 "http://127.0.0.1:30001/sessions/$SESSION_ID/events" \
  -H "x-secret-key: $SECRET" > $RUNTIME/sse.log 2>&1 &
SSE_PID=$!
sleep 1

# 发消息
REQ_ID=$(/usr/bin/python3 -c "import uuid; print(uuid.uuid4())" 2>/dev/null || echo "$(openssl rand -hex 4)-$(openssl rand -hex 2)-$(openssl rand -hex 2)-$(openssl rand -hex 2)-$(openssl rand -hex 6)")
echo "[6/7] 发消息测试模型 ..."
echo "  发送: $MESSAGE"
REPLY=$(curl -s --max-time 30 -X POST "http://127.0.0.1:30001/sessions/$SESSION_ID/reply" \
  -H "Content-Type: application/json" \
  -H "x-secret-key: $SECRET" \
  -d '{
    "request_id": "'"$REQ_ID"'",
    "user_message": {
      "role": "user",
      "created": '"$(date +%s)"',
      "content": [{"type": "text", "text": "'"$MESSAGE"'"}],
      "metadata": {"userVisible": true, "agentVisible": true}
    }
  }')
echo "  Reply ack: $REPLY"
echo ""

# 等待模型响应
echo "  等待模型响应 (最多 90s) ..."
WAITED=0
GOT_RESULT=""
while [ $WAITED -lt 90 ]; do
    if grep -q '"type":"Message"' $RUNTIME/sse.log 2>/dev/null; then
        GOT_RESULT="Message"
        break
    fi
    if grep -q '"type":"Error"' $RUNTIME/sse.log 2>/dev/null; then
        GOT_RESULT="Error"
        break
    fi
    sleep 3
    WAITED=$((WAITED + 3))
done

echo ""
if [ "$GOT_RESULT" = "Message" ]; then
    echo "  ======== 模型响应 ========"r
    # 拼接所有流式文本片段
    grep '^data:' $RUNTIME/sse.log | /usr/bin/python3 -c "
import sys, json
text_parts = []
for line in sys.stdin:
    line = line.strip()
    if line.startswith('data: '):
        try:
            d = json.loads(line[6:])
            if d.get('type') == 'Message':
                content = d.get('message', {}).get('content', [])
                for c in content:
                    if c.get('type') == 'text':
                        text_parts.append(c.get('text', ''))
        except: pass
print(''.join(text_parts))
" 2>/dev/null
    echo "  =========================="
    echo "  结果: 模型调用成功!"
elif [ "$GOT_RESULT" = "Error" ]; then
    echo "  结果: 模型调用失败"
    grep '^data:' $RUNTIME/sse.log | grep '"type":"Error"' | head -3
else
    echo "  结果: 超时，未收到响应"
fi
echo ""

kill $SSE_PID 2>/dev/null

# 清理
echo "[7/7] 清理 ..."
kill $GOOSED_PID 2>/dev/null
echo "  goosed agent 已停止"
if [ -n "$SSL_PROXY_PID" ]; then
    kill $SSL_PROXY_PID 2>/dev/null
    echo "  SSL 代理已停止"
fi
echo ""

echo "=== goosed 日志 ==="
tail -15 $RUNTIME/goosed.log
echo ""
echo "========================================="
echo " 验证完成"
echo "========================================="
