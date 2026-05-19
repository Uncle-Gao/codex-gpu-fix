import { WebSocket } from 'ws';
const ws = new WebSocket('ws://localhost:9222/devtools/page/BFA2CD2D0EDCFB51E2815A656D0D4317');
let nr = 1;
const pending = new Map();
function send(m, p = {}) {
  return new Promise((r, j) => {
    const id = nr++;
    pending.set(id, { r, j });
    ws.send(JSON.stringify({ id, method: m, params: p }));
  });
}
ws.on('message', (d) => {
  const o = JSON.parse(d.toString());
  if (o.id && pending.has(o.id)) { const { r, j } = pending.get(o.id); pending.delete(o.id); o.error ? j(new Error(JSON.stringify(o.error))) : r(o.result); }
});

// Tests in order: inject → user checks → if not fixed, try next
const test = process.argv[2] || '1';

const css = {
  '0': '/* clear */ #__bfix__ { display: none; }',
  '1': '* { transform: none !important; will-change: auto !important; contain: none !important; isolation: auto !important; backdrop-filter: none !important; -webkit-backdrop-filter: none !important; content-visibility: visible !important; }',
  '2': '* { border-radius: 0 !important; }',
  '3': '* { overflow: visible !important; }',
  '4': '* { box-shadow: none !important; }',
  '5': '* { opacity: 1 !important; }',
  '6': '* { mix-blend-mode: normal !important; }',
  '7': '* { position: static !important; }',
  '8': '* { contain-intrinsic-size: none !important; }',
};

const name = { '0':'clear', '1':'no-compositing', '2':'no-radius', '3':'no-overflow', '4':'no-shadow', '5':'no-opacity', '6':'no-blend', '7':'no-position', '8':'no-cis' };

const cssText = css[test] || css['1'];

const inject = `
(() => {
  let s = document.getElementById('__bfix__');
  if (!s) { s = document.createElement('style'); s.id = '__bfix__'; document.head.appendChild(s); }
  s.textContent = ${JSON.stringify(cssText)};
  return 'injected [' + ${JSON.stringify(name[test])} + ']';
})()
`;

ws.on('open', async () => {
  try {
    await send('Runtime.enable');
    const r = await send('Runtime.evaluate', { expression: inject, returnByValue: true });
    console.log(r.result?.value);
  } catch (e) { console.error(e.message); }
  finally { ws.close(); }
});
ws.on('error', (e) => { console.error('ws:', e.message); });
