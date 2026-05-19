#!/bin/bash
# Codex GPU Fix — Wrapper Script
# Replaces: /Applications/Codex.app/Contents/MacOS/Codex
#
# What this does:
#   1. Launches the real Codex binary with --use-angle=metal (Metal API for perf)
#      and --remote-debugging-port=9222 (Chrome DevTools Protocol)
#   2. Launches the CDP auto-injector (Node.js, zero dependencies) in background
#   3. The injector polls until the page is ready, then re-injects every 2s
#      to survive React/Codex DOM resets
#
# Why CDP injection instead of modifying app.asar:
#   Electron AsarIntegrity checksums prevent asar modification.
#   CDP runtime injection bypasses file integrity entirely.
#
# Debug mode:
#   Export CODEX_INJECT_DEBUG=1 before launching to capture injector
#   lifecycle logs to /tmp/codex-inject-debug.log. Default: silent.

REAL="$(dirname "$0")/Codex-real"
INJECT="$(dirname "$0")/../Resources/codex-inject.mjs"
NODE="/Users/uncle/.nvm/versions/node/v22.22.2/bin/node"

"$REAL" --use-angle=metal --remote-debugging-port=9222 "$@" &
PID=$!

if [ "$CODEX_INJECT_DEBUG" = "1" ]; then
  CODEX_INJECT_DEBUG=1 "$NODE" "$INJECT" 9222 >>/tmp/codex-inject-debug.log 2>&1 &
else
  "$NODE" "$INJECT" 9222 >/dev/null 2>&1 &
fi

wait $PID
