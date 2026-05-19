#!/bin/bash
# Codex GPU Fix — Auto-Reapply Script
# Path: /Users/uncle/.local/bin/codex-fix.sh
# Triggered by: LaunchAgent WatchPaths on /Applications/Codex.app
#
# When Codex auto-updates, it replaces the entire .app bundle,
# wiping our wrapper and injector. This script detects a fresh install
# and re-applies the fix automatically.
#
# Debounce: 10s lock prevents the codesign we perform from
# re-triggering WatchPaths in an infinite loop.

APP="/Applications/Codex.app"
REAL="$APP/Contents/MacOS/Codex-real"
WRAPPER="$APP/Contents/MacOS/Codex"
INJECT="$APP/Contents/Resources/codex-inject.mjs"
NODE="/Users/uncle/.nvm/versions/node/v22.22.2/bin/node"

# Debounce guard
LOCK="/tmp/codex-fix.lock"
if [ -f "$LOCK" ]; then
  now=$(date +%s)
  last=$(stat -f %m "$LOCK" 2>/dev/null || echo 0)
  [ $((now - last)) -lt 10 ] && exit 0
fi
touch "$LOCK"

# Wait for app install to finish
sleep 2
[ -d "$APP" ] || exit 0

# Check if wrapper is already in place
if [ -f "$REAL" ] && head -1 "$WRAPPER" 2>/dev/null | grep -q '^#!/bin/bash'; then
  if [ -f "$INJECT" ] && grep -q 'backdrop-filter' "$INJECT" 2>/dev/null; then
    xattr -cr "$APP" 2>/dev/null
    codesign --force --deep --sign - "$APP" 2>/dev/null
    exit 0
  fi
fi

# Fresh install — apply fix
if [ ! -f "$REAL" ]; then
  mv "$WRAPPER" "$REAL" 2>/dev/null || exit 1
fi

cat > "$WRAPPER" << 'WRAPPER_EOF'
#!/bin/bash
REAL="$(dirname "$0")/Codex-real"
INJECT="$(dirname "$0")/../Resources/codex-inject.mjs"
NODE="/Users/uncle/.nvm/versions/node/v22.22.2/bin/node"

"$REAL" --use-angle=metal --remote-debugging-port=9222 "$@" &
PID=$!

"$NODE" "$INJECT" 9222 2>/dev/null &

wait $PID
WRAPPER_EOF
chmod +x "$WRAPPER"

cat > "$INJECT" << 'INJECT_EOF'
const PORT = process.argv[2] || '9222';
const CSS = '*{backdrop-filter:none!important;-webkit-backdrop-filter:none!important}';

function injectNow(wsUrl) {
  return new Promise((resolve, reject) => {
    const ws = new WebSocket(wsUrl);
    let id = 1;
    ws.onopen = () => {
      ws.send(JSON.stringify({ id: id++, method: 'Runtime.enable' }));
      ws.send(JSON.stringify({
        id: id++, method: 'Runtime.evaluate', params: {
          expression: `(function(){var s=document.getElementById('__gfx_');if(!s){s=document.createElement('style');s.id='__gfx_';s.textContent=${JSON.stringify(CSS)};document.head.appendChild(s);return'ok'}return'already'})()`,
          returnByValue: true
        }
      }));
    };
    ws.onmessage = (e) => {
      try {
        const m = JSON.parse(e.data);
        if (m.id && m.result && !m.error) { ws.close(); resolve(true); }
        if (m.error) { ws.close(); reject(new Error(JSON.stringify(m.error))); }
      } catch {}
    };
    ws.onerror = () => { ws.close(); reject(new Error('ws error')); };
    setTimeout(() => { ws.close(); reject(new Error('timeout')); }, 5000);
  });
}

(async () => {
  for (let i = 0; i < 300; i++) {
    try {
      const res = await fetch(`http://localhost:${PORT}/json/list`);
      const targets = await res.json();
      const page = targets.find(t => t.type === 'page' && t.url?.includes('index.html'));
      if (page) {
        await injectNow(page.webSocketDebuggerUrl);
        process.exit(0);
      }
    } catch {}
    await new Promise(r => setTimeout(r, 100));
  }
  process.exit(1);
})();
INJECT_EOF

xattr -cr "$APP" 2>/dev/null
codesign --force --deep --sign - "$APP" 2>/dev/null

echo "Codex fix applied at $(date)" >> /tmp/codex-fix.log
