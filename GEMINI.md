# Gemini Context: Codex GPU Fix

This project provides a persistent patch for the OpenAI Codex desktop app to fix a GPU rendering bug on Intel Macs.

**IMPORTANT:** For detailed project rules, architectural decisions, and development guidance, please refer to [CLAUDE.md](./CLAUDE.md).

## Project Overview
*   **Goal:** Eliminate rendering artifacts by disabling the CSS `backdrop-filter` property via CDP injection.
*   **Core Technology:** Wrapper Script + CDP Injector + LaunchAgent.
*   **Primary Documentation:** See [CLAUDE.md](./CLAUDE.md) for the "don't touch" logic and critical constraints.

