#!/bin/bash

echo "=== Tmux Environment Debug ==="
echo "Current working directory: $(pwd)"
echo "Parent shell PID: $$"
echo "PPID: $PPID"

echo
echo "=== Environment Variables ==="
echo "CLAUDE_CODE_SSE_PORT: ${CLAUDE_CODE_SSE_PORT:-<NOT SET>}"
echo "ENABLE_IDE_INTEGRATION: ${ENABLE_IDE_INTEGRATION:-<NOT SET>}"
echo "FORCE_CODE_TERMINAL: ${FORCE_CODE_TERMINAL:-<NOT SET>}"
echo "CLAUDE_CODE_OAUTH_TOKEN: ${CLAUDE_CODE_OAUTH_TOKEN:0:20}..."
echo "CLAUDE_CODE_ENTRYPOINT: ${CLAUDE_CODE_ENTRYPOINT:-<NOT SET>}"

echo
echo "=== Lock Files Check ==="
if [ -n "$CLAUDE_CODE_SSE_PORT" ]; then
    echo "Looking for lock file: ~/.claude/ide/$CLAUDE_CODE_SSE_PORT.lock"
    if [ -f "$HOME/.claude/ide/$CLAUDE_CODE_SSE_PORT.lock" ]; then
        echo "✅ Lock file found"
        echo "Contents:"
        cat "$HOME/.claude/ide/$CLAUDE_CODE_SSE_PORT.lock" | jq . 2>/dev/null
    else
        echo "❌ Lock file NOT found"
    fi
else
    echo "❌ CLAUDE_CODE_SSE_PORT not set - cannot check lock file"
fi

echo
echo "=== All Lock Files ==="
ls -la ~/.claude/ide/ 2>/dev/null || echo "No lock files directory"

echo
echo "=== Network Test ==="
if [ -n "$CLAUDE_CODE_SSE_PORT" ]; then
    echo "Testing connection to port $CLAUDE_CODE_SSE_PORT:"
    timeout 2 bash -c "echo '' | nc 127.0.0.1 $CLAUDE_CODE_SSE_PORT" 2>/dev/null && echo "✅ Connection successful" || echo "❌ Connection failed"
else
    echo "Cannot test - CLAUDE_CODE_SSE_PORT not set"
fi

echo
echo "=== Claude Discovery Test ==="
echo "What Claude sees when looking for IDEs:"

# Simulate what Claude does to discover IDEs
echo "1. Checking ~/.claude/ide/ directory:"
if [ -d "$HOME/.claude/ide" ]; then
    for lock_file in "$HOME/.claude/ide"/*.lock; do
        if [ -f "$lock_file" ]; then
            port=$(basename "$lock_file" .lock)
            echo "  Found lock file for port: $port"
            
            # Check if the server is actually listening
            if netstat -an 2>/dev/null | grep -q "127.0.0.1.$port.*LISTEN"; then
                echo "    ✅ Server is listening on port $port"
            else
                echo "    ❌ Server NOT listening on port $port"
            fi
            
            # Check if CLAUDE_CODE_SSE_PORT matches
            if [ "$CLAUDE_CODE_SSE_PORT" = "$port" ]; then
                echo "    ✅ Matches CLAUDE_CODE_SSE_PORT environment variable"
            else
                echo "    ⚠️  Does NOT match CLAUDE_CODE_SSE_PORT ($CLAUDE_CODE_SSE_PORT)"
            fi
        fi
    done
else
    echo "  ❌ ~/.claude/ide/ directory does not exist"
fi

echo
echo "=== Recommendation ==="
if [ -z "$CLAUDE_CODE_SSE_PORT" ]; then
    echo "❌ PROBLEM: CLAUDE_CODE_SSE_PORT environment variable is not set"
    echo "   This means Claude cannot find the IDE to connect to"
    echo "   Check if the tmux-pane provider is correctly passing environment variables"
elif [ ! -f "$HOME/.claude/ide/$CLAUDE_CODE_SSE_PORT.lock" ]; then
    echo "❌ PROBLEM: Lock file for port $CLAUDE_CODE_SSE_PORT does not exist"
    echo "   The Neovim server may have stopped or the port changed"
else
    echo "✅ Environment looks correct - Claude should be able to connect"
fi

echo
echo "=== Debug Complete ==="