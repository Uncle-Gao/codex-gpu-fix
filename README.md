# Codex GPU Rendering Fix / Codex GPU 渲染修复

[English](#english) | [中文](#中文)

---

<a name="english"></a>
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

### Solution

#### 1. Recommended: Universal Stealth Launcher (New)

We now provide a standalone **"Codex-Fix"** app that launches the official Codex with the fix injected.

- **No Re-signing Required**: Does not modify the official app bundle.
- **Survives Updates**: Works forever even after Codex auto-updates.
- **Stealth Mode**: Runs in the background with no Dock icon.
- **GPU Optimized**: Keeps hardware acceleration and Metal enabled.

**Install:**

1. **Download**: Get `Codex-Fix-Universal.dmg` from the [Latest Release](https://github.com/Uncle-Gao/codex-gpu-fix/releases/latest).
2. **Install**: Open the DMG and drag **Codex-Fix** to your **Applications** folder.
3. **Launch**: Open **Codex-Fix** instead of the official Codex. (Ensure [Node.js](https://nodejs.org/) is installed on your Mac).

#### 2. Technical Details

**Why "external injection" instead of modifying `app.asar`**

Electron's **AsarIntegrity** verifies `app.asar` with a SHA-256 hash. Modifying it causes the app to crash. Our new solution uses **Chrome DevTools Protocol (CDP)** to inject the fix at runtime without touching a single byte of the original app.

**The persistent payload**

The fix re-applies an idempotent CSS payload every 2s. This ensures the `backdrop-filter: none` rule persists even if React re-renders or resets the DOM head.

**Role of `--use-angle=metal`**

Forces Electron to use Metal instead of OpenGL, providing a small performance boost on Intel Macs. It doesn't fix the bug but is worth keeping.

### Performance overhead

- **Injector process**: long-running Node process, ~30–50 MB RAM (startup cost, doesn't grow); CPU active only briefly during one localhost WebSocket round-trip every 2s
- **In-page MutationObserver**: the callback only does a single `getElementById('__gfx_')` (O(1) hash lookup), so even with React's high-frequency DOM mutations the cost is imperceptible
- Overall negligible compared to Codex itself (hundreds of MB RAM + GPU/Renderer processes) — sub-thousandth-fraction range

### Debug mode

Set `CODEX_INJECT_DEBUG=1` before launching to write injector lifecycle logs to `/tmp/codex-external-fix.log`:

```bash
CODEX_INJECT_DEBUG=1 open /Applications/Codex.app
tail -f /tmp/codex-external-fix.log
```

### Known trade-off

`border-radius` rendering quality drops slightly on Intel GPUs. Why: `backdrop-filter: blur()` originally forced a GPU compositor layer that incidentally fixed `border-radius` aliasing. With it disabled, anti-aliasing falls back to Intel-integrated-GPU defaults.

### File layout

```
codex-gpu-fix/
├── Codex-Fix-Universal.dmg            # Final distributable app
├── README.md                          # this file
├── GEMINI.md                          # project guide for AI assistants
├── scripts/
│   ├── codex-inject.mjs               # CDP persistent injector
│   ├── external-launcher.sh           # Core launch logic
│   ├── package-dmg.sh                 # DMG build script
│   └── ... (debug tools)
└── notes/
    ├── 排查过程.md                     # full investigation timeline (Chinese)
    └── 失败方案.md                     # failed approaches (Chinese)
```

### Legacy Method (Manual Injection)

The original method involved modifying the `Codex.app` bundle and re-signing it. This is no longer recommended.

**Install (Legacy):**

```bash
# 1. Wrap the real binary and deploy the injector
mv /Applications/Codex.app/Contents/MacOS/Codex /Applications/Codex.app/Contents/MacOS/Codex-real
cp scripts/codex-wrapper.sh /Applications/Codex.app/Contents/MacOS/Codex
cp scripts/codex-inject.mjs /Applications/Codex.app/Contents/Resources/codex-inject.mjs
chmod +x /Applications/Codex.app/Contents/MacOS/Codex

# 2. Re-sign ad-hoc
xattr -cr /Applications/Codex.app
codesign --force --deep --sign - /Applications/Codex.app
```

### Uninstall

If you used the **New Recommended** method, simply delete **Codex-Fix.app** from your Applications folder.

If you used the **Legacy** method, reinstalling the official Codex app will restore the original files.

---

<a name="中文"></a>
## 中文

修复 OpenAI Codex 桌面端在 Intel Mac 上的 GPU 渲染 bug（白色的透明/模糊区域）。通过 CDP 运行时**持续注入** `backdrop-filter: none`，在不修改 app.asar（受 Electron AsarIntegrity 保护）的前提下消除透明/模糊区域，性能开销可忽略。

> 📮 已提交至官方： [openai/codex#23458](https://github.com/openai/codex/issues/23458)

### 问题现象

Codex 启动后，首页和插件页出现**模糊/透明区域**，可以透过窗口看到桌面背景。

### 环境

| 项目 | 配置 |
|------|------|
| 机型 | MacBook Pro 2017 (MacBookPro14,3) |
| CPU | Intel Core i7 四核 3.1 GHz |
| GPU | Intel HD Graphics 630（核显，1.5 GB 共享显存） + AMD Radeon Pro 560（独显，4 GB） |
| 系统 | macOS 13 Ventura (Darwin 22.6.0) |
| App | OpenAI Codex v26.513.31313 / Electron 42.0.1 |

### 根因

Electron GPU 进程通过 IOSurface 共享纹理时，Intel HD Graphics 630 驱动在 macOS 13 下的合成器 bug。

页面 CSS 中 `backdrop-filter: blur()` 会触发 GPU 合成器截取背景内容做毛玻璃效果。截取过程中 IOSurface 传输到合成器失败 / 返回空数据，导致对应区域渲染为透明。

Intel 核显 + macOS 13 + Electron IOSurface IPC → 三板斧凑齐就触发。

### 解决方案

#### 1. 推荐方案：通用隐形启动器 (新)

我们现在提供一个独立的 **"Codex-Fix"** 应用程序，它会启动官方 Codex 并自动注入修复补丁。

- **无需重新签名**：不修改官方应用包。
- **抗更新**：Codex 自动更新后补丁依然有效。
- **隐形模式**：在后台运行，不在 Dock 栏显示图标。
- **GPU 优化**：保留硬件加速和 Metal 开启。

**安装步骤：**

1. **下载**：从 [最新发布页](https://github.com/Uncle-Gao/codex-gpu-fix/releases/latest) 下载 `Codex-Fix-Universal.dmg`。
2. **安装**：打开 DMG，将 **Codex-Fix** 拖入 **Applications (应用程序)** 文件夹。
3. **启动**：通过 **Codex-Fix** 启动应用，而不是直接打开官方 Codex。（请确保你的 Mac 已安装 [Node.js](https://nodejs.org/)）。

#### 2. 技术细节

**为什么使用“外部注入”而不是修改 `app.asar`**

Electron 的 **AsarIntegrity** 机制会校验 `app.asar` 的哈希值。修改它会导致应用崩溃。我们的新方案通过 **Chrome DevTools Protocol (CDP)** 在运行时注入修复代码，完全不触动原始应用的任何字节。

**持续注入逻辑**

修复逻辑每 2 秒重跑一次幂等的 payload。这确保了即使 React 重新渲染或重置了 DOM head，`backdrop-filter: none` 规则依然有效。

**`--use-angle=metal` 的作用**

强制 Electron 使用 Metal 图形 API 替代 OpenGL，在 Intel Mac 上有额外性能提升。它不会修复 bug，但值得保留。

### 性能开销

- **注入器进程**：常驻 Node 进程，~30-50 MB 内存（启动开销，不增长）；CPU 仅在每 2 秒一次的本地 WS 调用时短暂活动
- **页面里的 MutationObserver**：回调只做一次 `getElementById('__gfx_')`（O(1) 哈希查找），即便 React 高频变更 DOM 也几乎无感
- 整体相对于 Codex 本身（数百 MB 内存 + GPU/Renderer 进程）属于千分之几量级

### 调试模式

启动前 `export CODEX_INJECT_DEBUG=1`，注入器会把生命周期日志写入 `/tmp/codex-external-fix.log`：

```bash
CODEX_INJECT_DEBUG=1 open /Applications/Codex.app
tail -f /tmp/codex-external-fix.log
```

### 已知取舍

Intel GPU 上 `border-radius` 圆角渲染质量略降。原因：`backdrop-filter: blur()` 原本强制创建 GPU 合成层，意外修复了 `border-radius` 的锯齿问题。禁用它后圆角抗锯齿回到 Intel 核显默认水平。

### 文件说明

```
codex-gpu-fix/
├── Codex-Fix-Universal.dmg            # 最终发布的安装包
├── README.md                          # 本文档
├── GEMINI.md                          # AI 指导文档
├── scripts/
│   ├── codex-inject.mjs               # CDP 持续注入器
│   ├── external-launcher.sh           # 核心启动逻辑
│   ├── package-dmg.sh                 # DMG 打包脚本
│   └── ... (调试工具)
└── notes/
    ├── 排查过程.md                     # 完整排查时间线
    └── 失败方案.md                     # 试过的所有无效方案
```

### 遗留方案 (手动注入)

原始方案涉及修改 `Codex.app` 包并重新签名。不再推荐此方案。

**安装步骤 (遗留方案):**

```bash
# 1. 包装真实二进制 + 部署注入器
mv /Applications/Codex.app/Contents/MacOS/Codex /Applications/Codex.app/Contents/MacOS/Codex-real
cp scripts/codex-wrapper.sh /Applications/Codex.app/Contents/MacOS/Codex
cp scripts/codex-inject.mjs /Applications/Codex.app/Contents/Resources/codex-inject.mjs
chmod +x /Applications/Codex.app/Contents/MacOS/Codex

# 2. ad-hoc 重签名
xattr -cr /Applications/Codex.app
codesign --force --deep --sign - /Applications/Codex.app
```

### 卸载

如果你使用的是**新推荐**方案，只需从应用程序文件夹中删除 **Codex-Fix.app**。

如果你使用的是**遗留**方案，重新安装官方 Codex 即可恢复原始文件。
