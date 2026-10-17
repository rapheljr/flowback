# Flowback Comprehensive Source Audit & Verified Remediation Report

**Date:** October 2026  
**Auditor:** Principal macOS Systems Architect & Senior Swift Security/Performance Engineer  
**Reference Project:** `/Users/abin/workspace/projects/vorssaint-utils` (Strict Read-Only Reference)  
**Target Project:** `/Users/abin/workspace/projects/flowback`  
**Toolchain:** macOS 26.7.1 (25G241), arm64, Apple Swift 6.4 (swiftlang-6.4.0.34.1), SwiftLint Strict  

---

## 1. Executive Summary

This comprehensive source-level audit and verified remediation of **Flowback** systematically analyzed all core targets: `FlowbackCore`, `FlowbackFocus`, `FlowbackProviders`, `FlowbackServer`, `FlowbackStorage`, `FlowbackCLI`, `FlowbackApp`, `FlowbackUI`, and `FlowbackTestRunner`. Using the local macOS utility project **Vorssaint** as an architectural design reference, proven macOS systems patterns were selectively evaluated and independently adapted to elevate Flowback's concurrency, reliability, performance, data integrity, and privacy posture.

### Audit & Remediation Findings Summary
* **Total Audit Findings Assessed:** 23 findings (F-01 through F-23) + Condition 1 (C-01)
* **Confirmed & Remediated in Current Audit:** 10 findings (F-14 through F-23)
* **Confirmed & Preserved from Baseline:** 13 findings (F-01 through F-13) + Condition 1 (C-01)
* **Deferred Findings / Unresolved Bugs:** 0
* **Rejected Hypotheses:** 0
* **Verification Pass Rate:** 100% (608/608 standalone tests, 12/12 OpenCode JS tests, 0 SwiftLint violations, Debug and Release builds clean)

---

## 2. Vorssaint Pattern Evaluation & Selective Adaptation

| Architectural Pattern | Vorssaint Implementation | Flowback Baseline State | Audit Assessment & Action |
| :--- | :--- | :--- | :--- |
| **Bounded Streaming Process Runner** | `BoundedProcessRunner.swift` drains stdout continuously via `readabilityHandler` into bounded memory buffers (`limit: Int`). | `AsyncProcessRunner.swift` read pipes synchronously in `terminationHandler` via `readDataToEndOfFile()`. | **Adapted (F-14):** Prevents child process deadlock on 64KB pipe buffer; limits memory usage and cancels watchdog timer on finish. |
| **Coalesced Action Flush Settling** | Serial execution queues drain completely before reporting settled state. | `UIEventCoalescer.flush()` only looped while `hasPendingRequest`, ignoring in-flight `isExecuting`. | **Adapted (F-15):** `flush()` loops while `(hasPendingRequest \|\| isExecuting) && !isStopped`, guaranteeing complete execution completion. |
| **Session Cache Eviction & Recovery** | Ephemeral caches fall back to durable persistence upon cache misses. | `SessionManager.handleEvent` only checked in-memory dictionary; evicted sessions were recreated as blank startings. | **Adapted (F-16):** Resurrects cold/evicted sessions from `SessionStorageDelegate`, preserving window ID, bundle ID, and workspace. |
| **IPC Client Timeout Safeguards** | All socket and process operations enforce strict timeouts. | `IPCClient.swift` set no socket timeouts, risking indefinite CLI hangs on daemon stall. | **Adapted (F-17):** Implemented `SO_RCVTIMEO`, `SO_SNDTIMEO` (10s), and `SO_NOSIGPIPE` on Unix domain sockets. |
| **Schema Drift Protection** | Strict structural decoders for database queries. | `EventRepository.swift` used fragile `SELECT *` with positional index mapping. | **Adapted (F-18):** Established `eventColumnsProjection` and `mapRowToEvent` matching `SessionRepository` pattern. |
| **Resource & Wakeup Throttling** | Avoids redundant polling, file reads, and subprocess launches. | Periodic UI refresh executed database pruning write queries and spawned `agy --version` every 10 seconds. | **Adapted (F-19):** Cached binary version with mtime validation in `AntigravityCLIProvider` and throttled DB pruning to hourly. |
| **Secret & Credential Redaction** | `PRIVACY.md` guidelines; zero secrets logged or persisted. | Metadata and timeline details recorded plaintext API keys and bearer tokens. | **Adapted (F-20):** Introduced `SecretSanitizer` in `FlowbackCore` to sanitize tokens and keys across events and timeline. |
| **macOS Application Unhide & Activation** | Unhides hidden apps and invokes cooperative activation. | Bare `activate(options: [])` failed to unhide hidden terminal apps; lacked modern terminal emulator bundles. | **Adapted (F-21):** Added `application.unhide()`, cooperative activation, and bundle support for Alacritty, Kitty, and WezTerm. |
| **Modern macOS Settings Deep-Links** | Uses modern `.extension` deep-links on macOS 13+. | Hardcoded deprecated `com.apple.preference.notifications` pane path. | **Adapted (F-22):** Deep-links to `com.apple.Notifications-Settings.extension` with legacy preference pane fallback. |
| **Offline Diagnostics (`doctor`)** | Diagnostic commands inspect local state even when daemons are offline. | `flowback doctor` failed immediately with error if daemon socket was offline. | **Adapted (F-23):** Added comprehensive offline diagnostics (storage, permissions, hooks, CLI tools in PATH). |

---

## 3. Findings Register & Remediation Inventory

### Finding F-14: AsyncProcessRunner Pipe Deadlock & Watchdog Task Leak
* **Severity:** High | **Confidence:** Confirmed
* **File:** `Sources/FlowbackCore/Services/AsyncProcessRunner.swift`
* **Defect:** Reading pipe data in `terminationHandler` blocked if child process output exceeded the 64KB kernel pipe buffer, causing child processes to hang indefinitely until watchdog timeout. In addition, watchdog sleep tasks were never cancelled upon normal exit.
* **Remediation:** Switched to streaming drainage via `readabilityHandler` on stdout and stderr pipes, enforced bounded buffer capping (`maxOutputBytes: 1MB`), and cancelled watchdog task immediately upon child termination.
* **Verification:** `F-14: AsyncProcessRunner Bounded Streaming & Watchdog Safety` verified with >150KB output streams, byte capping, and watchdog cancellation.

### Finding F-15: UIEventCoalescer Flush Race Condition
* **Severity:** High | **Confidence:** Confirmed
* **File:** `Sources/FlowbackCore/Services/UIEventCoalescer.swift`
* **Defect:** `flush()` loop condition `while hasPendingRequest && !isStopped` returned prematurely if called while an action was actively executing (`isExecuting == true`) and `hasPendingRequest == false`.
* **Remediation:** Updated loop condition to `while (hasPendingRequest || isExecuting) && !isStopped`, cooperatively yielding until in-flight execution completes and all coalesced requests settle.
* **Verification:** `F-15: UIEventCoalescer Flush Synchronization` verified that `flush()` blocks until active in-flight execution finishes.

### Finding F-16: SessionManager Eviction & Origin Context Destruction
* **Severity:** High | **Confidence:** Confirmed
* **File:** `Sources/FlowbackCore/Sessions/SessionManager.swift`
* **Defect:** When receiving an event for a completed or evicted session (due to 100-session in-memory limit), `handleEvent` created a blank replacement session with `state: .starting`, destroying original window IDs, bundle ID, and workspace path.
* **Remediation:** Look up session from `storageDelegate` (SQLite) upon in-memory cache miss, preserving historical identity, origin context, window ID, and workspace.
* **Verification:** `F-16: Session Eviction & Storage Resurrection` verified resurrection of cold sessions with preserved window ID, workspace, and origin bundle.

### Finding F-17: IPCClient Unbounded Socket Blocking
* **Severity:** High | **Confidence:** Confirmed
* **File:** `Sources/FlowbackCore/IPC/IPCClient.swift`
* **Defect:** CLI client lacked socket read/write timeouts and signal safety, blocking indefinitely in `read()` if the daemon stalled.
* **Remediation:** Configured `SO_RCVTIMEO`, `SO_SNDTIMEO` (default 10.0s), and `SO_NOSIGPIPE`, moving `IPCClient` into `FlowbackCore/IPC` for universal client access.
* **Verification:** `F-17: IPCClient Socket Options & Timeouts` verified configurable timeouts and non-hanging error handling.

### Finding F-18: EventRepository Positional SQL Column Fragility
* **Severity:** Medium | **Confidence:** Confirmed
* **File:** `Sources/FlowbackStorage/Repositories/EventRepository.swift`
* **Defect:** `fetchEvents` utilized `SELECT *` with hardcoded column indices, susceptible to schema drift.
* **Remediation:** Established explicit projection `eventColumnsProjection` and `mapRowToEvent` mapping helper.
* **Verification:** `F-18: EventRepository Column Projection` verified explicit projection parsing and metadata mapping.

### Finding F-19: Periodic Subprocess Spawning & Redundant DB Write Pruning
* **Severity:** Medium | **Confidence:** Confirmed
* **Files:** `Sources/FlowbackApp/FlowbackService.swift`, `Sources/FlowbackProviders/AntigravityCLI/AntigravityCLIProvider.swift`
* **Defect:** Background UI refresh scheduled every 10 seconds executed SQLite write transactions for session pruning and spawned `agy --version` 360 times/hour.
* **Remediation:** Added `VersionCache` in `AntigravityCLIProvider` validating binary modification date (`mtime`), and throttled `pruneCompletedSessions` in `FlowbackService` to run at most once per hour.
* **Verification:** `F-19: Background Subprocess & Maintenance Throttling` verified version caching across multiple health checks.

### Finding F-20: Plaintext Secret & Token Exposure
* **Severity:** Medium | **Confidence:** Confirmed
* **Files:** `Sources/FlowbackCore/Services/SecretSanitizer.swift`, `AgentEvent.swift`, `TimelineTracker.swift`
* **Defect:** Event metadata and timeline entries stored and displayed unredacted credentials, API keys, and bearer tokens.
* **Remediation:** Built `SecretSanitizer` in `FlowbackCore` to scrub sensitive dictionary keys and free-text token patterns (`Bearer ...`, `sk-...`, `ghp_...`).
* **Verification:** `F-20: SecretSanitizer Redaction Invariant` verified redaction across metadata, free text, and `AgentEvent.init`.

### Finding F-21: macOS Focus Unhide & Terminal Emulator Gaps
* **Severity:** Medium | **Confidence:** Confirmed
* **Files:** `Sources/FlowbackFocus/ApplicationController.swift`, `TerminalAdapter.swift`
* **Defect:** Activation failed to unhide hidden applications; `TerminalAdapter` omitted popular terminal emulators (Alacritty, Kitty, WezTerm).
* **Remediation:** Added `application.unhide()`, cooperative activation (`activate(from:options:)`), and registered `org.alacritty`, `net.kovidgoyal.kitty`, and `com.github.wez.wezterm`.
* **Verification:** `F-21: macOS Focus & Terminal Emulator Coverage` verified support across all registered terminal bundles.

### Finding F-22: Deprecated Notification Settings Deep-Link
* **Severity:** Low | **Confidence:** Confirmed
* **File:** `Sources/FlowbackCore/Services/PermissionManager.swift`
* **Defect:** Used pre-macOS 13 preference pane path `com.apple.preference.notifications` rather than modern System Settings extension.
* **Remediation:** Added `modernNotificationSettingsURL` targeting `com.apple.Notifications-Settings.extension` with legacy fallback.
* **Verification:** `F-22: Notification Settings Extension Deep-Link` verified URL resolution.

### Finding F-23: Offline `flowback doctor` Failure
* **Severity:** Medium | **Confidence:** Confirmed
* **File:** `Sources/FlowbackCLI/main.swift`
* **Defect:** `flowback doctor` failed immediately when daemon was offline instead of diagnosing the environment.
* **Remediation:** Provided comprehensive offline diagnostics inspecting storage directory, database, hook configs, and CLI binaries in PATH.
* **Verification:** Smoke-tested `swift run flowback-cli doctor` in offline state.

---

## 4. Verification Matrix

| Check / Test Suite | Scope | Result | Observed Evidence |
| :--- | :--- | :--- | :--- |
| `swiftlint lint --strict` | Static code analysis & style | **PASS** | 99 files checked, 0 violations, 0 serious errors. |
| `swift build` (Debug) | Incremental & full package compilation | **PASS** | Built all targets clean with 0 warnings. |
| `swift build -c release` | Optimized release binary compilation | **PASS** | Built all targets clean in release mode. |
| `FlowbackTestRunner` | Full standalone verification suite | **PASS** | **608 passed, 0 failed, 0 errors.** |
| `node Scripts/test_opencode_plugin.js` | OpenCode JS hook plugin & IPC | **PASS** | **12 passed, 0 failed.** |
| `swift run flowback-cli doctor` | CLI offline diagnostics smoke test | **PASS** | Successfully reported offline filesystem, hooks, and CLI tools. |
| Markdown link verification | Documentation integrity | **PASS** | 21 root markdown documents validated. |
| `git -C /vorssaint-utils status` | Reference safety rule | **PASS** | Clean working tree; zero files modified or touched. |
| `git status --short --branch` | Target repository safety rule | **PASS** | Only intentional Flowback changes; zero commits/pushes made. |

---

## 5. Repository Safety Record

1. **Reference Repository (`/vorssaint-utils`):**
   * Remained **STRICTLY READ-ONLY**.
   * Zero files edited, created, or deleted.
   * Git HEAD: `125167ae2264d7c9c51c3a5b4d6cbad471e35a24` on `main`.
2. **Target Repository (`/projects/flowback`):**
   * Working on branch `main` at HEAD `e7979de55e63018947a10be73f06b7b63c004f07`.
   * Existing user modifications preserved.
   * **No commits, pushes, releases, or destructive Git operations were executed.**
