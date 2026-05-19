import { WebSocket } from 'ws';
const ws = new WebSocket('ws://localhost:9222/devtools/page/A7B17CE8700C9EE61E2120BCFD3D65C8');
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

const script = `
(() => {
  const old = document.getElementById('__toggles__'); if (old) old.remove();
  delete window.__updateFix__;

  const props = [
    { key: 'backdrop-filter',     css: 'none', label: 'backdrop-filter' },
    { key: 'transform',           css: 'none', label: 'transform' },
    { key: 'will-change',         css: 'auto', label: 'will-change' },
    { key: 'contain',             css: 'none', label: 'contain' },
    { key: 'isolation',           css: 'auto', label: 'isolation' },
    { key: 'content-visibility',  css: 'visible', label: 'content-visibility' },
    { key: 'border-radius',       css: '0',    label: 'border-radius' },
    { key: 'overflow',            css: 'visible', label: 'overflow' },
    { key: 'box-shadow',          css: 'none', label: 'box-shadow' },
    { key: 'opacity',             css: '1',    label: 'opacity' },
    { key: 'mix-blend-mode',      css: 'normal', label: 'mix-blend-mode' },
    { key: 'filter',              css: 'none', label: 'filter' },
    { key: 'clip-path',           css: 'none', label: 'clip-path' },
    { key: 'mask-image',          css: 'none', label: 'mask-image' },
  ];

  const state = {};
  props.forEach(p => state[p.key] = false);

  // Create panel
  const panel = document.createElement('div');
  panel.id = '__toggles__';
  panel.style.cssText = 'position:fixed;top:8px;right:8px;z-index:999999;background:#1e1e2e;color:#cdd6f4;font:11px/1.5 monospace;padding:10px 12px;border-radius:10px;box-shadow:0 4px 20px rgba(0,0,0,.5);max-height:90vh;overflow-y:auto;min-width:200px;user-select:none';

  const title = document.createElement('div');
  title.textContent = '🔧 GPU Layer Debug';
  title.style.cssText = 'font-weight:bold;margin-bottom:6px;font-size:12px;color:#f5c2e7';
  panel.appendChild(title);

  const hint = document.createElement('div');
  hint.textContent = 'click to toggle · changes apply instantly';
  hint.style.cssText = 'font-size:9px;color:#6c7086;margin-bottom:8px';
  panel.appendChild(hint);

  const list = document.createElement('div');
  panel.appendChild(list);

  function updateCSS() {
    let s = document.getElementById('__bfix__');
    if (!s) { s = document.createElement('style'); s.id = '__bfix__'; document.head.appendChild(s); }
    const rules = [];
    props.forEach(p => {
      if (state[p.key]) rules.push(p.key + ': ' + p.css + ' !important');
    });
    if (rules.length === 0) {
      s.textContent = '/* idle */';
    } else {
      s.textContent = '* { ' + rules.join('; ') + '; }';
      // Also handle prefixed
      if (state['backdrop-filter']) {
        s.textContent += '\\n* { -webkit-backdrop-filter: none !important; }';
      }
      if (state['mask-image']) {
        s.textContent += '\\n* { -webkit-mask-image: none !important; }';
      }
    }
  }

  function render() {
    list.innerHTML = '';
    props.forEach(p => {
      const row = document.createElement('div');
      row.style.cssText = 'display:flex;align-items:center;gap:6px;padding:3px 4px;cursor:pointer;border-radius:4px';
      row.addEventListener('mouseenter', () => row.style.background = '#313244');
      row.addEventListener('mouseleave', () => row.style.background = state[p.key] ? '#2a1f3d' : '');
      if (state[p.key]) row.style.background = '#2a1f3d';

      const dot = document.createElement('span');
      dot.textContent = state[p.key] ? '🟣' : '⚫';
      dot.style.cssText = 'font-size:10px;flex-shrink:0';
      row.appendChild(dot);

      const label = document.createElement('span');
      label.textContent = p.label;
      label.style.cssText = state[p.key] ? 'color:#cba6f7;font-weight:bold' : 'color:#6c7086';
      row.appendChild(label);

      if (state[p.key]) {
        const val = document.createElement('span');
        val.textContent = '→ ' + p.css;
        val.style.cssText = 'color:#a6adc8;font-size:10px;margin-left:auto';
        row.appendChild(val);
      }

      row.addEventListener('click', () => {
        state[p.key] = !state[p.key];
        updateCSS();
        render();
      });

      list.appendChild(row);
    });

    // active count
    const active = props.filter(p => state[p.key]).length;
    title.textContent = '🔧 GPU Debug' + (active > 0 ? ' (' + active + ' active)' : '');
  }

  render();

  // drag support
  let dragging = false, dx = 0, dy = 0;
  title.style.cursor = 'move';
  title.addEventListener('mousedown', (e) => {
    if (e.target !== title) return;
    dragging = true;
    dx = e.clientX - panel.offsetLeft;
    dy = e.clientY - panel.offsetTop;
  });
  document.addEventListener('mousemove', (e) => {
    if (!dragging) return;
    panel.style.left = (e.clientX - dx) + 'px';
    panel.style.top = (e.clientY - dy) + 'px';
    panel.style.right = 'auto';
  });
  document.addEventListener('mouseup', () => dragging = false);

  // close button
  const close = document.createElement('span');
  close.textContent = ' ✕';
  close.style.cssText = 'float:right;cursor:pointer;color:#6c7086;font-size:12px';
  close.title = 'close panel';
  close.addEventListener('click', (e) => { e.stopPropagation(); panel.remove(); });
  title.appendChild(close);

  document.body.appendChild(panel);
  return 'panel ready — right side of screen';
})()
`;

ws.on('open', async () => {
  try {
    await send('Runtime.enable');
    const r = await send('Runtime.evaluate', { expression: script, returnByValue: true });
    console.log(r.result?.value);
  } catch (e) { console.error(e.message); }
  finally { ws.close(); }
});
ws.on('error', (e) => { console.error('ws:', e.message); });
