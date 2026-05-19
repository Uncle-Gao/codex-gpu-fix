#!/bin/bash
APP_NAME="Codex-Fix"
DIST_DIR="./dist"
# We create a staging directory specifically for the DMG content
STAGING_DIR="./dist/dmg_staging"
APP_BUNDLE="$STAGING_DIR/$APP_NAME.app"
DMG_NAME="Codex-Fix-Universal.dmg"
ICON_SOURCE="/Applications/Codex.app/Contents/Resources/icon.icns"
[ ! -f "$ICON_SOURCE" ] && ICON_SOURCE="/Applications/Codex.app/Contents/Resources/electron.icns"

echo "🚀 Starting professional DMG build process for $APP_NAME..."

mkdir -p "$STAGING_DIR"
rm -rf "$STAGING_DIR"/*
rm -f "$DMG_NAME"

# 1. Create the App structure inside staging
osacompile -o "$APP_BUNDLE" -e 'return'

# 2. Write the internal shell script
mkdir -p "$APP_BUNDLE/Contents/Resources/scripts"
cat > "$APP_BUNDLE/Contents/Resources/scripts/run.sh" << 'RUN_EOF'
#!/bin/bash
# Find node
export PATH="/usr/local/bin:/opt/homebrew/bin:$HOME/.nvm/versions/node/$(ls -t $HOME/.nvm/versions/node 2>/dev/null | head -1)/bin:/opt/local/bin:$PATH"
NODE_BIN=$(command -v node)

if [ -z "$NODE_BIN" ]; then
    osascript -e 'display dialog "Error: Node.js is not installed. Please install Node.js (v22+)." buttons {"OK"} default button "OK" with title "Codex-Fix" with icon stop'
    exit 1
fi

APP_PATH="/Applications/Codex.app/Contents/MacOS/Codex"
TEMP_INJECTOR="/tmp/codex-inject-runtime.mjs"

# Write the JS injector
cat > "$TEMP_INJECTOR" << 'JS_EOF'
const PORT = '9222';
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
async function findPageWs() { try { const res = await fetch("http://localhost:9222/json/list"); const targets = await res.json(); return targets.find(t => t.type === "page" && t.url?.includes("index.html"))?.webSocketDebuggerUrl; } catch (e) { return null; } }
function evalOnce(wsUrl) { return new Promise((resolve, reject) => { const ws = new WebSocket(wsUrl); ws.onopen = () => ws.send(JSON.stringify({id: 1, method: "Runtime.evaluate", params: {expression: PAYLOAD, returnByValue: true}})); ws.onmessage = (e) => { const m = JSON.parse(e.data); if (m.id === 1) { ws.close(); resolve(true); } }; ws.onerror = () => { ws.close(); reject(); }; setTimeout(() => { ws.close(); reject(); }, 5000); }); }
(async () => { let wsUrl; for (let i = 0; i < 600; i++) { wsUrl = await findPageWs(); if (wsUrl) break; await new Promise(r => setTimeout(r, 100)); } if (!wsUrl) process.exit(1);
  while (true) { try { const url = (await findPageWs()) || wsUrl; await evalOnce(url); } catch (e) {} await new Promise(r => setTimeout(r, REINJECT_INTERVAL_MS)); }
})();
JS_EOF

# Launch
"$APP_PATH" --use-angle=metal --remote-debugging-port=9222 &>/dev/null &
"$NODE_BIN" "$TEMP_INJECTOR" &>/dev/null &
disown -a
RUN_EOF

chmod +x "$APP_BUNDLE/Contents/Resources/scripts/run.sh"

# 3. Compile the portable AppleScript entry point
cat > scripts/main.applescript << 'AS_EOF'
set scriptPath to (POSIX path of (path to me)) & "Contents/Resources/scripts/run.sh"
do shell script "/bin/bash '" & scriptPath & "'"
AS_EOF

osacompile -o "$APP_BUNDLE" scripts/main.applescript

# 4. Hide Dock Icon (Set LSUIElement to true)
echo "🙈 Hiding Dock icon..."
/usr/libexec/PlistBuddy -c "Add :LSUIElement bool true" "$APP_BUNDLE/Contents/Info.plist"

# 5. Icon
if [ -f "$ICON_SOURCE" ]; then
    cp "$ICON_SOURCE" "$APP_BUNDLE/Contents/Resources/applet.icns"
    touch "$APP_BUNDLE"
fi

# 6. Add Applications Symlink
echo "🔗 Creating Applications symlink..."
ln -s /Applications "$STAGING_DIR/Applications"

# 7. DMG
echo "💿 Generating DMG..."
hdiutil create -volname "$APP_NAME" -srcfolder "$STAGING_DIR" -ov -format UDZO "$DMG_NAME"

echo "✅ Success! Final stealth file: $DMG_NAME"
