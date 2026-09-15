# Flowback — Universal macOS AI Agent Context & Focus Manager

> **"Your agents work. Your context comes back."**

Flowback is a native macOS application and CLI tool that manages focus, workspace context, and user attention across AI coding agents (Antigravity, Claude Code, OpenAI Codex, Gemini CLI, Aider, OpenCode, etc.), editors, terminals, browsers, and desktop tools.

---

## The Problem Flowback Solves

An AI coding agent works in the background while you switch to another task—reading documentation in Brave, reviewing PRs, or chatting on Slack. When the agent finishes or requests permission:
* **Without Flowback:** You either miss that the agent finished, or an aggressive script blindly steals your focus while you are in the middle of typing a message.
* **With Flowback:** Flowback remembers the exact origin context (window ID, workspace path, process ID). When the agent stops, Flowback checks your activity:
  * If you are **idle**, it smoothly returns you to the exact origin window (e.g. `VS Code → MatchDay`).
  * If you are **actively typing**, it suppresses focus-stealing and displays an actionable macOS notification instead.

---

## Core Principles

1. **Strict Decoupling:** Agent providers **NEVER** manipulate macOS focus directly. All operations strictly flow:
   ```text
   Provider → AgentEvent → EventBus → SessionManager → PolicyEngine → AttentionArbiter → FocusController
   ```
2. **Native & Lightweight:** Written in 100% Swift 6 Concurrency, AppKit, and SwiftUI. No Electron, no local web servers, zero polling loops when idle.
3. **Local-First & Private:** SQLite persistence (WAL mode) at `~/.flowback/flowback.sqlite`. Zero cloud dependencies, zero telemetry, zero code/secret inspection.

---

## Feature Matrix

| Feature | Description |
|---|---|
| **Universal Providers** | First-class official support for Antigravity (hook lifecycle with `fullyIdle=true` prioritization), Claude Code, OpenAI Codex, Gemini CLI, Aider, and Generic JSON Hook Protocol. |
| **Exact Window Restoration** | Section 14 restoration hierarchy: Exact Window ID → Same Workspace/Title → Same PID → Same Bundle → Graceful fallback. |
| **User Intent Engine** | Senses system idle time via `CGEventSource`. Never steals focus if typing in another app (< 5s threshold) or in fullscreen presentations. |
| **Attention Arbiter** | Priority queue (`permissionRequired` > `failure` > `completed` > `waiting` > `informational`). Multi-agent aggregation and focus cooldown (< 1000ms) prevent window thrashing. |
| **Focus Lock** | Temporarily suspend auto-restoration (15m, 30m, 45m, 1h, or indefinite) while keeping notification delivery intact. |
| **Menu Bar & Dashboard** | Lightweight status bar icon showing active agents count, quick ⌘1-⌘9 session restoration, Focus Lock toggles, and a native SwiftUI dashboard. |
| **Native CLI (`flowback`)** | Command-line companion communicating over local Unix domain socket (`~/.flowback/flowback.sock`). |

---

## Installation

### Prerequisites
* macOS 14.0 (Sonoma) or newer (Apple Silicon & Intel)

### Option 1: DMG Installer
Download `Flowback.dmg` from releases, open it, and drag `Flowback.app` to `/Applications`.

### Option 2: CLI Build & Install
```bash
git clone https://github.com/flowback/flowback.git
cd focus-switcher

# Build release targets
bash Scripts/build.sh

# Install flowback CLI to PATH
bash Scripts/install_cli.sh
```

---

## Quick Start

### 1. Launch Flowback App
```bash
open dist/Flowback.app
```
The Flowback icon will appear in your macOS menu bar.

### 2. Verify System Health with CLI
```bash
flowback doctor
```

### 3. Check Active Sessions & Refresh
```bash
flowback status
flowback refresh
flowback agents
flowback providers
```

### 4. Enable Focus Lock
```bash
flowback focus-lock 30m
```

---

## Supported Providers & Applications

* **Antigravity:** Installed hooks at `~/.gemini/config/hooks.json`. Listens to `PreInvocation`, `PostInvocation`, and `Stop` events. Features proactive active transcript scanning and live background discovery.
* **Claude Code:** Terminal/hook provider with automatic hook detection and state mapping.
* **OpenAI Codex:** Process & hook provider.
* **Gemini CLI:** CLI hook integration.
* **Aider:** Git & terminal notification integration.
* **Generic Hook Protocol:** Any script, agent, or CI tool can emit normalized events:
  ```bash
  flowback emit '{"schemaVersion":1,"event":"agent.completed","provider":"custom","sessionId":"s123","workspace":"/path/to/project"}'
  ```

### Supported Editors & Terminals
* **Editors:** Google Antigravity IDE, Visual Studio Code (Stable, Insiders, Code OSS), Windsurf, VSCodium, Positron, Trae, and Cursor.
* **Terminals:** Apple Terminal, iTerm2, Kitty, Alacritty, Ghostty, and Warp.
* **Browsers:** Brave, Google Chrome, Safari, Microsoft Edge, Arc, and generic macOS applications.

---

## Architecture Overview

```text
                    ┌─────────────────────────┐
                    │        Flowback         │
                    │       macOS App         │
                    └────────────┬────────────┘
                                 │
                         ┌───────▼───────┐
                         │    Event Bus  │
                         └───────┬───────┘
                                 │
               ┌─────────────────┼─────────────────┐
               │                 │                 │
        ┌──────▼──────┐   ┌──────▼──────┐   ┌──────▼──────┐
        │  Providers  │   │   Sessions  │   │   Storage   │
        └──────┬──────┘   └──────┬──────┘   └─────────────┘
               │                 │
       ┌───────┼────────┐        │
       │       │        │        │
 Antigravity Claude   Codex     ...
       │       │        │
       └───────┼────────┘
               ↓
       Normalized Agent Events
               ↓
        Agent State Machine
               ↓
         Policy Engine
               ↓
       Attention Arbitration
               ↓
        Focus Controller
               ↓
     ┌─────────┴─────────┐
     ↓                   ↓
Application           Window/
Activation            Workspace
                       Restoration
```

---

## Documentation

* [ARCHITECTURE.md](ARCHITECTURE.md) — Comprehensive architectural specification
* [DEVELOPMENT.md](DEVELOPMENT.md) — Developer guide, test execution, and contributing
* [PROVIDERS.md](PROVIDERS.md) — Provider specifications and how to add new agents
* [APPLICATION_ADAPTERS.md](APPLICATION_ADAPTERS.md) — Application adapters and window discovery
* [FOCUS_ENGINE.md](FOCUS_ENGINE.md) — Intent detection, policies, arbitration, and cooldowns
* [EVENT_PROTOCOL.md](EVENT_PROTOCOL.md) — Generic JSON Event Protocol (v1 schema)
* [SECURITY.md](SECURITY.md) — Permissions, sandboxing, and security guarantees
* [PRIVACY.md](PRIVACY.md) — Privacy manifesto (zero telemetry, zero secret capture)
* [TROUBLESHOOTING.md](TROUBLESHOOTING.md) — Diagnostic guide and common fixes
* [RELEASING.md](RELEASING.md) — Release packaging, signing, and notarization

---

## License

MIT License. Copyright © 2026 Flowback. All rights reserved.
