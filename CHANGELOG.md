# Changelog

All notable changes to Flowback will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.0.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

---

## [1.0.0] - 2026-10-16

### Added
* **Universal Agent Providers:**
  * Official Antigravity provider supporting `PreInvocation`, `PostInvocation`, and `Stop` hooks with `fullyIdle=true` priority translation.
  * Proactive background agent discovery scanning running agent transcripts and live sessions.
  * Claude Code provider with terminal session lifecycle integration.
  * OpenAI Codex provider with process observation and status translation.
  * Gemini CLI and Aider integrations.
  * Generic JSON Hook Protocol (v1 schema) communicating over local Unix domain socket (`~/.flowback/flowback.sock`).
* **Editor & Terminal Adapters:**
  * VS Code family adapter supporting standard VS Code (`com.microsoft.VSCode`), VS Code Insiders (`com.microsoft.VSCodeInsiders`), VSCodium (`com.vscodium`), Positron (`co.posit.positron`), Windsurf (`com.codeium.windsurf`), and Trae (`com.byteplus.trae`).
  * Cursor adapter (`com.todesktop.230313mzl4w4u92` and `co.anysphere.cursor`).
  * Native terminal adapters for Apple Terminal, iTerm2, Kitty, Alacritty, Ghostty, and Warp.
  * Browser context capture for Brave, Google Chrome, Safari, Microsoft Edge, and Arc.
* **Focus Engine & Attention Arbiter:**
  * User Intent Engine using `CGEventSource` to detect user typing activity (< 5-second threshold) and suppress unwanted focus theft.
  * Priority-ordered Attention Arbiter (`permissionRequired` > `failure` > `completed` > `waiting` > `informational`).
  * Focus cooldown (1000ms window) and multi-agent completion aggregation to eliminate rapid window thrashing.
  * Focus Lock mode (15m, 30m, 45m, 1h, indefinite) to silence focus-switching while preserving notification delivery.
  * Section 14 window restoration hierarchy: Window ID → Workspace/Title matching → Process ID → Bundle Identifier → Graceful fallback.
* **Storage & Reliability:**
  * SQLite persistence engine with Write-Ahead Logging (WAL) mode at `~/.flowback/flowback.sqlite`.
  * Automatic schema migration runner and automatic database corruption recovery.
  * Startup and wake reconciliation to cleanly clean up orphaned background sessions.
* **Interface & Tooling:**
  * Status bar menu item showing active agent count, ⌘1–⌘9 quick restoration, Focus Lock toggles, and live diagnostics.
  * Native SwiftUI Dashboard with Session Timeline, Agent status, and Provider Health monitoring.
  * Native CLI executable `flowback` (`doctor`, `status`, `refresh`, `focus-lock`, `emit`, `test-focus`).
  * Standalone verification test harness (`FlowbackTestRunner`) executing 61 deterministic unit and integration test assertions.

### Changed
* Unified socket IPC handler to stream multi-chunk responses cleanly across POSIX buffer boundaries.
* Optimized SQLite parameter binding with `SQLITE_TRANSIENT` to prevent transient string memory faults under rapid concurrent session updates.
* Enhanced Antigravity lifecycle hooks with automatic backup and atomic registration in `~/.gemini/config/hooks.json`.

### Fixed
* Fixed issue where rapid simultaneous completions from multiple agents caused desktop window thrashing.
* Fixed socket connection hang when processing multi-kilobyte JSON hook payloads.
* Resolved memory lifetime issue during rapid session metadata writes to SQLite.
* Prevented focus restoration attempts into fullscreen presentation apps (e.g., Keynote or full-screen video players).

### Security
* Hardened Unix domain socket permissions to `0600` (strictly readable and writable by the invoking user).
* Ensured zero outbound network connections, zero telemetry, and zero collection of code or secrets.
* Configured Hardened Runtime entitlements with minimal Apple Events coordination (`com.apple.security.automation.apple-events`).

### Known Limitations
* Window raising across distinct macOS Spaces is constrained by macOS window server security policies; Flowback defaults to activating the target application on the current space unless Space switching is explicitly enabled in Settings.
* Running without Accessibility permissions (`AXUIElement`) will gracefully fall back to application-level switching rather than specific window raising.
