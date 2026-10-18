# Changelog

All notable changes to Flowback will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.0.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html) under a pre-1.0 development policy.

---

## [Unreleased]

---

## [0.4.1] - 2026-10-18

### Fixed
* **Focus Cancellation Ownership & Actor Reentrancy (F-01):**
  * Associated active cancellation handlers with monotonic generation IDs, preventing superseded navigation requests from clearing newer cancellation handlers upon actor reentrancy.
  * Ensured prompt cooperative cancellation propagation to child worker tasks upon arrival of newer navigation requests.
* **Deterministic LaunchServices Fallback & Main-Thread Safety (F-02):**
  * Added non-blocking asynchronous fallback via `NSWorkspace.openApplication` when direct AppKit activation fails.
  * Synchronous fallback path explicitly avoids blocking the main thread on semaphores to eliminate UI deadlocks.
* **TimeoutCoordinator Concurrency State Machine:**
  * Strict thread-safe state transitions guarded by `NSLock`.
  * Guarantees continuations resume at most once, captures continuations and tasks under lock, and executes resumptions and task cancellations outside the lock.
  * Automatically purges child task handles upon reaching terminal completion to prevent retain cycles.
* **Menu Bar Session Stability:**
  * Freezes recent session ordering into an immutable snapshot upon menu opening, preserving stable keyboard shortcuts (⌘1–⌘9).
* **Adapter Precedence:**
  * Enforced stable FIFO ordering for specialized application adapters with `GenericApplicationAdapter` pinned at baseline priority.

---

## [0.4.0] - 2026-10-18

### Added
* **macOS Card Design System & Accessibility:**
  * Modern macOS Card Design System (`CardView`, `ThemeTokens`) compliant with Apple Human Interface Guidelines and WCAG AA contrast standards.
  * Verified 10 UI surfaces in light, dark, and increased contrast modes with automated AppKit screenshot renders.
* **Expanded Provider Integrations:**
  * Ported native **GitHub Copilot** provider (`CopilotProvider`) with process resolution and editor window targeting.
* **General Sidebar Destinations:**
  * Four general sidebar destinations: **Advanced Settings** (cooldown slider, launch at login, defaults reset), **What's New** (dynamic release notes feed), **Support** (privacy-sanitized diagnostic exporter and Buy Me a Coffee links), and **About Flowback** (version metadata and embedded MIT license sheet).
* **Navigation & Safety:**
  * Back/forward toolbar navigation stack with persistent history.
  * Permissions reset confirmation sheet restoring factory configuration safely.
  * Privacy-guaranteed diagnostic exporter (`DiagnosticReportExporter`) scrubbing Bearer tokens, passwords, private keys, and user home paths.
* **Canonical Versioning & Verification:**
  * Authoritative canonical versioning in `FlowbackVersion.swift` and root `VERSION` file (`0.4.0`).
  * Expanded deterministic test harness (`FlowbackTestRunner`) executing **914 assertions across 24 test suites**.
  * Pre-flight local verification script (`Scripts/verify_all.sh`) validating SwiftLint, compilation, tests, and documentation links.

### Changed
* Silenced Command Line Tools search path linker warnings and updated AppKit activation APIs for macOS Sequoia.

### Fixed
* Fixed transcript parser escaping for JSON newlines and stripped redundant project path prefixes.
* Corrected AppKit menu bar shortcut conflicts between active conversation shortcuts and system navigation.

---

## [0.3.0] - 2026-10-17

### Added
* **Conversation-Aware Focus & Identity:**
  * Conversation-aware identity and transcript parsing (`BrainTranscriptParser`) mapping agent events directly to specific conversation threads.
  * Exact focus restoration semantics prioritizing active conversation workspaces.
* **Storage Engine v2:**
  * SQLite Schema v2 introducing `conversation_id`, `conversation_title`, and `metadata_json` with automated migration runner and rollback safety.
  * Hardened WAL recovery preserving journals during degraded mode.
* **UI Event Coalescing:**
  * High-frequency event burst coalescer (`UIEventCoalescer`) throttling up to 1,000 multi-agent events into single bounded UI passes with 99.9% dispatch reduction.

### Changed
* Hardened process execution runner (`AsyncProcessRunner`) with non-blocking stream handling to prevent deadlock on large pipe buffers (>100KB).

### Fixed
* Resolved multi-turn session reactivation and stale discovery protection.
* Addressed architectural findings F-01 through F-13.

---

## [0.2.0] - 2026-10-17

### Added
* **Multi-Agent Provider Expansion:**
  * Native background agent integration for **Windsurf** (`WindsurfProvider`), **OpenCode** (`OpenCodeProvider`), and **Cursor** (`CursorProvider`).
  * Official **Antigravity CLI** (`agy`) provider transitioning from legacy Gemini CLI with full lifecycle hooks.
  * Comprehensive regression test suites for Windsurf, OpenCode, Cursor, and Antigravity CLI.
* **Cloud Agent Transitions:**
  * Propagated discovered cloud agent terminal transitions and exempted remote sessions from wake cancellation.

### Fixed
* Remediated lifecycle, installation, and reliability defects in OpenCode, Cursor, and Windsurf providers.
* Resolved CI workspace detection in Cursor provider and satisfied SwiftLint requirements.

---

## [0.1.2] - 2026-10-17

### Added
* **Distribution & Tooling:**
  * Homebrew CLI formula (`Formula/flowback-cli.rb`) and release signing invariant enforcement in CI.
  * Staged Homebrew Cask formula generator (`Scripts/generate_cask.sh`).
  * Release artifact packager, validator, and checksum generator (`validate_release.sh`).
* **Service Hardening:**
  * Enforced Unix domain socket directory permissions (`0700`) and required session auth token for daemon shutdown.
  * Implemented lifecycle coordinator, stream teardown, and granular launch-at-login status (`bd514c0`).
* **Expanded Test Invariants:**
  * Expanded test runner to 182 assertions covering service lifecycle, storage, and IPC invariants (`cdcd2d0`).

### Fixed
* Eliminated AppKit application termination race during fast service shutdown.
* Preserved WAL journals during corruption recovery and surfaced degraded mode in UI (`7ea9ef6`).

---

## [0.1.1] - 2026-10-16

### Added
* Production brand identity, logo design system, and verification toolchain (`d8186a3`).
* Workflow dispatch manual trigger to release automation (`3b2c454`).

### Changed
* Audited and remediated Apple Human Interface Guidelines compliance and native macOS UX (`a67ea13`).
* Made SQLiteDatabase bindings Sendable for concurrency safety (`ba471fe`).

### Fixed
* Passed `mockAppController` to `UserIntentEngine` across all unit and integration test suites (`2ac4a9a`).
* Added CI fallback for active session discovery (`499da85`).

---

## [0.1.0] - 2026-10-16

### Added
* **Deterministic Focus Pipeline:** 12-step arbitration pipeline with process liveness protection and cooldown deferral (`9d84339`).
* **Standalone Daemon & CLI Flags:** Added `--daemon`, `--headless`, `--version`, and `--help` dispatch resolving standalone executable launch crash (`ea1e756`).
* **Socket Security Hardening:** Hardened Unix domain socket IPC with peer UID authentication (`getpeereid`), duplicate daemon prevention (`EADDRINUSE`), and bounded 2MB payloads (`7a190c9`).
* **Provider Tiers & Path Resolution:** Added `ProviderSupportLevel` tiers and dynamic user home directory resolution (`af56801`).
* **Database Pruning & In-Memory Storage:** Session and event retention pruning; in-memory SQLite support for tests (`793a430`).
* **Test Runner Expansion:** Test runner expanded from 61 to 89 tests across 17 test suites (`2ba8fd5`).

---

## [0.0.1] - 2026-09-15

### Added
* **First Working Prototype:** End-to-end agent event detection, IPC socket routing, and window focus restoration.
* **Proactive Agent Discovery:** Background session discovery scanning running process tables for Antigravity IDE instances (`ac0e48f`).
* **IPC Streaming & Framing:** Multi-chunk Unix domain socket streaming across POSIX buffer boundaries (`35caa54`).
* **Safe SQLite Persistence:** Transactional SQLite database with `SQLITE_TRANSIENT` memory protection (`35caa54`).
* **Deep Audit Test Suite:** Test suite expanded from 37 initial assertions to 61 assertions covering state transitions, socket IPC, and SQLite transactions (`35caa54`).
