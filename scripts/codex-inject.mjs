// Codex GPU Fix — CDP Auto-Injector
// Path: /Applications/Codex.app/Contents/Resources/codex-inject.mjs
// Runtime: Node.js 22+ (built-in WebSocket & fetch, zero dependencies)
//
// What this does:
//   Polls Chrome DevTools Protocol every 100ms until the page is ready,
//   then injects a <style> element that disables backdrop-filter globally.
//
// Why backdrop-filter: none !important:
//   backdrop-filter: blur() triggers GPU compositor to capture background
//   content via IOSurface. On Intel HD 630 + macOS 13, this IOSurface
//   transfer fails, producing transparent/white areas.
//   Disabling backdrop-filter keeps the element in normal flow rendering,
//   which doesn't need IOSurface IPC → no GPU driver bug.

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
  // 100ms polling — tight enough to inject before user notices the bug
  // 300 attempts × 100ms = 30s max wait (page usually ready in < 1s)
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
