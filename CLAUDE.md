# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## 这是什么

修复 OpenAI Codex 桌面端在 Intel Mac（HD Graphics 630 + macOS 13）上的 GPU 渲染 bug：页面出现透明/模糊区域。方案是通过 CDP **持续注入** `<style>` 禁用 `backdrop-filter`，绕过 Electron 的 AsarIntegrity 文件完整性保护。

## 架构：三件套

1. **`scripts/codex-wrapper.sh`** — 替换 `/Applications/Codex.app/Contents/MacOS/Codex`，启动真实二进制（加 `--use-angle=metal --remote-debugging-port=9222`），后台启动 CDP 注入器；支持 `CODEX_INJECT_DEBUG=1` 切换日志输出
2. **`scripts/codex-inject.mjs`** — Node.js 22+ 零依赖**常驻进程**：先轮询 CDP `/json/list` 等待页面，然后每 2 秒重新执行一次幂等 payload（补回 `<style>` + 重挂 MutationObserver）
3. **`scripts/codex-fix.sh`** + **`scripts/com.uncle.codex-fix.plist`** — LaunchAgent 监控 `/Applications/Codex.app` 修改时间，Codex 自动更新覆盖 wrapper 后自动重新应用修复 + ad-hoc 签名

## ⚠️ 关键设计决策（别动）

**为什么注入器必须常驻、不能"注入一次就退出"**

最初实现是注入一次就 `process.exit(0)`，启动时实测失败。排查发现：

- Codex 的 React mount 在页面 `readyState=complete` 后还会清空 `document.head`，把 `<style id="__gfx_">` 一起干掉
- payload 里的 MutationObserver 能挡一部分，但如果 Codex 整个替换 `documentElement` 或重置 JS 上下文（路由切换、SPA 重渲染等），观察器变成孤儿
- 所以注入器必须常驻，每 2 秒重跑一次幂等 payload；任何 DOM 重置最多 2 秒就恢复

**payload 是幂等的**：每轮都会 disconnect 旧观察器、创建新的，并按需补回 `<style>`。重跑多次完全安全。

**消息处理避坑**：CDP `Runtime.evaluate` 的响应中 `Runtime.enable` 也会返回带 `result` 的成功消息。旧实现按 `m.id && m.result && !m.error` 判定成功，结果第一个响应（enable）就触发 `ws.close()`，evaluate 还没处理完连接已断。修复：只用 `Runtime.evaluate`（无需 enable）+ 校验 `m.id === EVAL_ID`。

## 调试

启动 Codex 前 `export CODEX_INJECT_DEBUG=1`，日志写入 `/tmp/codex-inject-debug.log`。日志含：CDP 端口就绪时间、页面首次出现耗时、每轮重注入是否成功、失败原因。默认静默。

CDP 端口（9222）开着的时候也可以手动调试：
- **`scripts/cdp-toggle.mjs`** — 注入可拖拽面板，实时开关 14 个 CSS 属性（用于排查"换了哪个属性又出 bug 了"）
- **`scripts/cdp-nuclear.mjs`** — 批量测试 CSS 属性组合，参数 `node cdp-nuclear.mjs 0-8`

两个调试脚本需要 `npm install ws`，且硬编码了 CDP page ID（每次 Codex 重启变化），用前要从 `http://localhost:9222/json/list` 取新 ID 替换。

## 硬编码路径

| 路径 | 用途 |
|------|------|
| `/Applications/Codex.app` | Codex 安装位置（用户态应用，不需要 sudo） |
| `/Users/uncle/.nvm/versions/node/v22.22.2/bin/node` | Node.js 二进制 — 复用前按本机改 |
| `/Users/uncle/.local/bin/codex-fix.sh` | LaunchAgent 调用的重应用脚本 |
| `~/Library/LaunchAgents/com.uncle.codex-fix.plist` | LaunchAgent 配置 |
| CDP port `9222` | Chrome DevTools Protocol 调试端口 |
| `__gfx_` | 注入的 `<style>` 元素 id |
| `window.__gfx_observer` | MutationObserver 全局引用（用于 disconnect 旧的） |

## 根因

Intel HD Graphics 630 驱动在 macOS 13 下的合成器 bug：CSS `backdrop-filter: blur()` 触发 GPU 合成器通过 IOSurface 截取背景内容，传输失败导致对应区域渲染为透明。禁用 `backdrop-filter` 让元素走正常流式渲染，不触发 IOSurface IPC。

## 已知取舍

`border-radius` 圆角渲染质量在 Intel 核显上略降（原本 `backdrop-filter` 强制创建合成层，意外修复了锯齿）。

## codex-fix.sh 内嵌了一份注入器源码

`scripts/codex-fix.sh` 通过 heredoc 内嵌了 `codex-wrapper.sh` 和 `codex-inject.mjs` 的完整内容（因为 LaunchAgent 触发时这个脚本是唯一可执行的入口，不能依赖仓库存在）。**改动注入器逻辑时记得同步内嵌副本**，否则 Codex 自动更新后会用旧版本。

## 安装/卸载

见 README.md 的安装和卸载章节。
