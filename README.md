# Codex GPU 渲染修复

修复 OpenAI Codex 桌面端在 Intel Mac 上的 GPU 渲染 bug（白色的透明/模糊区域）。通过 CDP 运行时**持续注入** `backdrop-filter: none`，在不修改 app.asar（受 Electron AsarIntegrity 保护）的前提下消除透明/模糊区域，性能开销可忽略。

> 📮 已提交至官方： [openai/codex#23458](https://github.com/openai/codex/issues/23458)

Fix a GPU rendering bug in the OpenAI Codex desktop app on Intel Macs. Uses **persistent CDP runtime injection** to disable `backdrop-filter` — eliminating transparent/blurry areas without modifying app.asar (protected by Electron AsarIntegrity), with negligible performance overhead.

> 📮 Reported upstream: [openai/codex#23458](https://github.com/openai/codex/issues/23458)

## 问题现象 / The Bug

Codex 启动后，首页和插件页出现**模糊/透明区域**，可以透过窗口看到桌面背景。

## 环境

| 项目 | 配置 |
|------|------|
| 机型 | MacBook Pro 2017 (MacBookPro14,3) |
| CPU | Intel Core i7 四核 3.1 GHz |
| GPU | Intel HD Graphics 630（核显，1.5 GB 共享显存） + AMD Radeon Pro 560（独显，4 GB） |
| 系统 | macOS 13 Ventura (Darwin 22.6.0) |
| App | OpenAI Codex v26.513.31313 / Electron 42.0.1 |

## 问题

启动 Codex 后，首页和插件页出现模糊/透明区域，可以看到桌面背景透过窗口。性能无影响，但严重影响使用体验。

## 根因

Electron GPU 进程通过 IOSurface 共享纹理时，Intel HD Graphics 630 驱动在 macOS 13 下的合成器 bug。

页面 CSS 中 `backdrop-filter: blur()` 会触发 GPU 合成器截取背景内容做毛玻璃效果。截取过程中 IOSurface 传输到合成器失败 / 返回空数据，导致对应区域渲染为透明。

Intel 核显 + macOS 13 + Electron IOSurface IPC → 三板斧凑齐就触发。

## 最终方案

三件套：

1. **Wrapper 脚本** — 替换 `Codex.app/Contents/MacOS/Codex`，在原二进制基础上加 `--use-angle=metal` 和 CDP 调试端口
2. **CDP 持续注入器** — Node.js 常驻进程，先轮询等待页面就绪，然后每 2 秒重新执行一次幂等 payload：补回 `<style>`、重挂 MutationObserver
3. **LaunchAgent** — 监控 `/Applications/Codex.app` 修改时间，重装后自动重新应用修复 + 签名

### 为什么必须"持续注入"而不是"注入一次"

最初的实现是注入一次就退出，但实测在启动时**失败**。排查发现：

1. **Codex 的 React mount 会清空 `document.head`** —— 启动几秒后我们注入的 `<style>` 元素被一起干掉
2. 在 payload 里塞 MutationObserver 自愈也只能解决一半 —— 如果 Codex 替换整个 `documentElement` 或重置 JS 上下文（路由切换、热更新等），观察器会成为孤儿失效
3. **最终方案：注入器进程常驻，每 2 秒重跑幂等 payload**。每轮重新挂观察器、检查并补回 `<style>`。无论 Codex 怎么折腾 DOM，最多 2 秒就恢复。

### `--use-angle=metal` 的作用

强制 Electron 使用 Metal 图形 API 替代 OpenGL，在 Intel Mac 上有额外性能提升。它不会修复 bug，但值得保留。

### 为什么用 CDP 注入而不是直接改 app.asar

Electron 的 AsarIntegrity 机制对 `app.asar` 做了 SHA-256 哈希校验（存在 `Info.plist` 的 `ElectronAsarIntegrity` 键中）。修改 asar 会导致 hash 不匹配，启动时直接报错退出。

尝试用 `shasum -a 256` 重新计算 hash 并写回 plist，但 Electron 的 hash 计算方式与标准 shasum 不同（可能涉及内部文件排序或元数据剥离），始终无法算出匹配值。

CDP 运行时注入完全绕过文件完整性校验。

## 性能开销

- **注入器进程**：常驻 Node 进程，~30-50 MB 内存（启动开销，不增长）；CPU 仅在每 2 秒一次的本地 WS 调用时短暂活动
- **页面里的 MutationObserver**：回调只做一次 `getElementById('__gfx_')`（O(1) 哈希查找），即便 React 高频变更 DOM 也几乎无感
- 整体相对于 Codex 本身（数百 MB 内存 + GPU/Renderer 进程）属于千分之几量级

## 调试模式

启动前 `export CODEX_INJECT_DEBUG=1`，注入器会把生命周期日志写入 `/tmp/codex-inject-debug.log`：

```bash
CODEX_INJECT_DEBUG=1 open /Applications/Codex.app
tail -f /tmp/codex-inject-debug.log
```

日志包含：CDP 端口何时就绪、页面首次出现的耗时、每轮重注入是否成功、失败次数和原因。

默认静默运行（`>/dev/null 2>&1`）。

## 已知取舍

Intel GPU 上 `border-radius` 圆角渲染质量略降。原因：`backdrop-filter: blur()` 原本强制创建 GPU 合成层，意外修复了 `border-radius` 的锯齿问题。禁用它后圆角抗锯齿回到 Intel 核显默认水平。

尝试过用 `clip-path` 替代 `border-radius` 来圆角，效果无改善。用户选择接受当前状态。

## 文件说明

```
codex-gpu-fix/
├── README.md                          # 本文
├── CLAUDE.md                          # 给 AI 助手的项目导览
├── scripts/
│   ├── codex-wrapper.sh               # 替换 Codex.app/Contents/MacOS/Codex
│   ├── codex-inject.mjs               # CDP 持续注入器（Node 22+，常驻进程）
│   ├── codex-fix.sh                   # 自动重应用脚本（LaunchAgent 调用）
│   ├── com.uncle.codex-fix.plist      # LaunchAgent 配置
│   ├── cdp-toggle.mjs                 # 调试面板：交互式 CSS 属性开关
│   └── cdp-nuclear.mjs                # 调试脚本：逐个测试 CSS 属性
└── notes/
    ├── 排查过程.md                     # 完整排查时间线
    └── 失败方案.md                     # 试过的所有无效方案
```

> ⚠️ `codex-fix.sh` 和 `com.uncle.codex-fix.plist` 里硬编码了用户名 `uncle` 和 Node 路径 `/Users/uncle/.nvm/versions/node/v22.22.2/bin/node`，复用前请按本机情况调整。

## 安装

```bash
# 1. 包装真实二进制 + 部署注入器
sudo mv /Applications/Codex.app/Contents/MacOS/Codex /Applications/Codex.app/Contents/MacOS/Codex-real
sudo cp scripts/codex-wrapper.sh /Applications/Codex.app/Contents/MacOS/Codex
sudo cp scripts/codex-inject.mjs /Applications/Codex.app/Contents/Resources/codex-inject.mjs
sudo chmod +x /Applications/Codex.app/Contents/MacOS/Codex

# 2. ad-hoc 重签名（不能用 --remove-signature，macOS 13+ 会拒绝启动）
sudo xattr -cr /Applications/Codex.app
sudo codesign --force --deep --sign - /Applications/Codex.app

# 3. 安装自动重应用脚本（Codex 自动更新后会触发）
mkdir -p ~/.local/bin
cp scripts/codex-fix.sh ~/.local/bin/codex-fix.sh
chmod +x ~/.local/bin/codex-fix.sh

# 4. 安装 LaunchAgent
cp scripts/com.uncle.codex-fix.plist ~/Library/LaunchAgents/
launchctl load ~/Library/LaunchAgents/com.uncle.codex-fix.plist
```

## 卸载

```bash
launchctl unload ~/Library/LaunchAgents/com.uncle.codex-fix.plist
rm ~/Library/LaunchAgents/com.uncle.codex-fix.plist
rm ~/.local/bin/codex-fix.sh
# 重装 Codex 官方版本即可恢复原始文件
```
