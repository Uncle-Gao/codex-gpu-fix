# Codex GPU Rendering Fix / Codex GPU 渲染修复

[English](#english) | [中文](#中文)

---

## English

Fix a GPU rendering bug in the OpenAI Codex desktop app on Intel Macs (white transparent / blurry areas on the home and Plugins pages). Uses **persistent CDP runtime injection** to disable `backdrop-filter`, eliminating the artifacts without modifying `app.asar` (which is protected by Electron's AsarIntegrity check), with negligible performance overhead.

> 📮 Reported upstream: [openai/codex#23458](https://github.com/openai/codex/issues/23458)

### The bug

After launching Codex, the home page and Plugins page show **blurry / transparent regions** through which the desktop background is visible.

### Environment

| Item | Value |
|------|-------|
| Machine | MacBook Pro 2017 (MacBookPro14,3) |
| CPU | Intel Core i7 quad-core 3.1 GHz |
| GPU | Intel HD Graphics 630 (integrated, 1.5 GB shared) + AMD Radeon Pro 560 (discrete, 4 GB) |
| OS | macOS 13 Ventura (Darwin 22.6.0) |
| App | OpenAI Codex v26.513.31313 / Electron 42.0.1 |

### Root cause

A compositor bug in the Intel HD Graphics 630 driver on macOS 13 when Electron's GPU process shares textures via IOSurface.

A CSS `backdrop-filter: blur()` rule in the page causes the GPU compositor to capture the background content for the frosted-glass effect. The IOSurface transfer to the compositor silently fails / returns empty data, leaving those regions rendered as transparent.

Intel integrated GPU + macOS 13 + Electron IOSurface IPC — when all three coincide, the bug fires.

## Solution / 解决方案

### 1. Recommended: Universal Stealth Launcher (New)
### 1. 推荐方案：通用隐形启动器 (新)

We now provide a standalone **"Codex-Fix"** app that launches the official Codex with the fix injected.
我们现在提供一个独立的 **"Codex-Fix"** 应用程序，它会启动官方 Codex 并自动注入修复补丁。

- **No Re-signing Required**: Does not modify the official app bundle. / **无需重新签名**：不修改官方应用包。
- **Survives Updates**: Works forever even after Codex auto-updates. / **抗更新**：Codex 自动更新后补丁依然有效。
- **Stealth Mode**: Runs in the background with no Dock icon. / **隐形模式**：在后台运行，不在 Dock 栏显示图标。
- **GPU Optimized**: Keeps hardware acceleration and Metal enabled. / **GPU 优化**：保留硬件加速和 Metal 开启。

#### Install / 安装

1. **Download**: Get `Codex-Fix-Universal.dmg` from the [Latest Release](https://github.com/Uncle-Gao/codex-gpu-fix/releases/latest).
   **下载**：从 [最新发布页](https://github.com/Uncle-Gao/codex-gpu-fix/releases/latest) 下载 `Codex-Fix-Universal.dmg`。
2. **Install**: Open the DMG and drag **Codex-Fix** to your **Applications** folder.
   **安装**：打开 DMG，将 **Codex-Fix** 拖入 **Applications (应用程序)** 文件夹。
3. **Launch**: Open **Codex-Fix** instead of the official Codex. (Ensure [Node.js](https://nodejs.org/) is installed on your Mac).
   **启动**：通过 **Codex-Fix** 启动应用，而不是直接打开官方 Codex。（请确保你的 Mac 已安装 [Node.js](https://nodejs.org/)）。

---

### 2. Technical Details / 技术细节

#### Why "external injection" instead of modifying `app.asar`
#### 为什么使用“外部注入”而不是修改 `app.asar`

Electron's **AsarIntegrity** verifies `app.asar` with a SHA-256 hash. Modifying it causes the app to crash. Our new solution uses **Chrome DevTools Protocol (CDP)** to inject the fix at runtime without touching a single byte of the original app.

Electron 的 **AsarIntegrity** 机制会校验 `app.asar` 的哈希值。修改它会导致应用崩溃。我们的新方案通过 **Chrome DevTools Protocol (CDP)** 在运行时注入修复代码，完全不触动原始应用的任何字节。

#### The persistent payload / 持续注入逻辑
The fix re-applies an idempotent CSS payload every 2s. This ensures the `backdrop-filter: none` rule persists even if React re-renders or resets the DOM head.

修复逻辑每 2 秒重跑一次幂等的 payload。这确保了即使 React 重新渲染或重置了 DOM head，`backdrop-filter: none` 规则依然有效。

#### Role of `--use-angle=metal`
Forces Electron to use Metal instead of OpenGL, providing a small performance boost on Intel Macs. It doesn't fix the bug but is worth keeping.

#### Why CDP injection instead of patching `app.asar`
Electron's AsarIntegrity verifies `app.asar` with a SHA-256 hash stored under `ElectronAsarIntegrity` in `Info.plist`. Modifying the asar mismatches the hash and the app refuses to launch. CDP runtime injection bypasses file integrity entirely.

### Performance overhead

- **Injector process**: long-running Node process, ~30–50 MB RAM (startup cost, doesn't grow); CPU active only briefly during one localhost WebSocket round-trip every 2s
- **In-page MutationObserver**: the callback only does a single `getElementById('__gfx_')` (O(1) hash lookup), so even with React's high-frequency DOM mutations the cost is imperceptible
- Overall negligible compared to Codex itself (hundreds of MB RAM + GPU/Renderer processes) — sub-thousandth-fraction range

### Debug mode

Set `CODEX_INJECT_DEBUG=1` before launching to write injector lifecycle logs to `/tmp/codex-inject-debug.log`:

```bash
CODEX_INJECT_DEBUG=1 open /Applications/Codex.app
tail -f /tmp/codex-external-fix.log
```

Logs include: when the CDP port becomes ready, how long until the page first appears, whether each re-injection succeeded, and failure counts/reasons.

### Known trade-off

`border-radius` rendering quality drops slightly on Intel GPUs. Why: `backdrop-filter: blur()` originally forced a GPU compositor layer that incidentally fixed `border-radius` aliasing. With it disabled, anti-aliasing falls back to Intel-integrated-GPU defaults.

### File layout

```
codex-gpu-fix/
├── Codex-Fix-Universal.dmg            # Final distributable app / 最终发布的安装包
├── README.md                          # this file / 本文档
├── GEMINI.md                          # project guide for AI assistants / AI 指导文档
├── scripts/
│   ├── codex-inject.mjs               # CDP persistent injector / CDP 持续注入器
│   ├── external-launcher.sh           # Core launch logic / 核心启动逻辑
│   ├── package-dmg.sh                 # DMG build script / DMG 打包脚本
│   └── ... (debug tools)
└── notes/
    ├── 排查过程.md                     # full investigation timeline (Chinese)
    └── 失败方案.md                     # failed approaches (Chinese)
```

---

### Legacy Method (Manual Injection) / 遗留方案 (手动注入)

The original method involved modifying the `Codex.app` bundle and re-signing it. This is no longer recommended as it requires re-applying after every update.

原始方案涉及修改 `Codex.app` 包并重新签名。不再推荐此方案，因为每次更新后都需要重新操作。

#### Install / 安装 (Legacy)

```bash
# 1. Wrap the real binary and deploy the injector
mv /Applications/Codex.app/Contents/MacOS/Codex /Applications/Codex.app/Contents/MacOS/Codex-real
cp scripts/codex-wrapper.sh /Applications/Codex.app/Contents/MacOS/Codex
cp scripts/codex-inject.mjs /Applications/Codex.app/Contents/Resources/codex-inject.mjs
chmod +x /Applications/Codex.app/Contents/MacOS/Codex

# 2. Re-sign ad-hoc
xattr -cr /Applications/Codex.app
codesign --force --deep --sign - /Applications/Codex.app

# 3. Install LaunchAgent for auto-reapply
# (See scripts/com.uncle.codex-fix.plist)
```

### Uninstall / 卸载

If you used the **New Recommended** method, simply delete **Codex-Fix.app** from your Applications folder.
如果你使用的是**新推荐**方案，只需从应用程序文件夹中删除 **Codex-Fix.app**。

If you used the **Legacy** method, reinstalling the official Codex app will restore the original files.
如果你使用的是**遗留**方案，重新安装官方 Codex 即可恢复原始文件。
