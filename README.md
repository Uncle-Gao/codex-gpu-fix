# Codex GPU 渲染修复

修复 OpenAI Codex 桌面端在 Intel Mac 上的 GPU 渲染 bug。通过 CDP 运行时注入禁用 `backdrop-filter`，在不修改 app.asar（受 Electron AsarIntegrity 保护）且不影响性能的前提下消除透明/模糊区域。

Fix a GPU rendering bug in the OpenAI Codex desktop app on Intel Macs. Uses CDP runtime injection to disable `backdrop-filter` — eliminating transparent/blurry areas without modifying app.asar (protected by Electron AsarIntegrity) and with zero performance impact.

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
2. **CDP 自动注入器** — 100ms 轮询等待页面就绪，通过 Chrome DevTools Protocol 注入 `backdrop-filter: none !important`
3. **LaunchAgent** — 监控 `/Applications/Codex.app` 修改时间，重装后自动重新应用修复 + 签名

### `--use-angle=metal` 的作用

强制 Electron 使用 Metal 图形 API 替代 OpenGL，在 Intel Mac 上有额外性能提升。它不会修复 bug，但值得保留。

### 为什么用 CDP 注入而不是直接改 app.asar

Electron 的 AsarIntegrity 机制对 `app.asar` 做了 SHA-256 哈希校验（存在 `Info.plist` 的 `ElectronAsarIntegrity` 键中）。修改 asar 会导致 hash 不匹配，启动时直接报错退出。

尝试用 `shasum -a 256` 重新计算 hash 并写回 plist，但 Electron 的 hash 计算方式与标准 shasum 不同（可能涉及内部文件排序或元数据剥离），始终无法算出匹配值。

CDP 运行时注入完全绕过文件完整性校验。

## 已知取舍

Intel GPU 上 `border-radius` 圆角渲染质量略降。原因：`backdrop-filter: blur()` 原本强制创建 GPU 合成层，意外修复了 `border-radius` 的锯齿问题。禁用它后圆角抗锯齿回到 Intel 核显默认水平。

尝试过用 `clip-path` 替代 `border-radius` 来圆角，效果无改善。用户选择接受当前状态。

## 文件说明

```
codex-gpu-fix/
├── README.md                          # 本文
├── scripts/
│   ├── codex-wrapper.sh               # 替换 Codex.app/Contents/MacOS/Codex
│   ├── codex-inject.mjs               # CDP 自动注入器（Node 22+）
│   ├── codex-fix.sh                   # 自动修复脚本（LaunchAgent 调用）
│   ├── com.uncle.codex-fix.plist      # LaunchAgent 配置
│   ├── cdp-toggle.mjs                 # 调试面板：交互式 CSS 属性开关
│   └── cdp-nuclear.mjs                # 调试脚本：逐个测试 CSS 属性
└── notes/
    ├── 排查过程.md                     # 完整排查时间线
    └── 失败方案.md                     # 试过的所有无效方案
```

## 安装

```bash
# 创建 wrapper 和注入器
sudo cp scripts/codex-wrapper.sh /Applications/Codex.app/Contents/MacOS/Codex
sudo cp scripts/codex-inject.mjs /Applications/Codex.app/Contents/Resources/codex-inject.mjs
sudo chmod +x /Applications/Codex.app/Contents/MacOS/Codex

# 签名
sudo xattr -cr /Applications/Codex.app
sudo codesign --force --deep --sign - /Applications/Codex.app

# 安装 LaunchAgent
cp scripts/com.uncle.codex-fix.plist ~/Library/LaunchAgents/
launchctl load ~/Library/LaunchAgents/com.uncle.codex-fix.plist
```

## 卸载

```bash
launchctl unload ~/Library/LaunchAgents/com.uncle.codex-fix.plist
rm ~/Library/LaunchAgents/com.uncle.codex-fix.plist
# 重装 Codex 官方版本即可恢复原始文件
```
