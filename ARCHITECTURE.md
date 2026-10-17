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
* **AntigravityCLIProvider:** Antigravity CLI (`agy`, formerly Gemini CLI) session monitor and native lifecycle hook adapter.
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

---

## Conversation-Aware Identity & Exact Focus Restoration

### Identity Separation Principles

Flowback follows a strict identity separation policy:
1. **Application Identity:** `bundleIdentifier` (e.g. `com.google.antigravity`, `com.microsoft.VSCode`).
2. **Window Identity:** `windowIdentifier` (macOS `CGWindowID`).
3. **Workspace Identity:** Canonical file system path (e.g. `/Users/abin/workspace/projects/lottery-pi`).
4. **Agent Execution Identity:** `executionID` (single prompt, turn, or tool invocation).
5. **Conversation Identity:** `conversationID` (enduring thread or trajectory).
6. **Remote Cloud Identity:** `isRemote`, `conversationURL` (distinguishing background cloud agents from local editor threads).

A repository path, window title, or process ID is **never** treated as a unique conversation ID. Multiple conversations associated with the same repository or editor window remain independent sessions with distinct lifecycles, titles, and focus targets.

### Restoration Hierarchy

When the user selects a conversation in Flowback, `FocusController.restoreSession(_:)` resolves the target through a conservative priority order:

1. **Provider Web URL / Dashboard / PR:**
   - Evaluated for remote agents (`isRemote == true`) or sessions exposing `conversationURL`.
   - Strict scheme validation: Only `http://` and `https://` URLs are permitted; unsafe schemes (`javascript:`, `file:`, arbitrary URI handlers) are rejected.
   - Result: `.providerURLOpened`
2. **CLI & Terminal Session Resumption:**
   - Evaluated for terminal-based agents (e.g., `AntigravityCLIProvider`, `ClaudeCodeProvider`).
   - If an origin terminal exists, Flowback focuses the terminal window and supplies a structured resume hint (e.g., `agy --conversation <id>` or `claude resume <id>`).
   - Result: `.resumeHintPresented` (A displayed resume command is an actionable hint, not proof of restoration; `isExactConversation` is `false`).
3. **Workspace & Window Adapter Focus:**
   - Evaluated for desktop GUI applications.
   - The registered application adapter matches candidate windows by Window ID, followed by workspace directory name.
   - Result: `.exactConversationRestored` (if native deep linking/conversation selection is implemented), `.workspaceActivatedOnly` (if workspace matched), or `.windowActivatedOnly` (if containing application window raised).
4. **Ambiguous Window Guard:**
   - If multiple windows match a workspace path and no reliable Window ID is available, Flowback returns `.targetAmbiguous` rather than arbitrarily guessing a window.
5. **Unsupported / Failure:**
   - Returns `.conversationUnavailable`, `.restorationUnsupported`, or `.restorationFailed` with explanatory error messages. Flowback **never** misrepresents window-only activation or resume hints as exact conversation focus.

### Persistence & Schema Migration (V2)

Flowback storage implements zero-downtime, backward-compatible SQLite migrations:
* **Migration V1:** Base session, event, snapshot, and settings schema.
* **Migration V2:** Uses reliable schema inspection (`PRAGMA table_info(sessions);`) rather than parsing error message strings. Adds `conversation_title`, `conversation_id`, `task_summary`, `execution_id`, `parent_session_id`, `conversation_url`, `focus_capability`, and `is_remote` columns along with an index on `conversation_id`.
* **Idempotency & Failure Rollback:** If columns already exist, migration skips them cleanly. Any unexpected SQLite failure propagates, triggers immediate transaction rollback, and prevents `PRAGMA user_version` from advancing.
* Existing V1 databases automatically upgrade without data loss. Legacy records missing conversation fields default safely to `windowOnly` capability and derive titles from workspace project names.
* **Resilient SQL Column Projections (F-12):** Explicit column projections (`sessionColumnsProjection`) and name-based SQLite column lookup with positional fallbacks ensure schema modifications never cause misaligned column decoding.

---

## Audit Remediation Architectural Invariants (F-01 through F-13)

1. **Window Selection Accuracy (F-01):** `WindowController.selectMatchingWindowIndex` correlates target `WindowInfo` bounds, geometry, and title scoring against accessibility candidates. If identity cannot be uniquely resolved, window raising fails conservatively rather than raising an arbitrary window.
2. **Honest Restoration Outcomes (F-02):** Window and workspace adapters report `.workspaceActivatedOnly` or `.windowActivatedOnly`, never claiming `.exactConversationRestored`.
3. **Provider Hook Coexistence (F-03):** Desktop and CLI providers use isolated, namespaced keys (`flowback-antigravity` and `flowback-antigravity-cli`) in `hooks.json`. Atomic file writes and targeted uninstallation preserve user-defined hooks and sibling provider configurations.
4. **Hot Event Path Performance (F-04):** Event ingestion updates state and dispatches focus decisions with $O(1)$ complexity without performing filesystem directory traversals or CLI health checks. Periodic maintenance schedules handle background discovery and health.
5. **Bounded In-Memory State (F-05):** In-memory completed sessions are bounded to 100, while active sessions are never evicted. Historical records reload seamlessly from SQLite on demand, and database pruning enforces retention schedules.
6. **Provider-Owned Resumption (F-06):** Terminal agent resume syntax is owned by the respective providers (`AgentProvider.resumeCommand(for:)`) and resolved via `ResumeCommandRegistry`. Core domain and focus models remain strictly provider-agnostic.
7. **Asynchronous Non-Blocking Execution (F-07):** External processes are managed via `AsyncProcessRunner` using Swift concurrency continuations, `Process.terminationHandler`, watchdog timeouts, and cooperative task cancellation.
8. **Decoupled Hook Protocol Handling (F-08):** `IPCHandler` routes requests generically, delegating payload interpretation and provider-specific responses to `AgentProvider.generateHookResponse(for:)`.
9. **Remote Agent Intent & Diagnostics (F-09):** Cloud sessions (`isRemote == true`) evaluate destinations honestly via `.restoreDestination` and respect user typing safeguards without false "missing local origin" diagnoses.
10. **Unified Component Lifecycle (F-10):** `LifecycleCoordinator` serves as the authoritative state machine for `FlowbackService`, providing rollback on critical component failure and coordinated reverse-order teardown.
11. **Canonical Shared IPC Types (F-11):** Wire protocol types `IPCRequest` and `IPCResponse` reside in `FlowbackCore/IPC`, ensuring CLI and daemon contracts stay synchronized without reversing module dependencies.
12. **Stable Database Decoding (F-12):** Repository decoders use explicit SQL column projections and name-based mapping (`sqlite3_column_name`), eliminating fragility to column ordering.
13. **Adapter Registry Concurrency (F-13):** `ApplicationAdapterRegistry` synchronizes mutations and lookups via `NSLock`, snapshotting registered adapters before executing external evaluation logic.
14. **UI Event Coalescing & Throttling (C-01):** High-frequency event streams are throttled using `UIEventCoalescer` with a 50ms coalescing window. Multiple intermediate events schedule at most one pending UI synchronization on `@MainActor`, achieving a 99.9% reduction in main runloop UI refresh frequency while capturing the cumulative final state.
