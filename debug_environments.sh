#!/bin/bash

echo "=== Debugging Claude IDE Detection Issues ==="
echo

# Function to check environment
check_environment() {
    local env_name="$1"
    echo "--- $env_name Environment ---"
    
    # Basic environment check
    echo "SHELL: $SHELL"
    echo "TERM: $TERM"
    echo "TMUX: ${TMUX:-<not set>}"
    echo "SSH_CLIENT: ${SSH_CLIENT:-<not set>}"
    echo "PWD: $(pwd)"
    echo
    
    # Claude-specific environment variables
    echo "Claude Environment Variables:"
    echo "  CLAUDE_CODE_SSE_PORT: ${CLAUDE_CODE_SSE_PORT:-<not set>}"
    echo "  ENABLE_IDE_INTEGRATION: ${ENABLE_IDE_INTEGRATION:-<not set>}"
    echo "  FORCE_CODE_TERMINAL: ${FORCE_CODE_TERMINAL:-<not set>}"
    echo "  CLAUDE_CODE_OAUTH_TOKEN: ${CLAUDE_CODE_OAUTH_TOKEN:0:20}..."
    echo "  CLAUDE_CODE_ENTRYPOINT: ${CLAUDE_CODE_ENTRYPOINT:-<not set>}"
    echo "  CLAUDE_CODE_CONFIG_DIR: ${CLAUDE_CODE_CONFIG_DIR:-<not set>}"
    echo
    
    # Lock file check
    if [ -n "$CLAUDE_CODE_SSE_PORT" ]; then
        local lock_file="$HOME/.claude/ide/$CLAUDE_CODE_SSE_PORT.lock"
        if [ -f "$lock_file" ]; then
            echo "Lock file found: $lock_file"
            echo "Lock file contents:"
            cat "$lock_file" | jq . 2>/dev/null || cat "$lock_file"
        else
            echo "Lock file NOT found: $lock_file"
        fi
    else
        echo "Cannot check lock file - CLAUDE_CODE_SSE_PORT not set"
    fi
    echo
    
    # Network connectivity test
    if [ -n "$CLAUDE_CODE_SSE_PORT" ]; then
        echo "Network connectivity test:"
        timeout 2 bash -c "echo '' | nc 127.0.0.1 $CLAUDE_CODE_SSE_PORT" 2>/dev/null && echo "  ✅ TCP connection successful" || echo "  ❌ TCP connection failed"
        
        # WebSocket handshake test with proper headers
        if [ -f "$HOME/.claude/ide/$CLAUDE_CODE_SSE_PORT.lock" ]; then
            local auth_token=$(cat "$HOME/.claude/ide/$CLAUDE_CODE_SSE_PORT.lock" 2>/dev/null | jq -r '.authToken' 2>/dev/null)
            if [ -n "$auth_token" ] && [ "$auth_token" != "null" ]; then
                echo "  Testing WebSocket handshake:"
                local ws_key="dGhlIHNhbXBsZSBub25jZQ=="  # Valid 24-char base64
                local response=$(curl -s -m 2 \
                    -H "Connection: Upgrade" \
                    -H "Upgrade: websocket" \
                    -H "Sec-WebSocket-Key: $ws_key" \
                    -H "Sec-WebSocket-Version: 13" \
                    -H "x-claude-code-ide-authorization: $auth_token" \
                    -w "HTTP_CODE:%{http_code}" \
                    http://127.0.0.1:$CLAUDE_CODE_SSE_PORT/ 2>/dev/null)
                echo "    Response: $response"
            else
                echo "  ❌ Cannot test WebSocket - no valid auth token"
            fi
        fi
    else
        echo "Cannot test network connectivity - CLAUDE_CODE_SSE_PORT not set"
    fi
    echo
    
    # Check if Claude CLI is available and its version
    echo "Claude CLI Check:"
    if command -v claude >/dev/null 2>&1; then
        echo "  ✅ Claude CLI available: $(which claude)"
        claude --version 2>/dev/null || echo "  (version command failed)"
    else
        echo "  ❌ Claude CLI not found in PATH"
    fi
    echo
    
    # Test what Claude sees when looking for IDEs
    echo "Claude IDE Detection Test:"
    echo "  Running: claude --help | grep -A5 -B5 ide"
    claude --help 2>/dev/null | grep -A5 -B5 -i ide || echo "  (no IDE-related help found)"
    echo
}

# Check current environment
check_environment "Current"

# Provide instructions for manual testing
echo "=== Manual Testing Instructions ==="
echo
echo "1. Native Terminal Test:"
echo "   - Open a Neovim terminal (:terminal)"
echo "   - Run: source debug_environments.sh && check_environment 'Native Terminal'"
echo "   - Run: claude /ide"
echo "   - Note: Does it connect automatically?"
echo
echo "2. Tmux Pane Test:"
echo "   - Use tmux-pane provider to open Claude"
echo "   - Run: source debug_environments.sh && check_environment 'Tmux Pane'"
echo "   - Note: Does it show 'No available IDEs detected'?"
echo
echo "3. Comparison:"
echo "   - Compare environment variables between the two"
echo "   - Check if network connectivity differs"
echo "   - Look for any process or session differences"
echo

echo "=== Process and Session Analysis ==="
echo "Current processes related to claude or neovim:"
ps aux | grep -E "(claude|nvim)" | grep -v grep || echo "No related processes found"
echo

if [ -n "$TMUX" ]; then
    echo "Tmux session info:"
    echo "  Session: $(tmux display-message -p '#S')"
    echo "  Window: $(tmux display-message -p '#W')"
    echo "  Pane: $(tmux display-message -p '#P')"
    echo "  Pane ID: $(tmux display-message -p '#{pane_id}')"
    echo
    
    echo "All tmux panes with commands:"
    tmux list-panes -a -F "#{session_name}:#{window_index}.#{pane_index} #{pane_current_command} #{pane_start_command}" | head -10
else
    echo "Not in a tmux session"
fi

echo
echo "=== End Debug Report ==="