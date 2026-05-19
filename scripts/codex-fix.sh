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

if [ "$CODEX_INJECT_DEBUG" = "1" ]; then
  CODEX_INJECT_DEBUG=1 "$NODE" "$INJECT" 9222 >>/tmp/codex-inject-debug.log 2>&1 &
else
  "$NODE" "$INJECT" 9222 >/dev/null 2>&1 &
fi

wait $PID
WRAPPER_EOF
chmod +x "$WRAPPER"

cat > "$INJECT" << 'INJECT_EOF'
const PORT = process.argv[2] || '9222';
const DEBUG = process.env.CODEX_INJECT_DEBUG === '1';
const CSS = '*{backdrop-filter:none!important;-webkit-backdrop-filter:none!important}';
const REINJECT_INTERVAL_MS = 2000;

const PAYLOAD = `(function(){
  var CSS = ${JSON.stringify(CSS)};
  function ensure() {
    if (document.getElementById('__gfx_')) return;
    var s = document.createElement('style');
    s.id = '__gfx_';
    s.textContent = CSS;
    (document.head || document.documentElement || document).appendChild(s);
  }
  ensure();
  try { if (window.__gfx_observer) window.__gfx_observer.disconnect(); } catch(e){}
  window.__gfx_observer = new MutationObserver(ensure);
  try { window.__gfx_observer.observe(document, {childList: true, subtree: true}); } catch(e){}
  return !!document.getElementById('__gfx_');
})()`;

const log = DEBUG
  ? (msg) => console.log(`[${new Date().toISOString()}] ${msg}`)
  : () => {};

function evalOnce(wsUrl) {
  return new Promise((resolve, reject) => {
    const ws = new WebSocket(wsUrl);
    const EVAL_ID = 1;
    ws.onopen = () => {
      ws.send(JSON.stringify({
        id: EVAL_ID, method: 'Runtime.evaluate',
        params: { expression: PAYLOAD, returnByValue: true }
      }));
    };
    ws.onmessage = (e) => {
      try {
        const m = JSON.parse(e.data);
        if (m.id !== EVAL_ID) return;
        if (m.error) { ws.close(); reject(new Error(JSON.stringify(m.error))); return; }
        ws.close(); resolve(m.result?.result?.value);
      } catch {}
    };
    ws.onerror = () => { ws.close(); reject(new Error('ws error')); };
    setTimeout(() => { ws.close(); reject(new Error('timeout')); }, 5000);
  });
}

async function findPageWs() {
  const res = await fetch(`http://localhost:${PORT}/json/list`);
  const targets = await res.json();
  const page = targets.find(t => t.type === 'page' && t.url?.includes('index.html'));
  return page?.webSocketDebuggerUrl;
}

(async () => {
  log(`START pid=${process.pid} port=${PORT} interval=${REINJECT_INTERVAL_MS}ms debug=${DEBUG}`);
  let wsUrl;
  for (let i = 0; i < 600; i++) {
    try {
      wsUrl = await findPageWs();
      if (wsUrl) { log(`page ready after ${i * 100}ms`); break; }
    } catch (e) { if (i % 20 === 0) log(`waiting for CDP: ${e.message}`); }
    await new Promise(r => setTimeout(r, 100));
  }
  if (!wsUrl) { log(`TIMEOUT no page after 60s`); process.exit(1); }

  let count = 0, fails = 0;
  while (true) {
    try {
      const url = (await findPageWs()) || wsUrl;
      const ok = await evalOnce(url);
      count++;
      if (count <= 3 || count % 30 === 0) log(`reinject #${count} ok=${ok}`);
      fails = 0;
    } catch (e) {
      fails++;
      if (fails <= 3 || fails % 30 === 0) log(`reinject fail #${fails}: ${e.message}`);
      if (fails > 600) { log(`TOO MANY FAILS — exiting`); process.exit(2); }
    }
    await new Promise(r => setTimeout(r, REINJECT_INTERVAL_MS));
  }
})().catch(e => { log(`FATAL ${e.message}`); process.exit(3); });
INJECT_EOF

xattr -cr "$APP" 2>/dev/null
codesign --force --deep --sign - "$APP" 2>/dev/null

echo "Codex fix applied at $(date)" >> /tmp/codex-fix.log
