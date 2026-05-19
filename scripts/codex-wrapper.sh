#!/bin/bash
# Codex GPU Fix — Wrapper Script
# Replaces: /Applications/Codex.app/Contents/MacOS/Codex
#
# What this does:
#   1. Launches the real Codex binary with --use-angle=metal (Metal API for perf)
#      and --remote-debugging-port=9222 (Chrome DevTools Protocol)
#   2. Immediately launches the CDP auto-injector (Node.js, zero dependencies)
#   3. The injector polls until the page is ready, then injects backdrop-filter fix
#
# Why CDP injection instead of modifying app.asar:
#   Electron AsarIntegrity checksums prevent asar modification.
#   CDP runtime injection bypasses file integrity entirely.

REAL="$(dirname "$0")/Codex-real"
INJECT="$(dirname "$0")/../Resources/codex-inject.mjs"
NODE="/Users/uncle/.nvm/versions/node/v22.22.2/bin/node"

"$REAL" --use-angle=metal --remote-debugging-port=9222 "$@" &
PID=$!

# Launch injector immediately — it handles its own polling
"$NODE" "$INJECT" 9222 2>/dev/null &

wait $PID
