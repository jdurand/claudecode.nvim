#!/bin/bash

echo "=== Testing WebSocket connectivity from tmux environment ==="

PORT=${CLAUDE_CODE_SSE_PORT:-14381}
AUTH_TOKEN=$(cat ~/.claude/ide/$PORT.lock 2>/dev/null | python3 -c "import sys, json; print(json.load(sys.stdin)['authToken'])" 2>/dev/null)

echo "Port: $PORT"
echo "Auth Token: ${AUTH_TOKEN:0:20}..."
echo "Current PWD: $(pwd)"
echo ""

# Test basic TCP connectivity
echo "1. Testing basic TCP connectivity:"
timeout 2 bash -c "echo '' | nc 127.0.0.1 $PORT" 2>/dev/null && echo "✅ TCP connection successful" || echo "❌ TCP connection failed"

# Test HTTP connection
echo ""
echo "2. Testing HTTP connection:"
curl -s -I -m 2 http://127.0.0.1:$PORT/ | head -1 || echo "❌ HTTP connection failed"

# Test WebSocket handshake
echo ""
echo "3. Testing WebSocket handshake:"
if [ -n "$AUTH_TOKEN" ]; then
    curl -s -m 2 -H "Connection: Upgrade" -H "Upgrade: websocket" -H "Sec-WebSocket-Key: dGhlIHNhbXBsZQ==" -H "Sec-WebSocket-Version: 13" -H "x-claude-code-ide-authorization: $AUTH_TOKEN" http://127.0.0.1:$PORT/ -w "Status: %{http_code}\n" | tail -1
else
    echo "❌ No auth token found"
fi

echo ""
echo "4. Environment check:"
echo "CLAUDE_CODE_SSE_PORT: $CLAUDE_CODE_SSE_PORT"
echo "ENABLE_IDE_INTEGRATION: $ENABLE_IDE_INTEGRATION"
echo "FORCE_CODE_TERMINAL: $FORCE_CODE_TERMINAL"
echo "CLAUDE_CODE_OAUTH_TOKEN: ${CLAUDE_CODE_OAUTH_TOKEN:0:20}..."
echo "CLAUDE_CODE_ENTRYPOINT: $CLAUDE_CODE_ENTRYPOINT"

echo ""
echo "5. Lock file check:"
if [ -f ~/.claude/ide/$PORT.lock ]; then
    echo "✅ Lock file exists"
    cat ~/.claude/ide/$PORT.lock | python3 -c "import sys, json; data=json.load(sys.stdin); print('Workspace folders:'); [print('  ' + folder) for folder in data['workspaceFolders']]" 2>/dev/null
else
    echo "❌ Lock file not found"
fi

echo ""
echo "=== Test completed ==="