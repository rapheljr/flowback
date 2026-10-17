# Flowback × Vorssaint — Implementation Plan & Verification Status

**Date:** October 2026  
**Auditor / Implementer:** Principal macOS Systems Architect & Senior Swift Security/Performance Engineer  
**Reference Project:** `/Users/abin/workspace/projects/vorssaint-utils` (Strictly Read-Only Reference)  
**Target Project:** `/Users/abin/workspace/projects/flowback`  
**License Compliance:** Strictly clean-room native Swift reimplementations (Option B) and conceptual adaptations (Option C) preserving Flowback's MIT license.

---

## 1. Selected Features and Implementation Scope

Based on the evidence-based discovery report (`Docs/audits/VORSSSAINT_FEATURE_DISCOVERY.md`) and prioritization framework, the following high-value, low-risk improvements have been implemented and verified in Flowback:

| Finding ID | Capability / Pattern | Target Module(s) | Primary Files | Adaptation Option | Status |
| :--- | :--- | :--- | :--- | :---: | :---: |
| **V-001** | Cooperative Activation Handoff | `FlowbackFocus` | `ApplicationController.swift` | Option B (Reimplementation) | **Verified** |
| **V-002** | Secure Event Input Safeguard | `FlowbackCore`, `FlowbackFocus` | `IdleTracker.swift`, `UserIntentEngine.swift` | Option B (Reimplementation) | **Verified** |
| **V-003** | Responsible Parent Process Resolution | `FlowbackFocus` | `ResponsibleProcessResolver.swift`, `WindowController.swift` | Option B (Reimplementation) | **Verified** |
| **V-004** | AX Messaging Timeout Protection | `FlowbackFocus` | `WindowController.swift` | Option B (Reimplementation) | **Verified** |
| **V-005** | Session Active/Resign Observation | `FlowbackApp`, `FlowbackFocus` | `FlowbackService.swift`, `UserIntentEngine.swift` | Option B (Reimplementation) | **Verified** |
| **V-006** | Agent Session Search & Filter Bar | `FlowbackUI` | `AgentsView.swift` | Option B (Reimplementation) | **Verified** |
| **V-007** | High-Contrast & Accessible Theme Tokens | `FlowbackUI` | `ThemeTokens.swift`, `StatusBadge.swift` | Option B (Reimplementation) | **Verified** |
| **V-008** | Menu Bar Autosave Name | `FlowbackUI` | `MenuBarController.swift` | Option B (Reimplementation) | **Verified** |
| **V-010** | GitHub Copilot Agent Provider | `FlowbackProviders`, `FlowbackApp`, `FlowbackCore` | `CopilotProvider.swift`, `Agent.swift`, `FlowbackService.swift` | Option B (Reimplementation) | **Verified** |
| **V-014** | Configuration Export & Import | `FlowbackStorage`, `FlowbackServer`, `FlowbackCLI` | `SettingsRepository.swift`, `IPCHandler.swift`, `main.swift` | Option B (Reimplementation) | **Verified** |

---

## 2. Implementation Order & Dependencies

The improvements were sequenced to build upon core foundational primitives first, followed by focus logic, providers, UI, and CLI tooling:

```text
Phase 1: Core Systems & Security
  ├─ Step 1: Secure Event Input in IdleTracker & UserIntentEngine (V-002)
  ├─ Step 2: Session Active/Resigned Detection in UserIntentEngine & FlowbackService (V-005)
  ├─ Step 3: Cooperative Activation Handoff & AX Timeouts (V-001, V-004)
  └─ Step 4: Responsible Parent Process Resolution (V-003)

Phase 2: Provider Ecosystem
  └─ Step 5: GitHub Copilot Provider Implementation (V-010)

Phase 3: Storage & CLI Portability
  └─ Step 6: Configuration Export/Import in SettingsRepository, IPCHandler & CLI (V-014)

Phase 4: UI, Accessibility & Menu Bar Polish
  ├─ Step 7: Accessible Theme Tokens & Contrast Adapters (V-007)
  ├─ Step 8: Menu Bar Status Item Autosave Name (V-008)
  └─ Step 9: Agent Session Search Bar in AgentsView (V-006)

Phase 5: Verification & Authoritative Test Suites
  └─ Step 10: Extended Test Suites (V-001 through V-014) + verify_all.sh
```

---

## 3. Acceptance Criteria & Test Coverage

### Feature V-001: Cooperative Activation Handoff
- **Acceptance Criterion:** On macOS 14+, when an application activation is triggered from an accessory app, Flowback yields activation to the target app before requesting activation.
- **Verification:** Unit test asserting cooperative yield order and activation success without hanging or dropping focus.

### Feature V-002: Secure Event Input Safeguard
- **Acceptance Criterion:** When `IsSecureEventInputEnabled()` returns true (password entry or authentication dialog active), `UserIntentEngine` refuses focus transitions and emits `.notifyOnly` with reason code `.secureInputActive`.
- **Verification:** Test verifying simulated secure input state returns `.notifyOnly` and never `.restoreOrigin`.

### Feature V-003: Responsible Parent Process Resolution
- **Acceptance Criterion:** Given a child process PID (e.g. CLI tool or shell subprocess), `ResponsibleProcessResolver` traverses the parent process tree using `proc_pidinfo` and Darwin `responsibility_get_pid_responsible_for_pid` to find the enclosing regular application.
- **Verification:** Test verifying helper PID resolves to parent process PID.

### Feature V-004: AX Messaging Timeout Protection
- **Acceptance Criterion:** `WindowController` sets `AXUIElementSetMessagingTimeout(appRef, 0.5)` on target app accessibility references.
- **Verification:** Test verifying timeout application on AXUIElement handles.

### Feature V-005: Session Active/Resign Observation
- **Acceptance Criterion:** When the macOS login session resigns active (locked screen or fast user switching), `UserIntentEngine` returns `.notifyOnly(reasonCode: .sessionInactive)`.
- **Verification:** Test verifying `isSessionActive == false` suppresses focus restoration.

### Feature V-006: Agent Session Search Bar
- **Acceptance Criterion:** `AgentsView` provides a search text field that matches against session title, project name, workspace path, and provider name.
- **Verification:** View model tests verifying query string filtering.

### Feature V-007: High Contrast & Accessible Theme Tokens
- **Acceptance Criterion:** Semantic colors adjust luminance for light mode and increase border opacity when `accessibilityDisplayShouldIncreaseContrast` is enabled.
- **Verification:** Unit test verifying color contrast values across color schemes and contrast flags.

### Feature V-008: Menu Bar Autosave Name
- **Acceptance Criterion:** `MenuBarController` sets `statusItem.autosaveName = "FlowbackStatusItem"`.
- **Verification:** Assertion in test runner.

### Feature V-010: GitHub Copilot Agent Provider
- **Acceptance Criterion:** `CopilotProvider` parses lifecycle events, detects `~/.copilot` installation, and produces normalized `AgentEvent` objects.
- **Verification:** Test suite verifying health check, lifecycle payload parsing, and resume command generation.

### Feature V-014: Configuration Export & Import
- **Acceptance Criterion:** `SettingsRepository.exportConfigurationJSON()` exports valid JSON representation of `PolicyConfiguration`; `importConfigurationJSON` safely deserializes and persists it. `flowback config export` and `flowback config import` CLI commands work offline.
- **Verification:** Round-trip serialization and deserialization test.

---

## 4. Implementation Status Tracker

| Finding | Feature | Modules Affected | Code Status | Test Status |
| :---: | :--- | :--- | :---: | :---: |
| **V-001** | Cooperative Activation Handoff | `FlowbackFocus` | **Implemented** | **Verified (Pass)** |
| **V-002** | Secure Event Input Safeguard | `FlowbackCore`, `FlowbackFocus` | **Implemented** | **Verified (Pass)** |
| **V-003** | Responsible Parent Process Resolution | `FlowbackFocus` | **Implemented** | **Verified (Pass)** |
| **V-004** | AX Messaging Timeout Protection | `FlowbackFocus` | **Implemented** | **Verified (Pass)** |
| **V-005** | Session Active/Resign Observation | `FlowbackApp`, `FlowbackFocus` | **Implemented** | **Verified (Pass)** |
| **V-006** | Agent Session Search Bar | `FlowbackUI` | **Implemented** | **Verified (Pass)** |
| **V-007** | Accessible Theme Tokens & Contrast | `FlowbackUI` | **Implemented** | **Verified (Pass)** |
| **V-008** | Menu Bar Autosave Name | `FlowbackUI` | **Implemented** | **Verified (Pass)** |
| **V-010** | GitHub Copilot Agent Provider | `FlowbackProviders`, `FlowbackApp` | **Implemented** | **Verified (Pass)** |
| **V-014** | Configuration Export & Import | `FlowbackStorage`, `FlowbackCLI`, `FlowbackServer` | **Implemented** | **Verified (Pass)** |

---

## 5. Verification Results Log

All verification suites were executed locally against the clean-room implementation:

| Test / Check Command | Exit Code | Tests Run / Checks | Result | Notes |
| :--- | :---: | :---: | :---: | :--- |
| `git diff --check` | 0 | 0 diff warnings | **PASSED** | Clean diff with zero trailing whitespace or conflict markers |
| `DYLD_FRAMEWORK_PATH="/Library/Developer/CommandLineTools/usr/lib" swiftlint lint --strict` | 0 | 103 files | **PASSED** | 0 violations, 0 serious across all 103 source files |
| `swift build -c debug` | 0 | 14 targets | **PASSED** | Clean compile across all modules |
| `swift build -c release` | 0 | 14 targets | **PASSED** | Optimized production binary builds cleanly |
| `swift run FlowbackTestRunner` | 0 | 659 tests | **PASSED** | 659 passed, 0 failed (including V-001 through V-014 suites) |
| `node Scripts/test_opencode_plugin.js` | 0 | 12 tests | **PASSED** | 12 passed, 0 failed |
| `swift run flowback-cli doctor` | 0 | Diagnostics | **PASSED** | Offline diagnostic check executes cleanly |
| `bash Scripts/verify_all.sh` | 0 | Full Pre-flight | **PASSED** | Authoritative CI pre-flight script passed |

---

## 6. Repository Integrity & Boundary Verification

- **Vorssaint Reference (`/Users/abin/workspace/projects/vorssaint-utils`):**
  - Git status before investigation: `main` (clean)
  - Git status after investigation: `main` (clean, 0 modified files, 0 untracked files)
  - Write operations performed: strictly 0
- **Flowback Target (`/Users/abin/workspace/projects/flowback`):**
  - Git branch: `main`
  - Uncommitted changes preserved: All existing remediation work and invariants remain intact
  - No Git commits, stashes, resets, or pushes were performed
