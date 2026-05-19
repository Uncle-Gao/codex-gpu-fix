// Codex GPU Fix — CDP Auto-Injector (persistent)
// Path: /Applications/Codex.app/Contents/Resources/codex-inject.mjs
// Runtime: Node.js 22+ (built-in WebSocket & fetch, zero dependencies)
//
// What this does:
//   Polls Chrome DevTools Protocol until the page is ready, then repeatedly
//   evaluates a self-healing payload that ensures a <style> disabling
//   backdrop-filter is always present in the document.
//
// Why persistent re-injection (not "inject once and exit"):
//   1. Codex's React mount wipes document.head on startup, removing our <style>
//   2. A MutationObserver inside the payload catches DOM mutations, BUT
//      if Codex replaces document.documentElement entirely (or the JS context
//      is reset on navigation), that observer becomes orphaned
//   3. Re-running the payload every 2s reattaches the observer and re-adds
//      the style if missing — robust against any DOM/context reset
//
// Why backdrop-filter: none !important:
//   backdrop-filter: blur() triggers GPU compositor to capture background
//   content via IOSurface. On Intel HD 630 + macOS 13, this IOSurface
//   transfer fails, producing transparent/white areas.
//
// Debug mode:
//   Set env var CODEX_INJECT_DEBUG=1 to log lifecycle events to stdout.
//   The wrapper (codex-wrapper.sh) honors the same flag to redirect
//   stdout/stderr to /tmp/codex-inject-debug.log.

const PORT = process.argv[2] || '9222';
const DEBUG = process.env.CODEX_INJECT_DEBUG === '1';
const CSS = '*{backdrop-filter:none!important;-webkit-backdrop-filter:none!important}';
const REINJECT_INTERVAL_MS = 2000;

// Idempotent payload: always re-attaches observer (in case prior one was
// orphaned by documentElement replacement) and re-adds style if missing.
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

  // Phase 1: wait for page to appear (up to 60s)
  let wsUrl;
  for (let i = 0; i < 600; i++) {
    try {
      wsUrl = await findPageWs();
      if (wsUrl) { log(`page ready after ${i * 100}ms`); break; }
    } catch (e) { if (i % 20 === 0) log(`waiting for CDP: ${e.message}`); }
    await new Promise(r => setTimeout(r, 100));
  }
  if (!wsUrl) { log(`TIMEOUT no page after 60s`); process.exit(1); }

  // Phase 2: persistent re-injection — runs until parent (wrapper) dies
  let count = 0, fails = 0;
  while (true) {
    try {
      // Re-query page (CDP target id can change on navigation)
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
