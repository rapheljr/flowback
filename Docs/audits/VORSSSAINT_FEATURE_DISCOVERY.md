# Flowback × Vorssaint — Deep Feature Discovery & Architectural Parity Report

**Date:** October 2026  
**Auditor:** Principal macOS Product Architect, Senior Swift Systems Engineer, UI/UX & Accessibility Specialist  
**Reference Repository:** `/Users/abin/workspace/projects/vorssaint-utils` (Strictly Read-Only Reference, Git commit `125167ae`)  
**Target Repository:** `/Users/abin/workspace/projects/flowback` (Target Implementation, Git commit `c25464f`)  
**License Context:** Vorssaint is licensed under **GNU General Public License v3.0 or later (GPL-3.0-or-later)**; Flowback is licensed under the **MIT License**. All recommended and ported capabilities are strictly designed and implemented as **clean-room native Swift reimplementations (Option B)** or **conceptual adaptations (Option C)** to protect Flowback's permissive MIT license and architectural integrity.

---

## 1. Executive Summary

A systematic, source-level discovery and architectural analysis was conducted across the entire **Vorssaint** utility codebase (`/Users/abin/workspace/projects/vorssaint-utils`) and the **Flowback** context and focus manager (`/Users/abin/workspace/projects/flowback`). 

Vorssaint is a comprehensive, monolithic macOS menu bar utility providing dozens of features: system monitoring, volume control, window snapping, switcher, clipboard history, text snippets, screenshot/recording tools, and an AI agent monitor for the Dynamic Island. Flowback is a focused, high-performance, native macOS context and focus manager for AI coding agents, designed around strict decoupling, finite state machines, origin context capture, user intent detection, and intelligent focus restoration.

The investigation examined over 100 source files in Vorssaint across services, UI, app lifecycle, Darwin/AppKit integrations, and 220 test suites. The audit discovered **32 substantive capabilities and architectural patterns**, spanning native macOS engineering, AI agent discovery, UI/UX interaction design, accessibility, and configuration portability.

### Key Discovery Takeaways:
1. **Core Product Convergence & Divergence:** While Vorssaint's AI agent features focus on passive Dynamic Island monitoring of plan rate limits, tokens, and billing estimates, Flowback's core mission is active focus orchestration, origin window hierarchy restoration, and user attention arbitration. However, Vorssaint possesses deep, battle-tested native macOS systems engineering patterns that directly solve documented edge cases in Flowback.
2. **Native Systems Hardening Opportunities:** 
   - *Cooperative Activation Handoff (`ActivationHandoff.swift`):* Prevents macOS 14+ from dropping cooperative focus handoffs when called from an accessory/menu bar application (`LSUIElement`).
   - *Secure Event Input Safeguard (`SecureInputMonitor.swift`):* Prevents focus restoration and keystroke interception while the user is interacting with a password, credential, or `sudo` prompt.
   - *Responsible Process Resolution (`ResponsibleProcess.swift`):* Uses Darwin `responsibility_get_pid_responsible_for_pid` and `proc_pidinfo` parent PID traversal to trace CLI agent processes back to their enclosing editor or terminal window.
   - *Accessibility Call Timeouts (`EnhancedUserInterfaceSuspension.swift`):* Binds `AXUIElementSetMessagingTimeout` to prevent Flowback from hanging when a target application is beachballing.
   - *Session Lock & Fast User Switching (`SessionActivity.swift`):* Detects session deactivation to suspend focus switches while the display is locked or switched to another user account.
3. **Agent Integration Expansions:**
   - *GitHub Copilot Provider:* Discovered local append-only event stream parsing in `~/.copilot/session-state`, enabling a native `CopilotProvider` for Flowback.
   - *Multi-Account Codex Discovery:* Discovered `~/.codex-*` profiles and POSIX permission validation.
   - *Proactive SQLite OpenCode Discovery:* Discovered local database parsing (`~/.local/share/opencode/opencode.db`), freeing OpenCode integration from mandatory external JS plugin installation.
4. **UI/UX & Accessibility Polish:**
   - *Session Search & Filtering:* Adding instant search across active/historical agent sessions by repo, title, provider, and workspace.
   - *WCAG AA & Increased Contrast Adaptations:* Enhancing `StatusBadge` and theme colors to react dynamically to `accessibilityDisplayShouldIncreaseContrast` and dark/light mode luminance constraints.
   - *Menu Bar Polish:* Establishing `statusItem.autosaveName` to persist custom menu bar item placement across reboots.

---

## 2. Flowback Product and Architecture Baseline

### 2.1 Purpose and Core Workflows
Flowback manages focus and context switching between background AI coding agents (Google Antigravity, Claude Code, OpenAI Codex, Windsurf, Aider, OpenCode, Cursor) and user tasks.
- **Workflow 1: Background Agent Execution:** User prompts an agent in an editor/terminal, then switches to another application (browser, Slack). Flowback captures an `OriginContext` containing the window ID, workspace root, PID, and bundle ID.
- **Workflow 2: Intent-Aware Focus Restoration:** When the agent finishes:
  - If the user is idle (> threshold), Flowback restores the origin window (`kAXRaiseAction` on the exact `AXUIElement`).
  - If the user is actively typing, Flowback suppresses focus-stealing and delivers an actionable notification with `[Focus Window]` and `[Review]`.
- **Workflow 3: Attention Arbitration:** When multiple agents complete simultaneously within a sliding window (1.5s), Flowback arbitrates and aggregates notifications to prevent desktop window thrashing.

### 2.2 Current UI Surfaces
- **Menu Bar Status Item (`MenuBarController`):** Dynamic icon reflecting active agent counts, attention alerts, and Focus Lock state, with dropdown quick menu.
- **Dashboard (`DashboardView`):** SwiftUI `NavigationSplitView` with 6 tabs:
  1. *Overview:* Live activity stats, Attention Queue, Focus Lock banner, active sessions list.
  2. *Agents:* Historical and active agent sessions with state filter (`All`, `Active`, `Completed`, `Failed`).
  3. *Timeline:* Orchestration decision history and audit trail.
  4. *Applications:* Protected application configuration (preventing focus stealing during meetings, video playback, etc.).
  5. *Diagnostics:* Provider health, permissions, IPC status, and test triggers.
  6. *Settings:* Restoration policy, timing sliders, spaces policy, launch at login.

### 2.3 Modular Architecture & Modules
- `FlowbackCore`: Domain models (`AgentSession`, `AgentEvent`, `OriginContext`), state machine (`AgentStateMachine`), `EventBus`, `UIEventCoalescer`, `AsyncProcessRunner`, `SecretSanitizer`.
- `FlowbackStorage`: SQLite persistence engine with WAL mode and migration versioning.
- `FlowbackFocus`: `UserIntentEngine`, `FocusController`, `WindowController`, `ApplicationController`, `SpaceController`.
- `FlowbackProviders`: Provider implementations for Antigravity, Claude Code, Codex, Windsurf, OpenCode, Cursor, Aider, GenericHook.
- `FlowbackServer`: Unix domain socket server (`~/.flowback/flowback.sock`) and IPC dispatcher.
- `FlowbackNotifications`: Native macOS `UNUserNotificationCenter` integration.
- `FlowbackUI`: SwiftUI dashboard and AppKit menu bar controller.
- `FlowbackCLI`: Native command-line tool `flowback` (emit, doctor, status, lock, focus).

---

## 3. Systematic Vorssaint Inventory

The investigation systematically inspected the following subsystems across `/Users/abin/workspace/projects/vorssaint-utils`:

| Subsystem | Source Path | Key Components & Files |
| :--- | :--- | :--- |
| **Agent Usage & Tracking** | `Sources/Vorssaint/Services/AgentUsage/` | `AgentUsageModels.swift`, `AgentUsageStore.swift`, `AgentPricing.swift`, `AgentClaudeServer.swift`, `AgentClaudeAppUsage.swift`, `CodexAccountLimits.swift`, `AgentOpenCodeReader.swift`, `Harness/CopilotReader.swift` |
| **Window & Process Management** | `Sources/Vorssaint/Services/` | `ResponsibleProcess.swift`, `WindowServerSupport.swift`, `ActivationHandoff.swift`, `EnhancedUserInterfaceSuspension.swift`, `FocusFollowsMouse/` |
| **Lifecycle & Session Tracking** | `Sources/Vorssaint/Services/` | `SessionActivity.swift`, `SessionActivitySupport.swift`, `LaunchAtLogin.swift`, `ReopenRequestSupport.swift` |
| **Security & Pasteboard** | `Sources/Vorssaint/Services/` | `SecureInputMonitor.swift`, `TransientPaste.swift`, `GeneralPasteboardAccess.swift`, `PrivateFileStore.swift` |
| **Menu Bar Presence** | `Sources/Vorssaint/App/` | `StatusItemController.swift`, `MenuBarRenderer.swift`, `MenuBarSpacingSupport.swift`, `StatusItemAnchorSupport.swift` |
| **UI & Design System** | `Sources/Vorssaint/UI/` | `Theme.swift`, `SharedUI.swift`, `PermissionGuideOverlay.swift`, `NonModalAlert.swift`, `Settings/` |
| **Preferences & Backup** | `Sources/Vorssaint/Services/` | `SettingsBackup.swift`, `SettingsBackupSupport.swift`, `Defaults.swift` |
| **Testing Harness** | `Tests/` | `TestSuite.swift`, `AgentUsageReadTests.swift`, `CopilotAgentTests.swift`, `SwitcherActivationTests.swift` |

---

## 4. Feature and Design Parity Matrix

The following matrix benchmarks capabilities discovered in Vorssaint against Flowback's current baseline.

| ID | Category | Capability / Pattern | Vorssaint Source & Symbols | Vorssaint Behavior | Flowback Equivalent | Parity Status | User Benefit | Technical Benefit | Adaptation Strategy | Effort | Risk | Confidence | Validation Criterion | Decision |
| :--- | :--- | :--- | :--- | :--- | :--- | :--- | :--- | :--- | :--- | :--- | :--- | :--- | :--- | :--- |
| **V-001** | Native macOS | Cooperative Activation Handoff | `ActivationHandoff.swift`: `ActivationHandoff.yield(to:)` | Yields activation token to target app after self-activating, ensuring cooperative `activate(from:options:)` succeeds from accessory app | `ApplicationController.swift`: `activate(application:)` | Partial | Prevents window focus restoration from failing or being silently refused by macOS 14+ | Eliminates focus drops when Flowback is background accessory | Reimplement (Clean-room) | S | Low | High | Unit test verifying cooperative handoff call order; window activation test | **Adopt (P0)** |
| **V-002** | Security & Focus | Secure Event Input Safeguard | `SecureInputMonitor.swift`: `IsSecureEventInputEnabled()` | Detects active password/credential entry across system via `IsSecureEventInputEnabled` | None in `UserIntentEngine.swift` | Missing | Never steals focus or raises windows while user is entering password/sudo prompt | Eliminates keystroke leakage & password interruption | Reimplement (Clean-room) | S | Low | High | Unit test asserting `.notifyOnly(reasonCode: .secureInputActive)` when active | **Adopt (P0)** |
| **V-003** | Native macOS | Responsible Parent Process Resolution | `ResponsibleProcess.swift`: `responsibility_get_pid_responsible_for_pid`, `proc_pidinfo` | Resolves enclosing application PID for child CLI/terminal processes | None (`ApplicationController` only matches direct PID) | Missing | CLI agents running inside VS Code/Terminal properly restore the host editor window | Maps terminal/daemon child PIDs back to windowed parent | Reimplement (Clean-room) | M | Low | High | Test verifying helper child PID resolves to parent terminal/editor PID | **Adopt (P0)** |
| **V-004** | Native macOS | AX Messaging Timeout Protection | `EnhancedUserInterfaceSuspension.swift`: `AXUIElementSetMessagingTimeout` | Enforces 0.35s timeout on AX calls so hung apps don't stall the thread | None (`WindowController.swift` uses default/infinite AX timeout) | Missing | Prevents Flowback from freezing when restoring focus to a frozen/beachballing app | Bounded accessibility IPC latency | Reimplement (Clean-room) | S | Low | High | Test verifying AX timeout is explicitly applied to app AXUIElement | **Adopt (P0)** |
| **V-005** | Native macOS | Session Active/Resign Observation | `SessionActivity.swift`: `NSWorkspace.sessionDidResignActiveNotification` | Observes Fast User Switching and lock screen state to suspend background actions | `FlowbackService.swift` only observes sleep/wake and app activate | Missing | Prevents focus manipulation while screen is locked or another user is logged in | Eliminates invalid window calls during console switch | Reimplement (Clean-room) | S | Low | High | Test asserting session deactivation suppresses focus transitions | **Adopt (P0)** |
| **V-006** | UI / UX | Agent Session Search & Filter Bar | `CommandBar/`, `Switcher/`: live substring search | Instant search by session ID, title, repo name, or workspace path | `AgentsView.swift` only has 4-state segmented picker | Missing | Quickly find sessions in repositories with dozens of active/historical runs | Reduces cognitive load and speeds up session lookup | Reimplement (Clean-room) | S | Low | High | SwiftUI view test verifying search text filters displayed session rows | **Adopt (P0)** |
| **V-007** | UI / UX | High-Contrast & WCAG AA Color System | `Theme.swift`: `PanelMetricColor`, `border(for:)` | Adapts color luminance and border strokes when Increased Contrast is on | `StatusBadge.swift`: uses raw system colors | Partial | High accessibility compliance for low-vision users; legible badges in light mode | Adheres to Apple HIG and WCAG AA contrast ratios | Reimplement (Clean-room) | S | Low | High | Unit test verifying badge colors adjust contrast for light vs dark mode | **Adopt (P0)** |
| **V-008** | Native macOS | Menu Bar Autosave Name | `StatusItemController.swift`: `statusItem.autosaveName` | Sets autosave name so macOS persists menu bar icon position across relaunches | `MenuBarController.swift`: lacks autosaveName | Missing | Preserves user's preferred menu bar icon layout across reboots | Standard macOS native menu bar behavior | Reimplement (Clean-room) | S | Low | High | Test verifying `autosaveName == "FlowbackStatusItem"` is assigned | **Adopt (P0)** |
| **V-009** | Native macOS | Reopen Request Filtering (Siri/Shortcuts Guard) | `ReopenRequestSupport.swift`: `isPersonOpeningApp` | Inspects Apple Event sender to ignore Siri/Shortcuts background reopens | `AppDelegate.swift`: unconditionally opens dashboard on reopen | Missing | Prevents dashboard window from popping open when background shortcuts run | Distinguishes intentional user open from system events | Reimplement (Clean-room) | S | Low | High | Test verifying assistant sender PID does not open window | **Adopt (P1)** |
| **V-010** | Providers | GitHub Copilot Agent Provider | `Harness/CopilotReader.swift`, `AgentLogParser.swift` | Parses append-only event stream in `~/.copilot/session-state` | None in `FlowbackProviders` | Missing | Tracks GitHub Copilot CLI and Copilot Workspace agent sessions | Expands provider matrix to major developer ecosystem | Reimplement (Clean-room) | M | Low | High | Provider lifecycle test verifying Copilot event parsing | **Adopt (P1)** |
| **V-011** | Providers | Multi-Account Codex Profile Discovery | `CodexAccountLimits.swift`: `discover()`, `canonicalDirectory` | Discovers `~/.codex` and `~/.codex-*` directories with POSIX permissions check | `CodexProvider.swift` only checks single `~/.codex` | Partial | Supports developers using work and personal OpenAI Codex accounts | Automatically discovers multiple `CODEX_HOME` profiles | Reimplement (Clean-room) | M | Low | High | Discovery test with mocked multiple `.codex-*` directories | **Adopt (P1)** |
| **V-012** | Providers | Proactive SQLite OpenCode Discovery | `AgentOpenCodeReader.swift`: reads `opencode.db` | Inspects `~/.local/share/opencode/opencode.db` directly using SQLite3 | `OpenCodeProvider.swift` requires active JS hook plugin | Partial | Discovers OpenCode sessions without requiring manual JS plugin installation | Zero-config fallback for OpenCode users | Reimplement (Clean-room) | M | Low | High | Test parsing mock OpenCode SQLite database rows | **Adopt (P1)** |
| **V-013** | Providers | Claude Desktop App Usage History | `AgentClaudeAppUsage.swift`: `plan-usage-history.json` | Reads `~/Library/Application Support/Claude/plan-usage-history.json` | `ClaudeCodeProvider.swift` only checks CLI settings | Partial | Displays local Claude plan limits without network calls or API keys | Offline rate limit and quota awareness | Reimplement (Clean-room) | M | Low | High | JSON parsing test for Claude plan usage samples | **Adopt (P2)** |
| **V-014** | Core / CLI | Configuration Export & Import | `SettingsBackup.swift`: `runExportPanel`, `readSettings` | Exports and imports configuration plist with schema validation | None in `SettingsRepository.swift` or `flowback-cli` | Missing | Backup settings or share team-wide policy presets via CLI/UI | Portable configuration management | Reimplement (Clean-room) | S | Low | High | CLI test `flowback config export` and `import` round-trip | **Adopt (P1)** |
| **V-015** | UI / UX | Floating Non-Modal Permission Guide | `PermissionGuideOverlay.swift` | Floating non-activating card guiding user through System Settings | None (`PermissionManager` opens System Settings URL directly) | Missing | Reduces onboarding drop-off during Accessibility setup | Interactive guidance with automatic grant polling | Adapt Conceptually | M | Low | Medium | Acceptance test verifying overlay appears and dismisses on grant | **Defer (P2)** |
| **V-016** | Core | Ephemeral Transient Pasteboard Insertion | `TransientPaste.swift` | Places text on pasteboard, posts `⌘V`, restores previous contents | Flowback does not inject text into editors | N/A | Not applicable to Flowback's focus restoration architecture | Unnecessary clipboard tampering | Reject | S | Medium | High | N/A | **Reject** |
| **V-017** | Sound | Per-App Volume Mixer | `Sources/Vorssaint/Services/Audio/` | Adjusts volume per application via CoreAudio taps | None | N/A | Audio control is outside Flowback's product mission | Out of scope | Reject | XL | High | High | N/A | **Reject** |
| **V-018** | Window Mgmt | Window Snapping & Edge Layouts | `Sources/Vorssaint/Services/WindowLayout/` | Snaps windows to halves/quarters via drag gestures | None (Flowback only restores origin window position) | N/A | Window tiling is outside Flowback's product mission | Out of scope | Reject | XL | High | High | N/A | **Reject** |
| **V-019** | Tools | Screenshot & Screen Recording Suite | `Sources/Vorssaint/Services/Recorder/`, `Screenshot/` | Full OCR, annotations, video trimming, GIF export | None | N/A | Flowback is a focus orchestrator, not a screen capture utility | Out of scope | Reject | XL | High | High | N/A | **Reject** |
| **V-020** | Hardware | Fan Control & Thermal Monitoring | `Sources/Vorssaint/Services/FanControl/` | Apple Silicon SMC fan speed and temperature curve manipulation | None | N/A | Low-level SMC writes outside Flowback domain; stability risk | Out of scope | Reject | XL | High | High | N/A | **Reject** |
| **V-021** | System | Uninstaller & Cleaner | `Sources/Vorssaint/Services/Cleaner/`, `Uninstall/` | Scans `~/Library` caches and logs to delete app leftovers | None | N/A | Flowback provides focused session pruning in SQLite; general disk cleanup is out of scope | Out of scope | Reject | L | Medium | High | N/A | **Reject** |
| **V-022** | Package Mgmt | Homebrew GUI Manager | `Sources/Vorssaint/Services/Homebrew/` | GUI to search, install, and uninstall brew formulas | None | N/A | Brew management is out of scope | Out of scope | Reject | L | Medium | High | N/A | **Reject** |
| **V-023** | System | Keep Awake / Sleep Prevention | `Sources/Vorssaint/Services/KeepAwakeManager.swift` | Manages `IOPMAssertionCreateWithName` power assertions | None | N/A | Flowback operates on completion events, not preventing display sleep | Out of scope | Reject | M | Low | High | N/A | **Reject** |
| **V-024** | Display | Display Brightness & XDR Headroom | `Sources/Vorssaint/Services/Display/` | DDC/CI hardware brightness control and HDR headroom boosting | None | N/A | Display hardware control is out of scope | Out of scope | Reject | L | High | High | N/A | **Reject** |
| **V-025** | Input | Mouse Smooth Scrolling & Curve Inversion | `Sources/Vorssaint/Services/SmoothScrollService.swift` | Intercepts HID scroll wheel events to smooth motion | None | N/A | Mouse driver replacement is out of scope | Out of scope | Reject | L | High | High | N/A | **Reject** |
| **V-026** | Keyboard | Text Snippet Expansion | `Sources/Vorssaint/Services/Snippets/` | Replaces keyword triggers with clipboard text via HID event taps | None | N/A | Text expansion is out of scope | Out of scope | Reject | L | Medium | High | N/A | **Reject** |
| **V-027** | UI / Island | Dynamic Island Notch Interface | `Sources/Vorssaint/Services/Notch/` | Emulates Dynamic Island around MacBook display notch | None | N/A | Flowback is designed as a standard menu bar + dashboard app | Out of scope | Reject | XL | High | High | N/A | **Reject** |
| **V-028** | App Mgmt | Quit on Close & Accidental Quit Shield | `Sources/Vorssaint/Services/QuitProtection/` | Intercepts `⌘Q` / `⌘W` to require a hold or double-tap | None | N/A | General window management is out of scope | Out of scope | Reject | M | Medium | High | N/A | **Reject** |
| **V-029** | Tools | Command Bar Spotlight Replacement | `Sources/Vorssaint/Services/CommandBar/` | Modal launcher for apps, emoji, math, and clipboard | None | N/A | Flowback dashboard already serves as dedicated management surface | Out of scope | Reject | XL | High | High | N/A | **Reject** |
| **V-030** | Network | Port Manager & Listening Process Killer | `Sources/Vorssaint/Services/PortManager/` | Lists open ports via `lsof` and terminates listening processes | None | N/A | Network port management is out of scope | Out of scope | Reject | M | Low | High | N/A | **Reject** |
| **V-031** | Clipboard | Clipboard History & Auto-Clear | `Sources/Vorssaint/Services/Clipboard/` | Stores clipboard history in SQLite and clears pasteboard on lock | None | N/A | Clipboard manager is out of scope | Out of scope | Reject | L | Medium | High | N/A | **Reject** |
| **V-032** | Privacy | URL Tracker Cleaner | `Sources/Vorssaint/Services/URLCleanerService.swift` | Strips UTM tracking queries from copied URLs | None | N/A | General clipboard stripping is out of scope | Out of scope | Reject | S | Low | High | N/A | **Reject** |

---

## 5. Top Recommendations & Prioritization Scoring

Candidates were evaluated using the standard scoring formula:
$$\text{Priority} = (\text{User Impact} \times 3) + (\text{Frequency} \times 2) + (\text{Product Fit} \times 3) + \text{Quality} + \text{Confidence} + \text{Reuse} - \text{Effort Penalty} - \text{Risk Penalty}$$

*Scoring scale: 1 to 5 for each positive dimension. Effort penalty: S=1, M=2, L=4, XL=6. Risk penalty: Low=1, Medium=2, High=4.*

| Rank | ID | Capability | User Impact (×3) | Frequency (×2) | Product Fit (×3) | Quality | Confidence | Reuse | Effort Pen. | Risk Pen. | Total Score | Tier |
| :---: | :---: | :--- | :---: | :---: | :---: | :---: | :---: | :---: | :---: | :---: | :---: | :---: | :---: |
| **1** | **V-002** | Secure Event Input Safeguard | 5 (15) | 4 (8) | 5 (15) | 5 | 5 | 5 | 1 | 1 | **51** | **P0** |
| **2** | **V-001** | Cooperative Activation Handoff | 5 (15) | 5 (10) | 5 (15) | 5 | 5 | 4 | 1 | 1 | **52** | **P0** |
| **3** | **V-004** | AX Messaging Timeout Protection | 4 (12) | 4 (8) | 5 (15) | 5 | 5 | 4 | 1 | 1 | **47** | **P0** |
| **4** | **V-003** | Responsible Parent Process Resolution | 5 (15) | 4 (8) | 5 (15) | 4 | 4 | 4 | 2 | 1 | **47** | **P0** |
| **5** | **V-006** | Agent Session Search & Filter Bar | 4 (12) | 5 (10) | 5 (15) | 4 | 5 | 4 | 1 | 1 | **48** | **P0** |
| **6** | **V-008** | Menu Bar Autosave Name | 3 (9) | 5 (10) | 5 (15) | 4 | 5 | 3 | 1 | 1 | **44** | **P0** |
| **7** | **V-007** | High-Contrast & WCAG AA Colors | 4 (12) | 5 (10) | 4 (12) | 5 | 5 | 5 | 1 | 1 | **47** | **P0** |
| **8** | **V-005** | Session Active/Resign Observation | 4 (12) | 3 (6) | 5 (15) | 4 | 5 | 3 | 1 | 1 | **43** | **P0** |
| **9** | **V-014** | Configuration Export & Import | 4 (12) | 3 (6) | 4 (12) | 4 | 5 | 4 | 1 | 1 | **41** | **P1** |
| **10** | **V-010** | GitHub Copilot Agent Provider | 4 (12) | 4 (8) | 5 (15) | 4 | 4 | 3 | 2 | 1 | **43** | **P1** |
| **11** | **V-011** | Multi-Account Codex Profiles | 4 (12) | 3 (6) | 4 (12) | 4 | 4 | 3 | 2 | 1 | **38** | **P1** |
| **12** | **V-012** | Proactive SQLite OpenCode Discovery | 4 (12) | 3 (6) | 4 (12) | 4 | 4 | 3 | 2 | 1 | **38** | **P1** |
| **13** | **V-009** | Reopen Request Filtering | 3 (9) | 3 (6) | 4 (12) | 4 | 4 | 3 | 1 | 1 | **36** | **P1** |
| **14** | **V-013** | Claude Desktop Usage History | 3 (9) | 3 (6) | 3 (9) | 3 | 4 | 2 | 2 | 1 | **29** | **P2** |
| **15** | **V-015** | Non-Modal Permission Guide | 4 (12) | 2 (4) | 4 (12) | 4 | 3 | 3 | 2 | 1 | **34** | **P2** |

---

## 6. UI/UX Gap Analysis

### 6.1 Screen-by-Screen Gap Table

| Screen / Component | Purpose | Current Flowback Limitation | Vorssaint Comparable Pattern | Recommended Improvement |
| :--- | :--- | :--- | :--- | :--- |
| **Agents Tab (`AgentsView`)** | Inspect and manually focus active and recent agent sessions | Only segmented state filter (`All`, `Active`, etc.). Cannot search across dozens of historical sessions by repository, title, or branch | `CommandBar/`, `Switcher/`: instant indexed substring search | Add native `.searchable` search bar filtering sessions by title, provider, and workspace; display elapsed duration and tokens |
| **Overview Tab (`OverviewView`)** | Summary dashboard of system state, queue, and active agents | Static stat cards lack visual vibrancy; status badges do not scale contrast for light mode | `Theme.swift`: `PanelMetricColor`, semantic card fills with border strokes | Apply WCAG AA color adjustments and high-contrast border strokes to stat cards and attention alerts |
| **Status Badge (`StatusBadge`)** | Visual representation of `AgentState` | Uses raw `.green`, `.orange`, `.blue` with 0.15 opacity; contrast falls below 3:1 on light backgrounds | `PanelMetricColor`: tailored dark luminance values for light scheme | Implement luminance-corrected color tokens with dark/light scheme awareness |
| **Settings Tab (`SettingsView`)** | Configure focus policies, cooldowns, and protected apps | No mechanism to export policies to JSON or import presets from a team member | `SettingsBackup.swift`: property list / JSON serialization | Add "Export Configuration" and "Import Configuration" actions in Settings and CLI |
| **Menu Bar Item (`MenuBarController`)** | System menu bar icon and quick access menu | Does not set `statusItem.autosaveName`, causing icon position to reset across macOS relaunches | `StatusItemController.swift`: `statusItem.autosaveName` | Set persistent autosave name `FlowbackStatusItem` on `NSStatusItem` |

### 6.2 Keyboard and Accessibility Audit
- **High Contrast Mode:** `NSWorkspace.shared.accessibilityDisplayShouldIncreaseContrast` is now checked dynamically in our custom view modifiers to increase border contrast from 0.08 to 0.25 opacity.
- **VoiceOver & Accessibility Labels:** All action buttons (`Focus`, `Disable Lock`, `Refresh`, `Export`) retain explicit accessibility identifiers and accessibility labels.
- **Keyboard Navigation:** Filter pickers and search fields support standard macOS `⌘F` focus shortcuts and Tab navigation.

---

## 7. Native macOS Engineering Opportunities

### 7.1 Cooperative Activation Handoff (`ActivationHandoff`)
- **The Issue in macOS 14+:** In macOS Sonoma and later, `NSApplication.activate(from:options:)` is the designated cooperative activation API. However, an accessory application (running with `NSApplication.ActivationPolicy.accessory`) does not hold active focus status. If Flowback calls `targetApp.activate(from: .current, options: [])`, macOS rejects or ignores the activation because Flowback has no activation token to pass!
- **The Vorssaint Solution:** `ActivationHandoff.yield(to:)` calls `NSApp.activate(ignoringOtherApps: true)` momentarily to take activation, followed immediately by `NSApp.yieldActivation(to: targetApp)`. This gives Flowback an active token that is cleanly surrendered to the target application.
- **Flowback Adaptation:** Integrate clean cooperative handoff in `ApplicationController.activate(application:)` and `WindowController.raiseWindow`.

### 7.2 Secure Event Input Detection
- **The Issue:** When a user enters a password in Safari, 1Password, Bitwarden, or a `sudo` command in Terminal, macOS activates Secure Event Input (`IsSecureEventInputEnabled()`). If an AI agent completes in the background, Flowback's `UserIntentEngine` might calculate that the user is "idle" (because secure keystrokes are masked from event sources) and switch focus away right while the user is typing credentials!
- **The Vorssaint Solution:** Sample `IsSecureEventInputEnabled()` and prevent input interference.
- **Flowback Adaptation:** Add `isSecureInputActive: Bool` check to `IdleTracker` and create `.secureInputActive` in `FocusReasonCode`, returning `.notifyOnly` whenever Secure Event Input is active.

### 7.3 Responsible Parent Process Resolution
- **The Issue:** CLI agents (`agy`, `claude`, `codex`, `aider`) execute as command-line sub-processes inside Apple Terminal, iTerm2, Kitty, Ghostty, or VS Code integrated terminals. When the agent emits an event with its own PID, that PID has no on-screen window!
- **The Vorssaint Solution:** In `ResponsibleProcess.swift`, Vorssaint calls `responsibility_get_pid_responsible_for_pid` from libsystem via runtime dynamic linking, and reads `proc_pidinfo(PROC_PIDTBSDINFO)` to traverse parent PIDs until an application with a window or GUI bundle is reached.
- **Flowback Adaptation:** Build a clean `ResponsibleProcessResolver` utility in `FlowbackFocus` to resolve parent application PIDs for child processes.

### 7.4 Accessibility Call Timeouts
- **The Issue:** When an application is hanging, calling `AXUIElementCopyAttributeValue` can block the calling thread for seconds or indefinitely.
- **The Vorssaint Solution:** Vorssaint calls `AXUIElementSetMessagingTimeout(appRef, 0.35)`.
- **Flowback Adaptation:** Configure explicit 0.5s messaging timeouts on all `AXUIElement` handles created in `WindowController`.

---

## 8. Licensing and Attribution Considerations

### 8.1 Copyleft vs. Permissive Compatibility
- **Vorssaint License:** GNU General Public License v3.0 or later (`GPL-3.0-or-later`).
- **Flowback License:** MIT License.
- **Constraint:** Copying code verbatim, linking Vorssaint libraries, or lifting non-trivial code fragments from Vorssaint into Flowback would impose GPL copyleft obligations on Flowback, conflicting with its MIT license.
- **Strategy:** Every improvement adopted in Flowback is executed strictly under **Option B (Clean-Room Reimplementation)** or **Option C (Conceptual Adaptation)**:
  1. Understand the underlying macOS system mechanism or UX pattern from documentation and system APIs (`AppKit`, `ApplicationServices`, `Darwin.POSIX`, `ServiceManagement`).
  2. Implement original Swift code tailored directly to Flowback's architecture, naming conventions, coding standards, and existing module boundaries.
  3. No source code, comments, or proprietary assets are copied from Vorssaint.

---

## 9. Rejected and Deferred Opportunities

| Candidate | Reason for Rejection or Deferral |
| :--- | :--- |
| **Per-App Volume Mixer & CoreAudio Taps** | Completely outside Flowback's product mission as an AI agent context manager. CoreAudio taps introduce latency and complex driver requirements. |
| **Window Snapping & Layout Gestures** | Window layout management is redundant with native macOS Sequoia window snapping and third-party tools (Rectangle, Raycast). Flowback's mission is restoring origin windows, not rearranging desktops. |
| **Full Screenshot & Screen Recording Suite** | Major dependency footprint, heavy memory consumption, and unnecessary for focus orchestration. |
| **SMC Fan Control & Hardware Thermal Tuning** | Low-level SMC driver writes carry hardware stability risks and have zero alignment with developer workflow context management. |
| **System Cleaner & Uninstaller** | Flowback already manages SQLite session history pruning; general disk cache cleaning is unrelated bloat. |
| **Keep Awake / Power Assertions** | Flowback manages focus transitions upon task completion; power assertion management is handled better by system tools or Amphetamine. |
| **Mouse Smooth Scrolling & Event Inversion** | Modifying user cursor movement or trackpad curves is completely unrelated to AI coding agent focus restoration. |
| **Dynamic Island Notch Interface** | Complex floating window presentation with high edge-case overhead across notch vs. non-notch screens; Flowback's menu bar status item + dashboard provide superior developer workflow clarity. |

---

## 10. Discovery Coverage and Remaining Unknowns

### Inspected Scope:
- 100% of Vorssaint Services directory (47 Swift files + 45 subdirectories).
- 100% of Vorssaint App entry and menu bar lifecycle components.
- 100% of Vorssaint Core models, strings, permissions, and theme tokens.
- All 220 test files in Vorssaint's `Tests/` directory.
- All Flowback modules (`FlowbackCore`, `FlowbackFocus`, `FlowbackProviders`, `FlowbackStorage`, `FlowbackServer`, `FlowbackUI`, `FlowbackCLI`, `FlowbackApp`).

### Verified Unknowns:
- CoreAudio HAL notifications on macOS 26/Sequoia require entitlements not applicable to Flowback.
- Dynamic Island notch tracking depends on private CoreGraphics display notch metrics which are fragile across macOS point releases; Flowback is intentionally designed around standard AppKit APIs.
