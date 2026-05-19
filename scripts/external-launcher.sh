#!/bin/bash
# Codex External Launcher
# This script launches the OFFICIAL Codex app with CDP enabled and runs the injector
# WITHOUT modifying the app bundle, thus preserving the original signature.

# --- Configuration ---
APP_PATH="/Applications/Codex.app/Contents/MacOS/Codex"
# Get the absolute path to this project directory
PROJECT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
INJECT_SCRIPT="$PROJECT_DIR/scripts/codex-inject.mjs"
NODE_BIN="/Users/uncle/.nvm/versions/node/v22.22.2/bin/node"
LOG_FILE="/tmp/codex-external-fix.log"

# --- Validation ---
if [ ! -f "$APP_PATH" ]; then
    echo "Error: Codex.app not found at $APP_PATH"
    exit 1
fi

if [ ! -f "$NODE_BIN" ]; then
    echo "Error: Node.js not found at $NODE_BIN"
    exit 1
fi

# --- Execution ---
echo "Starting original Codex with Metal and CDP port 9222..."
# Launch Codex in background with performance flags and debugging port
"$APP_PATH" --use-angle=metal --remote-debugging-port=9222 >/dev/null 2>&1 &
CODEX_PID=$!

echo "Starting CDP Injector (Logging to $LOG_FILE)..."
# Launch the injector from the project directory
"$NODE_BIN" "$INJECT_SCRIPT" 9222 >"$LOG_FILE" 2>&1 &
INJECT_PID=$!

echo "Codex is running (PID: $CODEX_PID). The fix is active."
echo "Closing this terminal will NOT stop Codex, but it's recommended to keep it open or use the Automator app."

# Wait for Codex to exit
wait $CODEX_PID

# Clean up injector when Codex exits
kill $INJECT_PID 2>/dev/null
echo "Codex exited. Injector stopped."
