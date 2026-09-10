# Flowback Architecture

Flowback is engineered around a strict, unidirectional event-driven pipeline designed to isolate agent providers from macOS focus manipulation.

---

## The Core Invariant

> **Providers must NEVER directly manipulate macOS application focus.**

For example, this is forbidden:
```text
AntigravityProvider → activate VS Code  [VIOLATION]
```

Instead:
```text
AntigravityProvider
       ↓
   AgentEvent
       ↓
    EventBus
       ↓
 SessionManager
       ↓
  PolicyEngine
       ↓
AttentionArbiter
       ↓
FocusController
       ↓
┌──────────────┬──────────────┐
│  AppKit /    │ AXUIElement /│
│ NSWorkspace  │ CoreGraphics │
└──────────────┴──────────────┘
```

---

## Module Breakdown

Flowback is divided into clean Swift Package Manager libraries:

### 1. `FlowbackCore`
* **Domain Models:** Strongly typed entities (`AgentSession`, `OriginContext`, `FocusSnapshot`, `AttentionRequest`, `ProviderHealth`).
* **State Machine:** Deterministic 9-state machine (`unknown`, `starting`, `running`, `waiting`, `permissionRequired`, `paused`, `completed`, `failed`, `cancelled`). Protected against transitions out of terminal states (`completed`, `failed`, `cancelled`).
* **Event System:** Strongly typed `AgentEvent` and `FocusEvent`, distributed via an asynchronous thread-safe `EventBus`.
* **Deduplication:** `EventDeduplicator` caches event hashes with a 500ms sliding window to prevent duplicate hook triggers.
* **Policies:** Hierarchical policy evaluation (`PolicyConfiguration`): Workspace Override → Application Override → Provider Override → Global Default.
* **Timeline:** `TimelineTracker` records fine-grained chronological audit logs for every session.
* **System Sensors:** `IdleTracker` senses real-time hardware idle duration using macOS `CGEventSource.secondsSinceLastEventType`.

### 2. `FlowbackStorage`
* **Zero-Dependency SQLite:** Custom C SQLite3 wrapper (`SQLiteDatabase`) operating in Write-Ahead Logging (`PRAGMA journal_mode = WAL;`) with `PRAGMA synchronous = NORMAL;`.
* **Thread-Safe Actor:** Actor-isolated database access with automatic immediate transactions.
* **Safe Pointer Lifecycle:** Wrapped in `ConnectionBox: @unchecked Sendable` ensuring compatibility across macOS 14.0+.
* **Versioned Migrations:** Incremental V1 schema defining `sessions`, `events`, `focus_snapshots`, `settings`, and indexing.
* **Self-Healing Recovery:** `RecoveryManager` detects SQLite header corruption, backs up corrupted files to `.corrupt.<timestamp>`, and recreates fresh schemas automatically.

### 3. `FlowbackFocus`
* **ApplicationController:** Wraps `NSWorkspace` and `NSRunningApplication` for PID and bundle-based discovery and activation.
* **WindowController:** CoreGraphics `CGWindowListCopyWindowInfo` queries and Accessibility `AXUIElement` window raising.
* **Application Adapters:** Open adapter architecture (`ApplicationAdapterRegistry`):
  * `VSCodeAdapter`: Handles VS Code, Insiders, OSS. Matches by Window ID, then workspace folder name.
  * `CursorAdapter`: Handles Cursor AI editor.
  * `TerminalAdapter`: Handles Terminal, iTerm2, Ghostty, Warp, Hyper.
  * `BraveAdapter`: Handles Brave Browser tabs and windows.
  * `GenericApplicationAdapter`: Fallback for all standard macOS apps.
* **UserIntentEngine:** Deterministic focus evaluator checking Focus Lock, policies, protected apps, fullscreen mode, active user interaction (< 5s idle threshold), and macOS Spaces.
* **AttentionArbiter:** Priority queue sorting requests (`permissionRequired` > `failure` > `completed` > `waiting` > `informational`), aggregating simultaneous agent events (1.5s window), and enforcing focus cooldown (1.0s) to eliminate window thrashing.
* **FocusController:** Central coordinator implementing Section 14 restoration hierarchy.

### 4. `FlowbackProviders`
* **Provider Protocol:** `AgentProvider` protocol defining discovery, health check, hook installation/uninstallation, and payload parsing.
* **AntigravityProvider:** Native hook installer for `~/.gemini/config/hooks.json`. Subscribes to `Stop` hook, prioritizing `fullyIdle = true`.
* **ClaudeCodeProvider:** Detects CLI installation, manages hook registration.
* **CodexProvider:** OpenAI Codex session monitor.
* **GeminiCLIProvider:** Gemini CLI session monitor.
* **AiderProvider:** Aider git-based session monitor.
* **GenericHookProvider:** JSON schema v1 receiver for custom agents and scripts.

### 5. `FlowbackServer`
* **Unix Domain Socket:** High-performance POSIX socket listener at `~/.flowback/flowback.sock`.
* **JSON-RPC Dispatcher:** `IPCHandler` executes `status`, `agents`, `sessions`, `doctor`, `focus`, `focus-lock`, `hook`, `emit`, and `test-focus`.

### 6. `FlowbackNotifications`
* **macOS UserNotifications:** Direct integration with `UNUserNotificationCenter`.
* **Actionable Alerts:** Features custom categories with `[Focus]` and `[Review]` action buttons.

### 7. `FlowbackUI`
* **MenuBarController:** Native `NSStatusItem` with dynamic badge ("● 3 agents active"), ⌘1-⌘9 recent session shortcuts, Attention Queue, Focus Lock menu, and direct dashboard launcher.
* **SwiftUI Dashboard:** Window controller with 7 primary views:
  * Overview: Active agents, waiting items, provider health.
  * Agents: Live agent cards with duration and status badges.
  * Sessions: Comprehensive session history.
  * Timeline: Millisecond-accurate event audit log.
  * Applications: Monitored applications and registered adapters.
  * Diagnostics: Flowback Doctor with self-repair buttons.
  * Settings: Configurable policies, cooldowns, and protected apps.

### 8. `FlowbackApp`
* **Composition Root:** `FlowbackService` orchestrates all background actors, monitors sleep/wake via `NSWorkspace.willSleepNotification` / `didWakeNotification`, and registers global shortcuts.

### 9. `FlowbackCLI`
* **Native Executable:** Standalone CLI tool `flowback` communicating over the local Unix domain socket.
