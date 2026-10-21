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
* **ApplicationController:** Wraps `NSWorkspace` and `NSRunningApplication` for PID and bundle-based discovery and activation, featuring cooperative activation and non-blocking asynchronous LaunchServices fallback.
* **WindowController:** CoreGraphics `CGWindowListCopyWindowInfo` queries and Accessibility `AXUIElement` window raising.
* **Application Adapters:** Open adapter architecture (`ApplicationAdapterRegistry`):
  * `WindsurfAdapter`: Handles Codeium Windsurf editor (`com.codeium.windsurf`). Matches exact window ID or workspace directory title (`[Workspace] — Windsurf`).
  * `CursorAdapter`: Handles Cursor AI editor (`co.anysphere.cursor`, `com.todesktop.230313mzl4w4u92`, `com.cursor.Cursor`).
  * `VSCodeAdapter`: Handles VS Code, Insiders, OSS, VSCodium, Positron, Trae. Matches by Window ID, then workspace folder name.
  * `TerminalAdapter`: Handles Apple Terminal, iTerm2, Ghostty, Warp, Alacritty, Kitty, WezTerm, Hyper.
  * `BraveAdapter`: Handles Brave Browser tabs and windows.
  * `GenericApplicationAdapter`: Fallback for all standard macOS apps.
* **UserIntentEngine:** Deterministic focus evaluator checking Focus Lock, policies, protected apps, fullscreen mode, active user interaction (< 5s idle threshold), and macOS Spaces.
* **AttentionArbiter:** Priority queue sorting requests (`permissionRequired` > `failure` > `completed` > `waiting` > `informational`), aggregating simultaneous agent events (1.5s window), and enforcing focus cooldown (1.0s) to eliminate window thrashing.
* **FocusController:** Central coordinator implementing Section 14 restoration hierarchy with actor reentrancy safety and tokenized cancellation ownership.

### 4. `FlowbackProviders`
* **Provider Protocol:** `AgentProvider` protocol defining discovery, health check, hook installation/uninstallation, payload parsing, and resume syntax.
* **AntigravityProvider:** Native hook installer for `~/.gemini/config/hooks.json`. Subscribes to `Stop` hook, prioritizing `fullyIdle = true`.
* **AntigravityCLIProvider:** Antigravity CLI (`agy`, formerly Gemini CLI) session monitor, lockfile tracker, and native lifecycle hook adapter.
* **WindsurfProvider:** Official Cascade JSON lifecycle hooks (`~/.codeium/windsurf/hooks.json`) and transcript scanner.
* **OpenCodeProvider:** Native OpenCode plugin (`~/.config/opencode/plugins/flowback.js`) with event subscriptions over local IPC.
* **CursorBackgroundProvider:** Remote Cursor Cloud Agents API client (`api.cursor.com/v1/agents`) tracking subagents, branches, and PR URLs with local window heuristics.
* **CopilotProvider:** GitHub Copilot CLI and agent adapter (`~/.copilot`, `~/.config/github-copilot`) with `gh copilot` resume hint.
* **ClaudeCodeProvider:** Detects CLI installation, manages hook registration and terminal session tracking.
* **CodexProvider:** OpenAI Codex session monitor and status mapping.
* **AiderProvider:** Aider git-based session monitor and terminal watcher.
* **GenericHookProvider:** JSON schema v1 receiver for custom agents and scripts.

### 5. `FlowbackServer`
* **Unix Domain Socket:** High-performance POSIX socket listener at `~/.flowback/flowback.sock` with peer UID verification.
* **JSON-RPC Dispatcher:** `IPCHandler` executes `status`, `refresh`, `agents`, `sessions`, `doctor`, `providers`, `focus`, `focus-lock`, `hook`, `emit`, `test-focus`, `test-notification`, `config-export`, `config-import`, and `quit`.

### 6. `FlowbackNotifications`
* **macOS UserNotifications:** Direct integration with `UNUserNotificationCenter`.
* **Actionable Alerts:** Features custom categories with `[Focus]` and `[Review]` action buttons.

### 7. `FlowbackUI`
* **MenuBarController:** Native `NSStatusItem` with dynamic badge ("● 3 agents active"), ⌘1-⌘9 recent session shortcuts, Attention Queue, Focus Lock menu, and direct dashboard launcher. Freezes recent sessions into an immutable snapshot during menu presentation to ensure stable keyboard shortcut targets.
* **SwiftUI Dashboard:** Window controller adhering to the macOS Card Design System (HIG / WCAG AA compliant) with 7 primary tabs and 4 general destinations:
  * Primary Tabs: **Overview** (active agents & quick stats), **Agents** (live agent cards with elapsed timers), **Sessions** (paginated SQLite history), **Timeline** (millisecond-accurate event log), **Applications** (monitored processes & registered adapters), **Diagnostics** (Flowback Doctor with repair actions), and **Settings** (configurable policies, cooldowns, and protected apps).
  * General Sidebar Destinations: **Advanced Settings** (cooldown slider, launch at login, factory defaults reset), **What's New** (dynamic release notes feed), **Support** (privacy-sanitized diagnostic exporter and Buy Me a Coffee links), and **About Flowback** (version metadata, contributor credits, and embedded MIT license sheet).

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

## Audit Remediation Architectural Invariants (F-01 through F-23)

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
15. **Bounded Process Output Streaming & Watchdog Safety (F-14):** `AsyncProcessRunner` streams stdout and stderr continuously via `readabilityHandler` into bounded memory buffers (`maxOutputBytes: 1MB`), preventing 64KB OS pipe buffer deadlocks. Timeout watchdog tasks are cancelled immediately upon child completion to prevent task leaks.
16. **UI Event Coalescing Flush Synchronization (F-15):** `UIEventCoalescer.flush()` awaits both pending scheduled requests and active in-flight executions (`(hasPendingRequest || isExecuting)`), ensuring callers observe settled state.
17. **Session Storage Resurrection (F-16):** When receiving an event for an evicted in-memory session, `SessionManager` restores the session from `storageDelegate` (SQLite), preserving original window IDs, process IDs, workspace, and origin bundle without creating empty placeholder sessions.
18. **Bounded IPC Client Socket Options (F-17):** `IPCClient` sets `SO_RCVTIMEO` and `SO_SNDTIMEO` (10s) and `SO_NOSIGPIPE` on Unix domain sockets, preventing indefinite CLI hangs if the daemon is stalled.
19. **Stable Event Column Projections (F-18):** `EventRepository` queries use explicit column projection `eventColumnsProjection` and `mapRowToEvent`, eliminating fragile `SELECT *` positional column lookups.
20. **Background Subprocess & Storage Throttling (F-19):** `AntigravityCLIProvider` caches probed CLI binary versions with mtime validation. `FlowbackService` throttles database retention pruning to once per hour to eliminate unnecessary background SQLite write transactions and subprocess launches.
21. **Deterministic Secret Sanitization (F-20):** `SecretSanitizer` scrubs API keys, bearer tokens, passwords, and sensitive keys from `AgentEvent.metadata` and `TimelineTracker` before persistence and UI publication.
22. **macOS Cooperative Activation & Terminal Coverage (F-21):** `ApplicationController.activate` unhides hidden applications and uses cooperative activation (`activate(from:options:)`). `TerminalAdapter` adds support for Alacritty, Kitty, and WezTerm.
23. **Modern Settings Extension Deep-Links (F-22):** `PermissionManager` provides deep-links to modern macOS 13+ Notification Settings extensions (`com.apple.Notifications-Settings.extension`) with legacy preference pane fallback.
24. **Offline Doctor Environment Diagnostics (F-23):** `flowback doctor` provides offline inspection of local storage, permissions, hooks, and CLI tools when the daemon is not running.
25. **Focus Cancellation Ownership & Monotonic Generation IDs (F-24):** `FocusController` associates active cancellation handlers with monotonic generation IDs, preventing superseded navigation requests from clearing newer cancellation handlers upon actor reentrancy. Ensured cooperative cancellation propagation to child worker tasks.
26. **Deterministic LaunchServices Fallback & Main-Thread Safety (F-25):** `ApplicationController` provides non-blocking asynchronous fallback via `NSWorkspace.openApplication` when direct AppKit activation fails, explicitly avoiding blocking main thread semaphores to eliminate UI deadlocks.
27. **Thread-Safe TimeoutCoordinator State Machine (F-26):** `TimeoutCoordinator` guards concurrency state transitions under `NSLock`, guaranteeing continuations resume at most once, capturing tasks under lock, executing cancellations outside lock, and immediately purging child task handles upon terminal state.
28. **Menu Bar Session Ordering Stability (F-27):** `MenuBarController` freezes recent session ordering into an immutable snapshot upon menu opening, preserving stable keyboard shortcuts (⌘1–⌘9) even during concurrent multi-agent completions.

