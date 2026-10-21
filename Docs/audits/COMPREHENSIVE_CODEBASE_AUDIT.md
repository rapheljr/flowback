# Flowback — Comprehensive Codebase Audit

**Audit Date:** October 21, 2026  
**Repository:** `/Users/abin/workspace/projects/flowback`  
**Branch / Commit Audited:** `main` @ `2aaebd9` (`build: update fallback version and build number defaults to v0.4.1`)  
**Product Version / Build:** `v0.4.1` (build `2`)  
**Host Environment:** macOS 26.7.1 (Build `25G241`), Apple Silicon (`arm64`), Apple Swift 6.4 (`swiftlang-6.4.0.34.1 clang-2100.3.34.1`), SwiftLint `0.65.1`  
**Guiding Product Principle:** *"Integrate broadly, orchestrate narrowly, restore focus conservatively."*

---

## A. Executive Summary

### 1. Overall Health
Flowback has a well-structured, zero-external-dependency Swift 6 modular architecture (`FlowbackCore`, `FlowbackStorage`, `FlowbackFocus`, `FlowbackProviders`, `FlowbackServer`, `FlowbackNotifications`, `FlowbackUI`, `FlowbackApp`, `FlowbackCLI`) with strong foundational primitives: a deterministic finite state machine (`AgentStateMachine`), sliding-window event deduplication (`EventDeduplicator`), thread-safe `TimeoutCoordinator` with monotonic generation tokens in `FocusController`, bounded streaming subprocess execution (`AsyncProcessRunner`), WAL-backed SQLite persistence with corruption recovery (`RecoveryManager`), and UI burst coalescing (`UIEventCoalescer`).

However, independent adversarial source inspection and reproducible runtime verification uncovered **14 concrete findings** (`FB-AUD-001` through `FB-AUD-014`), including **5 High-severity defects** and **6 Medium-severity defects** that directly affect core focus restoration, state synchronization between CLI/Daemon/UI, policy enforcement, SQLite transaction isolation under Swift actor reentrancy, and test suite integrity.

### 2. Confirmed Defects Summary
- **`FB-AUD-001` (High — Release Blocker):** `FocusController.restoreSession(_:)` hard-fails with `.permissionDenied` whenever `origin.windowIdentifier != nil` and Accessibility permission (`AXIsProcessTrusted()`) is not granted, even though `origin.windowIdentifier` is routinely populated via `CGWindowListCopyWindowInfo` without Accessibility permission. This prevents Flowback from executing its documented application-level activation fallback (`NSWorkspace`) when Accessibility is untrusted, and causes 7 test assertions in `FlowbackTestRunner` to fail whenever the runner binary lacks host TCC Accessibility authorization.
- **`FB-AUD-002` (High — Release Blocker):** `FlowbackTestRunner` invokes `MenuBarController.setup()` (`NSStatusBar.system.statusItem(withLength:)`) inside suite `V-008`. In headless or non-WindowServer execution contexts, AppKit terminates the process cleanly with exit status `0` (`returncode: 0`) mid-run—masking 9 earlier test failures and skipping ~400 trailing assertions across `V-008` through Suite 28.
- **`FB-AUD-003` (High — Release Blocker):** Split-brain state management across `IPCHandler`, `FlowbackService`, and `DashboardViewModel`:
  1. Toggling Focus Lock via CLI (`flowback focus-lock 30m`) mutates only `IPCHandler.focusLock` and never updates `FlowbackService.focusLock`, so `FlowbackService.handleAgentEvent` continues stealing focus while `flowback status` reports `focusLockActive: true`.
  2. Clicking "Disable" on the Focus Lock banner in `OverviewView` mutates only `dashboardViewModel.focusLock`, which is overwritten within 50ms–10s by `FlowbackService.updateMinimalUIState()`.
  3. Adding/removing protected applications in `ApplicationsView` or importing configuration via `flowback config import` does not synchronize with `FlowbackService.configuration` in memory.
  4. `AttentionArbiter` cooldown and aggregation windows are captured as immutable `let` constants at startup and never update when changed in Settings.
- **`FB-AUD-004` (High — Release Blocker):** `PolicyConfiguration.completionBehavior`, `permissionBehavior`, and `failureBehavior`—exposed prominently in the `Advanced` UI and configuration schema—are completely unimplemented dead fields that are never read by `UserIntentEngine`, `FocusController`, or `FlowbackService`. Additionally, `FlowbackService.handleAgentEvent` ignores `.agentWaiting` and `.agentIdle` events despite `AgentEventType.isActionableForAttention` marking them actionable.
- **`FB-AUD-005` (High — Release Blocker):** `SQLiteDatabase.runInTransaction` executes `BEGIN IMMEDIATE TRANSACTION;` and then suspends across `try await block()` on the `SQLiteDatabase` actor. Under Swift actor reentrancy, concurrent callers can interleave queries inside the open transaction or fail with `SQLITE_ERROR: cannot start a transaction within a transaction`.

### 3. Highest-Risk Areas
1. **Composition Root State Synchronization (`FlowbackService` ↔ `IPCHandler` ↔ `DashboardViewModel`):** Duplicate copies of `FocusLockState` and `PolicyConfiguration` across actors/classes without a single authoritative state owner.
2. **Untrusted-Accessibility Degradation Path (`FocusController.restoreSession`):** Premature abort on `origin.windowIdentifier != nil && !permissionChecker()` blocks app-level fallback.
3. **Actor Reentrancy Across Multi-Statement Operations (`SQLiteDatabase.runInTransaction`, `AttentionArbiter` queue lifecycle):** Suspension points inside actor methods allow interleaved mutations.
4. **Provider Health & Discovery Fidelity (`CodexProvider`, `AiderProvider`, `ClaudeCodeProvider`, `OpenCodeProvider`):** Stubbed health checks (`isInstalled: false` hardcoded) and naive process polling (`OpenCodeProvider` fabricating a new session timestamp every 10s).

### 4. What Works Reliably
- **Core State Machine & Deduplication (`AgentStateMachine`, `EventDeduplicator`):** Enforces terminal-state immutability, multi-turn reactivation in `SessionManager`, and sliding-window deduplication.
- **Navigation Cancellation & Timeout State Machine (`TimeoutCoordinator`, `FocusController` generation tokens):** Monotonic generation counters and `NSLock`-guarded `TimeoutCoordinator` prevent double-resumed continuations, stale cancellation handler clobbering, and superseded navigation completions.
- **Window Matching Heuristics (`WindowController.selectMatchingWindowIndex`):** Deterministic scoring across window geometry and title with conservative tie-breaking (returns `nil` on ties rather than guessing).
- **IPC Socket Framing & Bounds (`UnixSocketServer`, `IPCClient`):** Enforces `0700` directory permissions, `0600` socket/token permissions, `getpeereid()` UID checks, 2 MB payload caps, `SO_NOSIGPIPE`, and `SO_RCVTIMEO`/`SO_SNDTIMEO`.
- **UI Event Coalescer (`UIEventCoalescer`):** Coalesces high-frequency event bursts into single 50ms UI refresh passes with deterministic `flush()` settling.

### 5. Release-Readiness Verdict
**`NOT READY`** for public distribution or broad beta until P0 blockers (`FB-AUD-001` through `FB-AUD-005` and `FB-AUD-011`) are remediated, and Apple Developer ID signing + notarization are completed for public Gatekeeper acceptance.

### 6. Audit Limitations
- **Command Line Tools Host (No `Xcode.app`):** `XCTest.framework` is not present on this CLT-only host (`/Applications/Xcode.app` is absent), so `swift test` cannot compile `Tests/*Tests`; all test execution was performed via the standalone `FlowbackTestRunner` binary.
- **Sandboxed / Non-GUI Execution Constraints:** The audit execution environment restricts `sandbox-exec` (requiring `--disable-sandbox` for SwiftPM manifest compilation), blocks `listen()` on Unix domain sockets inside the command sandbox (affecting `UnixSocketServer` live bind tests and `Scripts/test_opencode_plugin.js`), and runs without an interactive WindowServer GUI session or granted TCC Accessibility permission (`AXIsProcessTrusted() == false`).
- **No Apple Developer Signing Credentials:** Developer ID certificates and Apple Notary Service credentials are not present in the local environment; notarization and clean-Mac Gatekeeper acceptance could not be executed live.

---

## B. Audit Coverage & Inventory

| Phase / Audit Domain | Subsystems & Files Inspected | Checks Executed | Disposition | Limitations |
| :--- | :--- | :--- | :--- | :--- |
| **Phase 0 — Audit Baseline** | Git state (`HEAD` `2aaebd9`), `Package.swift`, `VERSION`, `BUILD`, `.gitignore`, `.swiftlint.yml`, `Makefile`, directory tree | `git_status`, `git_log`, `git_branch`, `git_diff`, `git_show`, `sw_vers`, `swift --version`, `swiftlint version` | **Passed with evidence** | None |
| **Phase 1 — Architecture & Design** | All 11 targets in `Package.swift`, module imports, actor boundaries, singletons (`FlowbackService`, `EventBus`, `TimelineTracker`, `ProviderRegistry`, `ApplicationAdapterRegistry`, `ResumeCommandRegistry`) | Static dependency graph trace and end-to-end workflow trace | **Findings identified** (`FB-AUD-003`, `FB-AUD-012`) | None |
| **Phase 2 — Correctness & Contracts** | `AgentStateMachine`, `PolicyConfiguration`, `FocusPolicy`, `SessionManager`, `TimelineTracker`, `RestorationResult`, `AgentEvent`, `AgentSession` | Contract trace across all public APIs and configuration fields | **Findings identified** (`FB-AUD-003`, `FB-AUD-004`, `FB-AUD-012`) | None |
| **Phase 3 — Concurrency & Lifecycle** | `FocusController`, `TimeoutCoordinator`, `UIEventCoalescer`, `ManualSleepScheduler`, `AsyncProcessRunner`, `LifecycleCoordinator`, `SQLiteDatabase`, `IPCHandler`, `AppDelegate` | Lock/continuation/reentrancy audit; executed concurrency suites in `FlowbackTestRunner` | **Findings identified** (`FB-AUD-003`, `FB-AUD-005`, `FB-AUD-007`) | None |
| **Phase 4 — Focus & macOS Integration** | `FocusController`, `ApplicationController`, `WindowController`, `UserIntentEngine`, `AttentionArbiter`, `SpaceController`, `ResponsibleProcessResolver`, `IdleTracker`, `PermissionManager` | Source inspection, `FlowbackTestRunner` focus suites, `Scripts/test_live_macos.sh` components | **Findings identified** (`FB-AUD-001`, `FB-AUD-012`, `FB-AUD-013`) | Interactive GUI WindowServer & granted TCC Accessibility unavailable in headless sandbox |
| **Phase 5 — Agent & App Adapters** | All 10 providers in `Sources/FlowbackProviders/` + JS plugin; all 6 adapters in `Sources/FlowbackFocus/Adapters/` | Line-by-line inspection of detection, health, hooks, discovery, and restoration | **Findings identified** (`FB-AUD-009`, `FB-AUD-010`) | Live third-party agent binaries (except `agy`) not running on host |
| **Phase 6 — Security & Privacy** | `SecretSanitizer`, `DiagnosticReportExporter`, `UnixSocketServer`, `IPCClient`, `IPCHandler`, `BrainTranscriptParser`, provider hook installers | Adversarial regex, decoder bypass, socket permission, and command construction review | **Findings identified** (`FB-AUD-006`, `FB-AUD-008`) | None |
| **Phase 7 — Process Management & IPC** | `AsyncProcessRunner`, `UnixSocketServer`, `IPCClient`, `IPCHandler`, `AdvancedViewModel`, `SupportView` | Pipe drainage, timeout/cancellation, signal escalation, and IPC wire framing review | **Findings identified** (`FB-AUD-007`, `FB-AUD-008`) | Live `bind()/listen()` blocked by command runner sandbox (`EPERM`) |
| **Phase 8 — UI, UX & Accessibility** | `MenuBarController`, `DashboardView`, `FlowbackCard`, `ThemeTokens`, `StatusBadge`, `ReleaseNotesModel`, all 10 views in `Sources/FlowbackUI/Views/` | Main-thread audit, binding dataflow trace, WCAG contrast calculation review | **Findings identified** (`FB-AUD-002`, `FB-AUD-003`, `FB-AUD-008`) | Interactive VoiceOver and live menu bar clicking require GUI session |
| **Phase 9 — Performance & Resource Use** | `FlowbackService` 10s timer, `SessionManager` retention, `TimelineTracker`, `AntigravityProvider`/`WindsurfProvider` transcript scanning, `OpenCodeProvider` | Algorithmic complexity and I/O frequency analysis | **Findings identified** (`FB-AUD-010`) | None |
| **Phase 10 — Reliability & Observability** | `RecoveryManager`, `DiagnosticReportExporter`, `PermissionManager`, `FlowbackCLI` `doctor`, `OSLog` usage, `try?` error swallowing | Error path trace across storage, IPC, UI settings save, and CLI | **Findings identified** (`FB-AUD-003`, `FB-AUD-012`) | None |
| **Phase 11 — Tests & Quality Assurance** | All 11 files in `Sources/FlowbackTestRunner/`, `MockFixtures.swift`, all 12 files in `Tests/` | Ran `swift build`, `swift build -c release`, `FlowbackTestRunner`, `swiftlint lint --strict`, `validate_version_sync.sh`, `test_website.sh` | **Findings identified** (`FB-AUD-001`, `FB-AUD-002`) | `XCTest` unavailable on CLT-only host; socket bind blocked by sandbox |
| **Phase 12 — CLI, Config & DX** | `Sources/FlowbackCLI/main.swift`, `Sources/FlowbackApp/main.swift`, `SettingsRepository`, `AdvancedViewModel` | Executed `Flowback --help/--version` and `flowback-cli --version/doctor` | **Findings identified** (`FB-AUD-003`, `FB-AUD-014`) | None |
| **Phase 13 — Packaging & Distribution** | `Scripts/build.sh`, `package_app.sh`, `sign_and_notarize.sh`, `package_release_artifacts.sh`, `validate_release.sh`, `generate_manifest.sh`, `generate_cask.sh`, `.github/workflows/*`, `dist/`, `Casks/`, `Formula/` | Ran `validate_version_sync.sh` and `validate_release.sh --local` | **Findings identified** (`FB-AUD-011`, `FB-AUD-013`) | No Apple Developer ID certificate or notarization credentials in environment |
| **Phase 14 — Documentation & Hygiene** | All 20 root `.md` files, all `Docs/*.md` and `Docs/audits/*.md` files, `Website/`, `.gitignore` | Ran Markdown link validator across root and `Docs/`; cross-checked docs vs code | **Findings identified** (`FB-AUD-014`) | None |
| **Phase 15 — Dependencies & Maintainability** | `Package.swift`, compiler/linker warnings, code duplication across providers/adapters | Audited target graph, linker flags, and SwiftLint configuration | **Passed with evidence** (minor notes in `FB-AUD-009`, `FB-AUD-010`) | External CVE DBs N/A (0 external Swift packages) |
| **Phase 16 — Git Integrity & Licensing** | Git commit log, tracked files, `LICENSE`, `THIRD_PARTY_NOTICES.md`, clean-room reimplementation audit reports | Checked `git_status`, `git_log`, `git_diff`, and file inventory | **Findings identified** (`FB-AUD-014`) | Reference repos outside connected folder not directly queried via filesystem tools |
| **Phase 17 — Product Acceptance** | End-to-end evaluation against the 11 product acceptance questions | Synthesized from source, runtime tests, and packaging checks | **Findings identified** | Documented in Section G/H |

---

## C. Architecture & Control-Flow Analysis (Phase 1)

### 1. Module Dependency Graph
Flowback's Swift Package Manager target graph (`Package.swift`) is strictly acyclic and layered bottom-up:

```text
FlowbackCore  (Domain, State, Policies, Sessions, Events, IPC wire types, Services)
  ├── FlowbackStorage       (SQLiteDatabase, Migrations, RecoveryManager, Repositories)
  ├── FlowbackFocus         (ApplicationController, WindowController, Adapters, UserIntentEngine, AttentionArbiter, FocusController)
  ├── FlowbackProviders     (AgentProvider, ProviderRegistry, BrainTranscriptParser, 10 Provider implementations)
  ├── FlowbackNotifications (NotificationManager)
  ├── FlowbackCLI           (flowback-cli executable)
  └── FlowbackTestHarness   (MockApplicationController, MockWindowController, MockIdleTracker, MockSpaceController)
        │
        ├── FlowbackServer  (UnixSocketServer, IPCHandler — depends on Core, Focus, Providers, Storage)
        ├── FlowbackUI      (MenuBarController, DashboardView, 10 Views — depends on Core, Focus, Providers, Storage, Notifications)
        └── FlowbackApp     (FlowbackService, AppDelegate, Flowback executable — composition root)
```

### 2. Primary Control-Flow Trace
1. **Hook / CLI Event Ingestion:** External agent invokes `flowback hook <provider>` or `flowback emit <json>` → `IPCClient.send()` connects to `~/.flowback/flowback.sock` → `UnixSocketServer.handleClient()` verifies `getpeereid()`, reads up to 2 MB, decodes `IPCRequest`, and calls `IPCHandler.handleRequest()` → `provider.parseLifecyclePayload(data:)` returns `AgentEvent` → `EventBus.publish(agentEvent:)` checks `EventDeduplicator.shouldProcess(event:)` (1.5s window) and yields to subscribers.
2. **Session State & Focus Arbitration:** `FlowbackService.agentEventsTask` consumes `EventBus.agentEvents()` on `@MainActor` → `SessionManager.handleEvent(event)` validates transitions via `AgentStateMachine` (or reactivates terminal sessions on new turns), records to `TimelineTracker`, and persists via `SessionRepository` → `EventRepository.saveEvent(event)` persists the event → If `event.type` is `.agentCompleted`, `.agentFailed`, or `.agentPermissionRequired`, `FlowbackService` enqueues an `AttentionRequest` in `AttentionArbiter` and calls `FocusController.handleSessionCompletion(...)` → `UserIntentEngine.evaluate(...)` returns a `FocusDecision` → If `.restoreOrigin` or `.restoreDestination`, `FocusController` checks `AttentionArbiter.canRestoreFocusNow()` and calls `restoreSession(_:)`; otherwise `NotificationManager.sendAttentionNotification(...)` posts a macOS notification → `UIEventCoalescer.schedule()` coalesces UI state synchronization (`updateMinimalUIState()`).
3. **Proactive Discovery Loop:** Every 10 seconds, `FlowbackService.backgroundRefreshTask` calls `refreshUIState()` → `ProviderRegistry.discoverAllActiveSessions()` polls providers → `SessionManager.mergeDiscoveredSessions(discovered)` transitions or enriches sessions and publishes synthesized `AgentEvent`s to `EventBus`.

### 3. Architectural Strengths & Boundary Violations
- **Strengths:** Providers never import `FlowbackFocus` or manipulate windows directly; `FocusController` never imports `FlowbackProviders` (communicating CLI resume hints via `ResumeCommandRegistry` in `FlowbackCore`); zero third-party Swift package dependencies reduce supply-chain surface.
- **High-Risk Coupling & State Ownership Violations:**
  1. **Duplicate Mutable State Across `FlowbackService`, `IPCHandler`, and `DashboardViewModel` (`FB-AUD-003`):** `FocusLockState` is stored independently in `FlowbackService.focusLock`, `IPCHandler.focusLock`, and `DashboardViewModel.focusLock` with one-way or missing synchronization. `PolicyConfiguration` is stored independently in `FlowbackService.configuration`, `DashboardViewModel.config`, and SQLite (`SettingsRepository`).
  2. **Global Singletons Mix with Dependency Injection:** `EventBus.shared`, `TimelineTracker.shared`, `ProviderRegistry.shared`, `ApplicationAdapterRegistry.shared`, `ResumeCommandRegistry.shared`, and `PermissionManager.shared` are used as defaults alongside injected instances, which causes `FocusController` in tests to fall back to live `PermissionManager.shared.isAccessibilityGranted()` when `permissionChecker` is omitted (`FB-AUD-001`).
  3. **Unused `LifecycleCoordinator` Component Protocol (`FB-AUD-012`):** `LifecycleCoordinator` defines `LifecycleManagedComponent` with ordered startup and LIFO rollback, but `FlowbackService` manually calls `transition(to:)` without registering a single `LifecycleManagedComponent`.

---

## D. Findings Register (Phase 2 – Phase 16)

---

### `FB-AUD-001` — `FocusController.restoreSession(_:)` Hard-Fails with `.permissionDenied` When `origin.windowIdentifier != nil` and Accessibility Is Untrusted, Breaking Application-Level Fallback and Causing Test Failures

- **Severity:** High
- **Confidence:** High
- **Category:** Focus Restoration / macOS Integration / Test Determinism
- **Affected Files & Lines:**
  - `Sources/FlowbackFocus/FocusController.swift:284-296`
  - `Sources/FlowbackProviders/Antigravity/AntigravityProvider.swift:141-156, 267-282`
  - `Sources/FlowbackProviders/AntigravityCLI/AntigravityCLIProvider.swift:469-484`
  - `Sources/FlowbackProviders/Windsurf/WindsurfProvider.swift:175-186`
  - `Sources/FlowbackProviders/OpenCode/OpenCodeProvider.swift:165-177`
  - `Sources/FlowbackTestRunner/main.swift:231-249`
  - `Sources/FlowbackTestRunner/ConversationAwarenessSuites.swift:200-346`
  - `Sources/FlowbackTestRunner/AuditRemediationSuites.swift:115-148`
- **Evidence:**
  In `Sources/FlowbackFocus/FocusController.swift:284-296`:
  ```swift
  // Permission check: if windowIdentifier is set, accessibility permission is mandatory to raise it
  if origin.windowIdentifier != nil && !permissionChecker() {
      logger.warning("Accessibility permission denied; cannot perform window-level restoration for session \(session.id)")
      return RestorationResult(
          outcome: .permissionDenied,
          sessionID: session.id,
          providerID: session.providerID,
          conversationID: convID,
          conversationTitle: convTitle,
          targetDescription: origin.displayLabel,
          message: "Accessibility permissions denied. Cannot perform window-level restoration."
      )
  }
  ```
  Meanwhile, `AntigravityProvider`, `AntigravityCLIProvider`, `WindsurfProvider`, and `OpenCodeProvider` capture `origin.windowIdentifier` (`kCGWindowNumber`) via `CGWindowListCopyWindowInfo`, which succeeds on macOS **without** Accessibility permission (`AXIsProcessTrusted()`). And in `FlowbackTestRunner`, `main.swift:248`, `ConversationAwarenessSuites.swift:279,281,282,304,345`, and `AuditRemediationSuites.swift:146` instantiate `FocusController` without passing `permissionChecker: { true }`, defaulting to `PermissionManager.shared.isAccessibilityGranted()`.
- **Concrete Failure Scenario:**
  1. **Production:** A user launches Flowback without granting Accessibility permission (or before granting it). An agent starts in VS Code or Terminal; `CGWindowListCopyWindowInfo` records `windowIdentifier = 101`. When the agent finishes, `FocusController.restoreSession` sees `origin.windowIdentifier != nil && !permissionChecker()` and immediately aborts with `.permissionDenied` (`isSuccessful = false`), never calling `adapter.restoreContext(...)` or `appController.activateApplication(...)`.
  2. **Test Suite:** Running `./.build/debug/FlowbackTestRunner` on any machine or CI runner where the terminal/runner lacks Accessibility trust produces 7 assertion failures (`Scenario A: Failed to restore origin for idle user` at `main.swift:248`, which also exits the suite early and skips Scenarios B–J; 5 failures in `ConversationAwarenessSuites.swift`; 1 failure in `AuditRemediationSuites.swift:146`).
- **Actual Impact:**
  Directly violates Flowback's documented product promise (`README.md`, `INSTALLATION.md`, `DiagnosticsView.swift`, `ReleaseNotesModel.swift`) that running without Accessibility permission *"gracefully degrades to application-level switching via `NSWorkspace` instead of raising a specific window."* Also makes `FlowbackTestRunner` non-deterministic across environments based on host TCC state.
- **Why Existing Safeguards/Tests Do Not Prevent It:**
  `FocusHardeningAndConcurrencySuites.swift` passed `permissionChecker: { true }` explicitly in its tests, whereas older suites in `main.swift`, `ConversationAwarenessSuites.swift`, `AuditRemediationSuites.swift`, and `AcceptanceScenariosTests.swift` omitted `permissionChecker` and relied on the developer's local terminal happening to have Accessibility permission enabled—or were masked by `FB-AUD-002`.
- **Recommended Remediation:**
  1. When `!permissionChecker()` and `origin.windowIdentifier != nil`, either degrade to application-level activation via `appController.activateApplication(app)` returning `.windowActivatedOnly` (with `fallbackUsed: "application_activation_without_accessibility"`), or only return `.permissionDenied` when application activation itself fails or when exact window raising is strictly required by policy.
  2. Inject a deterministic `permissionChecker: { true }` into all unit/integration test fixtures in `main.swift`, `ConversationAwarenessSuites.swift`, `AuditRemediationSuites.swift`, and `AcceptanceScenariosTests.swift` (while keeping dedicated tests for `permissionChecker: { false }`).
- **Regression Test Required:**
  Verify that `FocusController` in all mock-based acceptance suites passes when `AXIsProcessTrusted()` is `false` on the host, and add a dedicated test verifying the exact documented fallback behavior when Accessibility is denied.
- **Blocks Release:** **Yes**

---

### `FB-AUD-002` — `FlowbackTestRunner` Prematurely Exits with Code `0` Inside `V-008` (`MenuBarController.setup()`) in Headless Environments, Masking Prior Test Failures and Skipping ~400 Assertions

- **Severity:** High
- **Confidence:** High
- **Category:** Tests & Quality Assurance / CI Integrity
- **Affected Files & Lines:**
  - `Sources/FlowbackTestRunner/VorssaintDiscoverySuites.swift:176-182`
  - `Sources/FlowbackUI/MenuBar/MenuBarController.swift:42-51`
  - `Sources/FlowbackTestRunner/main.swift:566-597`
- **Evidence:**
  Executing `./.build/debug/FlowbackTestRunner` in a non-GUI/sandboxed session produces:
  ```text
  Passed printed: 627, Failed printed: 9, Reached summary: False
  returncode: 0
  stdout tail:
  [TEST SUITE] V-008: Menu Bar Controller Autosave Configuration
  ```
  Inside `VorssaintDiscoverySuites.swift:177-181`:
  ```swift
  await testGroup("V-008: Menu Bar Controller Autosave Configuration") {
      let menuBar = MenuBarController()
      menuBar.setup()
      assertTest(true, "V-008: MenuBarController sets autosaveName 'FlowbackStatusItem' during setup")
      menuBar.teardown()
  }
  ```
  `menuBar.setup()` calls `NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)`. Without an active GUI WindowServer session or initialized `NSApplication`, AppKit's status bar initialization calls `_exit(0)` internally.
- **Concrete Failure Scenario:**
  `FlowbackTestRunner` runs in a headless terminal, SSH session, or sandboxed CI step. Nine assertions fail in earlier suites (`totalTestsFailed = 9`). When execution reaches `V-008`, `NSStatusBar.system.statusItem(...)` terminates the process with exit code `0`. The final summary block (`if totalTestsFailed > 0 { exit(1) }`) at `main.swift:591` is never reached, and suites `V-010`, `V-014`, `V-019`–`V-023`, `V-015`–`V-018`, `FocusHardeningAndConcurrencySuites`, and `Canonical Version Metadata Consistency` (~400 assertions) never execute.
- **Actual Impact:**
  `FlowbackTestRunner` falsely returns exit code `0` even when tests fail and ~40% of the test suite is skipped. Furthermore, `V-008` itself contains a tautological assertion `assertTest(true, ...)` that does not even inspect `menuBar`.
- **Why Existing Safeguards/Tests Do Not Prevent It:**
  `Scripts/verify_all.sh` checks only the exit code of `swift run FlowbackTestRunner` rather than verifying that `"ALL VERIFICATION SUITES PASSED!"` was printed.
- **Recommended Remediation:**
  1. Guard `NSStatusBar.system.statusItem(...)` creation in headless test environments (or expose a testable configuration/autosaveName property on `MenuBarController` without instantiating a live WindowServer `NSStatusItem` when WindowServer is unavailable, e.g., checking `CGSessionCopyCurrentDictionary() != nil`).
  2. Register an `atexit` handler or track a `didCompleteAllSuites` flag so any premature `exit(0)` before `main.swift` finishes is flagged, and update `Scripts/verify_all.sh` to assert that `ALL VERIFICATION SUITES PASSED!` appears in stdout.
- **Regression Test Required:**
  Verify `FlowbackTestRunner` runs all suites through Suite 28, prints `TEST RESULTS SUMMARY`, and exits with code `1` whenever any assertion fails.
- **Blocks Release:** **Yes**

---

### `FB-AUD-003` — Split-Brain `focusLock` and `PolicyConfiguration` State Across `IPCHandler`, `FlowbackService`, and `DashboardViewModel`

- **Severity:** High
- **Confidence:** High
- **Category:** Architecture / Correctness / Concurrency
- **Affected Files & Lines:**
  - `Sources/FlowbackServer/IPCHandler.swift:10, 17-18, 46-52, 166-198, 298-308`
  - `Sources/FlowbackApp/FlowbackService.swift:58-60, 115, 124-127, 152-167, 253-259, 366-367, 424-433, 480-491`
  - `Sources/FlowbackUI/Dashboard/DashboardView.swift:278-283`
  - `Sources/FlowbackUI/Views/OverviewView.swift:55-57`
- **Evidence:**
  1. **CLI Focus Lock Ignored by Orchestrator:** `IPCHandler` (`@unchecked Sendable`) stores a mutable `private var focusLock: FocusLockState` (`IPCHandler.swift:18`) without any lock. When a user runs `flowback focus-lock 30m`, `IPCHandler.handleFocusLock` (`IPCHandler.swift:166-198`) mutates `self.focusLock` inside `IPCHandler`, but **never** notifies `FlowbackService`. When an agent finishes, `FlowbackService.handleAgentEvent` (`FlowbackService.swift:253-258`) evaluates `focusController.handleSessionCompletion(session: session, config: configuration, focusLock: self.focusLock, ...)` using `FlowbackService.focusLock` (which remains `isActive: false`!).
  2. **Overview UI Focus Lock "Disable" Button Overwritten:** In `OverviewView.swift:55-57`, clicking `"Disable"` sets `focusLock = FocusLockState(isActive: false)` on `dashboardViewModel.focusLock`. `FlowbackService` has no observer on `dashboardViewModel.focusLock`, so `FlowbackService.focusLock` and `IPCHandler.focusLock` remain active, and the next `updateMinimalUIState()` (`FlowbackService.swift:367`) overwrites `dashboardViewModel.focusLock = self.focusLock`, re-locking the UI!
  3. **Protected Applications Tab Never Persists or Syncs:** `ApplicationsView` (`DashboardView.swift:278-283`) mutates `dashboardViewModel.config.protectedApplications`, but unlike `SettingsView` and `AdvancedView`, `ApplicationsView` has no `.onChange` or `onSave` callback to `FlowbackService`! Thus, adding or removing a protected application in the `Applications` tab never saves to SQLite (`settingsRepository`) and is overwritten by `dashboardViewModel.config = configuration` on the next `updateMinimalUIState()` (`FlowbackService.swift:366`).
  4. **CLI `flowback config import` Never Updates In-Memory Config:** `IPCHandler.handleConfigImport` (`IPCHandler.swift:298-308`) saves the imported JSON to SQLite via `settingsRepo.importConfigurationJSON(jsonString)` but never updates `FlowbackService.configuration` or `dashboardViewModel.config`.
  5. **`AttentionArbiter` Timings Never Update After Startup:** `FlowbackService.start()` (`FlowbackService.swift:124-127`) initializes `AttentionArbiter(aggregationWindow: ..., cooldownDuration: ...)` once with `let` constants (`AttentionArbiter.swift:10-11`). Changing `focusCooldownMs` or `attentionAggregationMs` in Settings never updates `attentionArbiter`.
- **Concrete Failure Scenario:**
  A developer enters a meeting and runs `flowback focus-lock 30m` from the terminal. `flowback status` prints `focusLockActive: true`. Two minutes later, an Antigravity agent completes; `FlowbackService` reads its own `self.focusLock` (`false`) and steals focus during the meeting. Similarly, a user adds `com.obsproject.obs-studio` in the `Applications` tab; within 10 seconds, `refreshUIState()` -> `updateMinimalUIState()` wipes out the added bundle ID.
- **Actual Impact:**
  Core user-facing safety controls (CLI Focus Lock, Overview Disable Lock button, Protected Applications tab, CLI Config Import, and live cooldown slider adjustments) silently fail to take effect or revert unexpectedly, plus `IPCHandler.focusLock` has an unsynchronized data race across concurrent IPC client tasks.
- **Why Existing Safeguards/Tests Do Not Prevent It:**
  Unit tests tested `IPCHandler`, `SettingsRepository`, `UserIntentEngine`, and `ApplicationsView` in isolation rather than testing an end-to-end state mutation from `IPCHandler` or `ApplicationsView` into `FlowbackService.handleAgentEvent`.
- **Recommended Remediation:**
  1. Make `FlowbackService` (or a dedicated actor) the single authoritative owner of `focusLock` and `configuration`, passing `@Sendable` callbacks/delegates to `IPCHandler`, `OverviewView`, and `ApplicationsView` (or adding `onSave` to `ApplicationsView`).
  2. Convert `IPCHandler` to an `actor` (or remove mutable state from `IPCHandler` and read/write `focusLock` and `configuration` through `FlowbackService`).
  3. Add a method on `AttentionArbiter` (`updateTimings(aggregationWindow:cooldownDuration:)`) and invoke it whenever `configuration` changes.
- **Regression Test Required:**
  End-to-end test: invoke `IPCHandler` `focus-lock 30m`, then publish `.agentCompleted` through `EventBus` and assert `FlowbackService` suppresses focus restoration; invoke `IPCHandler` `config-import` and assert `FlowbackService.configuration` and `AttentionArbiter` reflect the imported values; mutate `ApplicationsView` protected apps and assert persistence in `SettingsRepository`.
- **Blocks Release:** **Yes**

---

### `FB-AUD-004` — `PolicyConfiguration.completionBehavior`, `permissionBehavior`, and `failureBehavior` Are Unimplemented Dead Fields, and `.agentWaiting` / `.agentIdle` Events Are Ignored by `FlowbackService`

- **Severity:** High
- **Confidence:** High
- **Category:** Correctness / Behavioral Contracts
- **Affected Files & Lines:**
  - `Sources/FlowbackCore/Policies/PolicyConfiguration.swift:7-9, 23-25, 46-48`
  - `Sources/FlowbackUI/Views/AdvancedView.swift:241-294`
  - `Sources/FlowbackFocus/UserIntentEngine.swift:92-215`
  - `Sources/FlowbackApp/FlowbackService.swift:239-269`
  - `Sources/FlowbackCore/Events/AgentEvent.swift:34-41`
- **Evidence:**
  - `PolicyConfiguration` defines `completionBehavior: CompletionBehavior` (`.restoreOrigin`, `.notificationOnly`, `.askUser`), `permissionBehavior: PermissionBehavior` (`.focusAgent`, `.notificationOnly`), and `failureBehavior: FailureBehavior` (`.focusAgent`, `.notificationOnly`), and `AdvancedView.swift:241-294` renders pickers for all three.
  - A repository-wide `grep` confirms that `completionBehavior`, `permissionBehavior`, and `failureBehavior` are **never referenced** in `UserIntentEngine.swift`, `FocusController.swift`, or `FlowbackService.swift`.
  - Furthermore, in `FlowbackService.swift:239`:
    ```swift
    // Check terminal states for attention
    if event.type == .agentCompleted || event.type == .agentFailed || event.type == .agentPermissionRequired {
    ```
    Even though `AgentEventType.isActionableForAttention` (`AgentEvent.swift:34-41`) returns `true` for `.agentCompleted`, `.agentFailed`, `.agentPermissionRequired`, `.agentWaiting`, and `.agentIdle`, `FlowbackService.handleAgentEvent` ignores `.agentWaiting` and `.agentIdle`.
- **Concrete Failure Scenario:**
  1. A user opens **Advanced Preferences** and sets **Completion Behavior** to `Notification Only` (or **Permission Request Behavior** to `Notification Only` / **Failure Behavior** to `Notification Only`). When an agent completes, requires permission, or fails while the user is idle, `UserIntentEngine.evaluate` completely ignores those settings and switches window focus anyway.
  2. An OpenCode session finishes a turn and emits `session.idle` (which `OpenCodeProvider` maps to `.agentWaiting`), or Claude Code / Codex emits `status: "waiting"`. `FlowbackService.handleAgentEvent` neither enqueues an `AttentionRequest` nor notifies/focuses the user.
- **Actual Impact:**
  Three prominent user-facing policy controls in Advanced Preferences are non-functional UI facades, and agents entering `.waiting` (including OpenCode `session.idle`) never trigger user notifications or focus arbitration.
- **Why Existing Safeguards/Tests Do Not Prevent It:**
  `GeneralSidebarDestinationsSuites.swift` (`V-020`) only tested JSON serialization/deserialization of `completionBehavior`, `permissionBehavior`, and `failureBehavior`, never testing whether `UserIntentEngine.evaluate` or `FlowbackService` actually honors them!
- **Recommended Remediation:**
  1. Pass the triggering `AgentEventType` (or `session.state`) into `UserIntentEngine.evaluate(...)` and enforce `config.completionBehavior` (when `.agentCompleted` / `.completed`), `config.permissionBehavior` (when `.agentPermissionRequired` / `.permissionRequired`), and `config.failureBehavior` (when `.agentFailed` / `.failed`), returning `.notifyOnly` when set to `.notificationOnly` or `.askUser`.
  2. Update `FlowbackService.handleAgentEvent` (`FlowbackService.swift:239`) to use `if event.type.isActionableForAttention` and map `.agentWaiting` to `AttentionPriority.waiting`.
- **Regression Test Required:**
  Unit tests in `UserIntentEngineTests` / `FlowbackTestRunner` asserting that `completionBehavior = .notificationOnly`, `permissionBehavior = .notificationOnly`, and `failureBehavior = .notificationOnly` each suppress automatic focus switching even when the user is idle and `focusPolicy == .smart`.
- **Blocks Release:** **Yes**

---

### `FB-AUD-005` — `SQLiteDatabase.runInTransaction` Actor Reentrancy Across `await block()` Breaks Transaction Isolation and Risks Nested Transaction Failures

- **Severity:** High
- **Confidence:** High
- **Category:** Concurrency / Persistence
- **Affected Files & Lines:**
  - `Sources/FlowbackStorage/SQLiteDatabase.swift:127-137`
- **Evidence:**
  In `Sources/FlowbackStorage/SQLiteDatabase.swift:127-137`:
  ```swift
  public func runInTransaction<T: Sendable>(_ block: @Sendable () async throws -> T) async throws -> T {
      try execute(sql: "BEGIN IMMEDIATE TRANSACTION;")
      do {
          let result = try await block()
          try execute(sql: "COMMIT;")
          return result
      } catch {
          _ = try? execute(sql: "ROLLBACK;")
          throw error
      }
  }
  ```
  Because `SQLiteDatabase` is a Swift `actor`, suspending at `try await block()` allows other tasks queued on `SQLiteDatabase` to execute on the same SQLite connection (`box.handle`) while the transaction is still open.
- **Concrete Failure Scenario:**
  Task A calls `db.runInTransaction { try await db.execute(...); try await db.execute(...) }`. At the first `await` inside `block()`, Task B enters `db.execute(...)` or `db.runInTransaction(...)` on the same `SQLiteDatabase` actor:
  - If Task B calls `runInTransaction`, SQLite fails with `SQLITE_ERROR (1): cannot start a transaction within a transaction`.
  - If Task B calls `execute(...)` (e.g., saving an unrelated session), Task B's write is silently included inside Task A's transaction—and if Task A throws, Task B's write is rolled back!
- **Actual Impact:**
  Data loss (unintended rollback of unrelated concurrent writes) or spurious `SQLiteError.executionFailed` under concurrent database access.
- **Why Existing Safeguards/Tests Do Not Prevent It:**
  The transaction rollback test in `FlowbackTestRunner/main.swift:347-360` runs a single sequential transaction with no concurrent tasks accessing `auditDb`.
- **Recommended Remediation:**
  Provide a synchronous transaction closure `public func runInTransaction<T: Sendable>(_ block: (SQLiteDatabase) throws -> T) throws -> T` (since all `SQLiteDatabase.execute` and `query` calls are synchronous C SQLite3 operations inside the actor and have no reason to suspend across actor hops!), or guard `runInTransaction` with a non-reentrant async queue/gate so external callers wait until `COMMIT`/`ROLLBACK` completes.
- **Regression Test Required:**
  Concurrent test launching two overlapping `runInTransaction` tasks and concurrent `saveSession` calls on the same `SQLiteDatabase` instance, verifying zero `cannot start a transaction within a transaction` errors and strict rollback isolation.
- **Blocks Release:** **Yes**

---

### `FB-AUD-006` — `AgentEvent.init(from: Decoder)` and `AgentSession.init` Bypass `SecretSanitizer`

- **Severity:** Medium
- **Confidence:** High
- **Category:** Security & Privacy
- **Affected Files & Lines:**
  - `Sources/FlowbackCore/Events/AgentEvent.swift:125-171`
  - `Sources/FlowbackCore/Domain/AgentSession.swift:27-90, 117-177`
- **Evidence:**
  - `AgentEvent.init(...)` (lines 74–86) calls `SecretSanitizer.sanitizeMetadata(metadata)` and `SecretSanitizer.sanitizeText(...)` on `conversationTitle` and `taskSummary`.
  - However, `AgentEvent.init(from decoder: Decoder)` (lines 125–171) decodes `metadata`, `conversationTitle`, and `taskSummary` directly from the decoder without invoking `SecretSanitizer`.
  - Likewise, `AgentSession.init` (`AgentSession.swift:27-90`) does not sanitize `metadata`, `conversationTitle`, `taskSummary`, or `errorDescription` when sessions are constructed directly by provider `discoverActiveSessions()` methods (`AntigravityProvider`, `AntigravityCLIProvider`, `WindsurfProvider`, `CursorBackgroundProvider`).
- **Concrete Failure Scenario:**
  A transcript or cloud agent summary discovered by `discoverActiveSessions()` (or an `AgentEvent` decoded via `JSONDecoder`) contains a Bearer token, API key (`sk-...`, `ghp_...`), or password in the user prompt/title or error string. Because `AgentSession.init` and `AgentEvent.init(from:)` do not call `SecretSanitizer`, the raw secret is stored in memory, displayed in the Dashboard/Menu Bar UI, and persisted in plaintext to `~/.flowback/flowback.sqlite` (`sessions` table).
- **Actual Impact:**
  Partial bypass of the `PRIVACY.md` and `F-20` invariant (*"Zero secrets persisted or displayed in UI"*). Note that `DiagnosticReportExporter` still sanitizes on export, and `TimelineTracker` sanitizes `details` and `explanation` (though **not** `summary` in `TimelineTracker.swift:59`!).
- **Why Existing Safeguards/Tests Do Not Prevent It:**
  Test `F-20` (`ExtendedRemediationSuites.swift:204-215`) only tested `AgentEvent(...)` direct initialization, not `JSONDecoder().decode(AgentEvent.self, ...)` or `AgentSession(...)` initialization or `TimelineTracker.record(summary:)`.
- **Recommended Remediation:**
  1. Apply `SecretSanitizer.sanitizeMetadata` and `SecretSanitizer.sanitizeText` inside `AgentEvent.init(from:)`, `AgentSession.init`, and `AgentSession.init(from:)`.
  2. Sanitize `summary` (in addition to `details` and `explanation`) in `TimelineTracker.record(...)` (`TimelineTracker.swift:59`).
- **Regression Test Required:**
  Decode an `AgentEvent` and initialize an `AgentSession` containing `sk-...` and `Bearer ...` in `metadata`, `conversationTitle`, `taskSummary`, and `errorDescription`, and assert all fields are redacted.
- **Blocks Release:** No (P1 before public release)

---

### `FB-AUD-007` — `AsyncProcessRunner` Does Not Escalate to `SIGKILL` or Terminate Process Groups When a Timed-Out or Cancelled Process Ignores `SIGTERM`

- **Severity:** Medium
- **Confidence:** High
- **Category:** Process Management & Concurrency
- **Affected Files & Lines:**
  - `Sources/FlowbackCore/Services/AsyncProcessRunner.swift:199-231`
- **Evidence:**
  In `AsyncProcessRunner.swift:209-211` (`cancel()`) and `225-227` (`terminateForTimeout(seconds:)`):
  ```swift
  if process.isRunning {
      process.terminate()
  }
  ```
  `Foundation.Process.terminate()` sends only `SIGTERM` to the immediate child PID. It does not place the child in a process group (`setpgid`), does not signal child descendants, and does not send `SIGKILL` (`kill(pid, SIGKILL)`) if the child remains alive after a grace period.
- **Concrete Failure Scenario:**
  A probed CLI binary returns a hung wrapper script or traps `SIGTERM` while spawning a child process. `AsyncProcessRunner` resumes its continuation with `.timedOut`, but the underlying OS process (and any descendants) remains running in the background indefinitely.
- **Actual Impact:**
  Potential orphaned background processes if an external CLI binary misbehaves or hangs ignoring `SIGTERM`.
- **Why Existing Safeguards/Tests Do Not Prevent It:**
  Test `F-07` (`AuditRemediationSuites.swift:355-368`) tests timeout against `/bin/sleep 5`, which terminates immediately on `SIGTERM`.
- **Recommended Remediation:**
  After calling `process.terminate()`, schedule a short non-blocking escalation task (e.g., 200ms) that checks `process.isRunning` and sends `kill(process.processIdentifier, SIGKILL)` if still alive.
- **Regression Test Required:**
  Run `/bin/sh -c 'trap "" TERM; sleep 10'` via `AsyncProcessRunner.run(..., timeoutSeconds: 0.2)` and verify that the child PID is terminated via `SIGKILL` after timeout.
- **Blocks Release:** No (P1)

---

### `FB-AUD-008` — Synchronous Main-Thread Process Wait (`tccutil`) and AppleScript Execution (`NSAppleScript`) Can Freeze the UI Runloop

- **Severity:** Medium
- **Confidence:** High
- **Category:** UI / Responsiveness / Process Management
- **Affected Files & Lines:**
  - `Sources/FlowbackUI/Views/AdvancedView.swift:49-71`
  - `Sources/FlowbackUI/Views/SupportView.swift:145-151`
- **Evidence:**
  1. In `AdvancedView.swift:49-71`:
     ```swift
     @MainActor
     public func resetSystemPermissions(bundleIdentifier: String? = nil) {
         let id = bundleIdentifier ?? (Bundle.main.bundleIdentifier ?? "com.flowback.app")
         let process = Process()
         process.executableURL = URL(fileURLWithPath: "/usr/bin/tccutil")
         process.arguments = ["reset", "All", id]
         do {
             try process.run()
             process.waitUntilExit()
     ```
     `process.waitUntilExit()` blocks `@MainActor` synchronously without a timeout instead of using `AsyncProcessRunner.run(...)`.
  2. In `SupportView.swift:145-151`:
     ```swift
     Button {
         let terminalScript = "tell application \"Terminal\" to do script \"flowback doctor\" activate"
         if let script = NSAppleScript(source: terminalScript) {
             var error: NSDictionary?
             script.executeAndReturnError(&error)
         }
     }
     ```
     `NSAppleScript.executeAndReturnError` executes synchronously on the main thread, blocking UI rendering while Terminal launches or while macOS prompts for Automation (`com.apple.security.automation.apple-events`) consent. Also note that `"tell application \"Terminal\" to do script \"flowback doctor\" activate"` is invalid single-line AppleScript syntax (`do script "flowback doctor"` and `activate` must be on separate lines or statements), so `executeAndReturnError` silently fails with a syntax error and discards `error`!
- **Concrete Failure Scenario:**
  1. Clicking `"Run 'flowback doctor' in Terminal"` in `SupportView` silently does nothing because `"tell application \"Terminal\" to do script \"flowback doctor\" activate"` is a single-line AppleScript syntax error (`Expected end of line, etc. but found identifier "activate"`), and the error dictionary is ignored!
  2. Clicking `"Reset Permissions"` in `AdvancedView` blocks the main thread until `tccutil` exits.
- **Actual Impact:**
  The `"Run 'flowback doctor' in Terminal"` button in the Support tab is completely broken due to the AppleScript syntax error and swallowed error dictionary, and `resetSystemPermissions` blocks the main runloop.
- **Why Existing Safeguards/Tests Do Not Prevent It:**
  No test exercises the `"Run 'flowback doctor' in Terminal"` button action or `resetSystemPermissions()`.
- **Recommended Remediation:**
  1. In `AdvancedViewModel.resetSystemPermissions`, use `AsyncProcessRunner.run(executablePath: "/usr/bin/tccutil", arguments: ["reset", "All", id], timeoutSeconds: 5.0)` asynchronously.
  2. In `SupportView`, fix the multi-line script (`"tell application \"Terminal\"\nactivate\ndo script \"flowback doctor\"\nend tell"`), execute off the main thread (or via `osascript` with `AsyncProcessRunner`), and surface any error in `viewModel.exportMessage`.
- **Regression Test Required:**
  Compile/validate the AppleScript string via `NSAppleScript.compileAndReturnError` in a test assertion and verify `compileAndReturnError` succeeds with `nil` error.
- **Blocks Release:** No (P1)

---

### `FB-AUD-009` — Application Adapter Inconsistencies (`GenericApplicationAdapter`, `BraveAdapter`, and Duplicate `com.codeium.windsurf` Registration)

- **Severity:** Medium
- **Confidence:** High
- **Category:** Application Adapters / Focus Restoration
- **Affected Files & Lines:**
  - `Sources/FlowbackFocus/Adapters/GenericApplicationAdapter.swift:38-45`
  - `Sources/FlowbackFocus/Adapters/BraveAdapter.swift:10-16, 29-42`
  - `Sources/FlowbackFocus/Adapters/VSCodeAdapter.swift:16`
- **Evidence:**
  1. `GenericApplicationAdapter.restoreContext` (`GenericApplicationAdapter.swift:38-45`) calls `await appController.activateApplication(app)` **first** (raising whatever window was last active in that app) and then calls `_ = windowController.raiseWindow(windowID: winID, pid: app.processIdentifier)` without checking its return value or falling back to `context.windowTitle` / `context.workspacePath` matching. All specialized adapters (`VSCodeAdapter`, `CursorAdapter`, `WindsurfAdapter`, `TerminalAdapter`) raise the target window before activating and fall back to title/workspace matching when `winID` is stale.
  2. `BraveAdapter.restoreContext` (`BraveAdapter.swift:29-34`) calls `NSWorkspace.shared.open(url)` directly instead of using an injected opener, and its `supportedBundles` (`BraveAdapter.swift:10-16`) omits `com.brave.Browser.beta` and `com.microsoft.edgemac`, contradicting `APPLICATION_ADAPTERS.md:77` and `README.md:94`.
  3. `VSCodeAdapter.supportedBundles` (`VSCodeAdapter.swift:16`) includes `"com.codeium.windsurf"`, duplicating `WindsurfAdapter`.
- **Concrete Failure Scenario:**
  When restoring focus to a generic macOS IDE (e.g., Xcode `com.apple.dt.Xcode` or Zed `dev.zed.Zed`, which use `GenericApplicationAdapter`) after its `windowIdentifier` changes or when only `workspacePath`/`windowTitle` is known, `GenericApplicationAdapter` never attempts workspace or window-title matching, activating the wrong window.
- **Actual Impact:**
  Degraded window-selection accuracy for non-VSCode/Cursor/Windsurf editors (such as Xcode, Zed, JetBrains IDEs) and missing bundle IDs for Brave Beta and Microsoft Edge.
- **Why Existing Safeguards/Tests Do Not Prevent It:**
  Adapter tests only checked `canHandle(bundleIdentifier:)` for `VSCodeAdapter`, `CursorAdapter`, `WindsurfAdapter`, and `TerminalAdapter`.
- **Recommended Remediation:**
  1. Align `GenericApplicationAdapter.restoreContext` with `VSCodeAdapter`/`CursorAdapter` (raise exact `windowIdentifier` → match `workspacePath` folder name → match `windowTitle` → activate application).
  2. Remove `"com.codeium.windsurf"` from `VSCodeAdapter.supportedBundles`.
  3. Add `"com.brave.Browser.beta"` and `"com.microsoft.edgemac"` to `BraveAdapter.supportedBundles`.
- **Regression Test Required:**
  Unit test for `GenericApplicationAdapter` verifying workspace/title fallback when `windowIdentifier` is nil or stale, and bundle coverage tests for `BraveAdapter`.
- **Blocks Release:** No (P1)

---

### `FB-AUD-010` — Provider Health & Discovery Defects Across `CodexProvider`, `AiderProvider`, `ClaudeCodeProvider`, `OpenCodeProvider`, and `AntigravityProvider`

- **Severity:** Medium
- **Confidence:** High
- **Category:** Agent Providers / Performance
- **Affected Files & Lines:**
  - `Sources/FlowbackProviders/Codex/CodexProvider.swift:12-23`
  - `Sources/FlowbackProviders/Aider/AiderProvider.swift:12-21`
  - `Sources/FlowbackProviders/ClaudeCode/ClaudeCodeProvider.swift:17-37, 77-84`
  - `Sources/FlowbackProviders/OpenCode/OpenCodeProvider.swift:262-289`
  - `Sources/FlowbackProviders/Antigravity/AntigravityProvider.swift:382`
- **Evidence:**
  1. `CodexProvider.checkHealth()` (`CodexProvider.swift:12-23`) and `AiderProvider.checkHealth()` (`AiderProvider.swift:12-21`) hardcode `isInstalled: false`, `hookInstalled: false`, `hookExecutable: false`. Neither checks for `~/.codex`, `/opt/homebrew/bin/codex`, `/opt/homebrew/bin/aider`, or `PATH`. Consequently, `DiagnosticsView` and `flowback doctor` **always** show OpenAI Codex and Aider as `"Not Detected"` even when installed!
  2. `ClaudeCodeProvider.checkHealth()` (`ClaudeCodeProvider.swift:17-24`) sets `hookInstalled = fm.fileExists(atPath: settingsPath)` merely by checking if `~/.claude/settings.json` exists—without checking if Flowback's hook is configured inside it—and its `installIntegration()` / `uninstallIntegration()` (`ClaudeCodeProvider.swift:77-84`) are empty log statements that do not touch disk.
  3. `OpenCodeProvider.discoverActiveSessions()` (`OpenCodeProvider.swift:262-289`) checks `NSWorkspace.shared.runningApplications` for `ai.opencode.app` / `com.opencode` and returns an `AgentSession(id: "opencode-proc-\(pid)", state: .running, startedAt: Date(), updatedAt: Date())` every 10 seconds whenever the OpenCode app is open—even if the user is idle and no agent session is running!
  4. `AntigravityProvider.installIntegration()` (`AntigravityProvider.swift:382`) writes `export PATH="$HOME/.local/bin:/usr/local/bin:$PATH"; flowback hook antigravity`, omitting `/opt/homebrew/bin` (which `AntigravityCLIProvider` and `WindsurfProvider` include).
- **Concrete Failure Scenario:**
  - A developer installs OpenAI Codex or Aider via Homebrew; `flowback doctor` and the Dashboard Diagnostics tab permanently report them as `"Not Detected"`.
  - A developer leaves `OpenCode.app` open in the background; `FlowbackService`'s 10-second discovery timer continuously reports `1 active agent` (`opencode-proc-<pid>`) forever.
  - A developer on Apple Silicon installs `flowback` to `/opt/homebrew/bin/flowback` and clicks `"Repair / Install Hooks"` for Antigravity Desktop; Antigravity IDE's hook fails with `flowback: command not found` because `/opt/homebrew/bin` is missing from `AntigravityProvider`'s `PATH`.
- **Actual Impact:**
  Inaccurate provider health reporting for Codex, Aider, and Claude Code; phantom active sessions for OpenCode; and broken hook execution for Homebrew installs of `flowback` under Antigravity Desktop.
- **Why Existing Safeguards/Tests Do Not Prevent It:**
  Tests for `CodexProvider` and `AiderProvider` only checked `health.isSupported == true`, not `isInstalled` detection; `AntigravityProvider` hook test only checked `cmd.contains("flowback hook antigravity")`, not `/opt/homebrew/bin` in `PATH`.
- **Recommended Remediation:**
  1. Add binary/config path checks (`/opt/homebrew/bin`, `/usr/local/bin`, `~/.local/bin`, `~/.codex`, `~/.aider*`) to `CodexProvider.checkHealth()` and `AiderProvider.checkHealth()`.
  2. Inspect `~/.claude/settings.json` contents for `flowback` in `ClaudeCodeProvider.checkHealth()`.
  3. Remove the naive process-existence fabrication in `OpenCodeProvider.discoverActiveSessions()` (or check actual OpenCode session state) so an idle open window is not permanently marked as a running agent.
  4. Add `/opt/homebrew/bin` to `AntigravityProvider.installIntegration()`'s `PATH`.
- **Regression Test Required:**
  Assert `AntigravityProvider` installed hook includes `/opt/homebrew/bin`, and test `CodexProvider`/`AiderProvider` health detection with injected binary/config paths.
- **Blocks Release:** No (P1)

---

### `FB-AUD-011` — Stale `v0.4.0` Artifacts in `dist/`, All-Zero SHA-256 in `Formula/flowback-cli.rb`, Hardcoded `v0.4.0` in `publish_milestone_releases.sh`, and Unnotarized Ad-Hoc Signature

- **Severity:** Medium (Release Blocker for Distribution)
- **Confidence:** High
- **Category:** Packaging, Signing & Distribution
- **Affected Files & Lines:**
  - `Formula/flowback-cli.rb:6`
  - `dist/release-manifest.json:3, 6`
  - `dist/SHA256SUMS:1-4`
  - `Website/release-manifest.json:10-40`
  - `Scripts/publish_milestone_releases.sh:67`
  - `Scripts/validate_version_sync.sh:104-118`
- **Evidence:**
  1. `Formula/flowback-cli.rb:6` contains a placeholder checksum:
     ```ruby
     version "0.4.1"
     sha256 "0000000000000000000000000000000000000000000000000000000000000000"
     ```
     `Scripts/validate_version_sync.sh:104-110` checks only `grep -q "version \"${VERSION}\""`, allowing the all-zero SHA-256 to pass validation.
  2. Running `bash Scripts/validate_release.sh --local` fails with 3 errors:
     ```text
     ✗ FAIL: Distribution ZIP missing in /Users/abin/workspace/projects/flowback/dist
     ✗ FAIL: Manifest version mismatch: expected '0.4.1', got '0.4.0'
     ✗ FAIL: Cask SHA-256 (7fdcc8a5597aba48c82128a747530b3820e970f67f9ba334093ab93647d0ed8e) does not match archive hash ()
     ```
     Because `dist/` still contains `Flowback-0.4.0-*.dmg/zip` and `dist/release-manifest.json` at `0.4.0`.
  3. `Website/release-manifest.json` claims `version: "0.4.1"` and `gitCommit: "094e1a93ec0b3ae3e9f2cbe9ec598ef7f7a68a4a"`, but its 4 artifact `sha256` values (`650af3b7...`, `919fa5d6...`, `02dbbd67...`, `7fdcc8a5...`) are **byte-for-byte identical** to the `Flowback-0.4.0-*` hashes in `dist/SHA256SUMS`! In other words, `Website/release-manifest.json` and `Casks/flowback.rb` were manually edited to say `0.4.1` without actually rebuilding and hashing the `0.4.1` archives!
  4. `Scripts/publish_milestone_releases.sh:67` still lists `"v0.4.0|HEAD|...|true"` as the latest milestone and omits `v0.4.1`.
  5. `dist/Flowback.app` is ad-hoc signed (`Signature=adhoc`) without a Developer ID certificate or stapled notarization ticket.
- **Concrete Failure Scenario:**
  If a user downloads `Flowback-0.4.1-macos.zip` or installs via Homebrew (`Casks/flowback.rb` or `Formula/flowback-cli.rb`), the SHA-256 checksums in `Website/release-manifest.json`, `Casks/flowback.rb`, and `Formula/flowback-cli.rb` will not match the actual `v0.4.1` release artifacts, and macOS Gatekeeper will block `Flowback.app` unless signed with Developer ID and notarized.
- **Actual Impact:**
  Broken checksum verification for `v0.4.1` downloads and Homebrew formulas, plus Gatekeeper rejection on clean Macs.
- **Why Existing Safeguards/Tests Do Not Prevent It:**
  `validate_version_sync.sh` checks only version strings, not whether `Website/release-manifest.json` hashes are distinct from prior releases or whether `Formula/flowback-cli.rb` has a placeholder `0000...` hash.
- **Recommended Remediation:**
  1. Re-run `bash Scripts/package_release_artifacts.sh 0.4.1 universal 2` after fixing P0 code findings so `dist/`, `Website/release-manifest.json`, and `Casks/flowback.rb` contain genuine `0.4.1` artifact hashes.
  2. Update `Scripts/validate_version_sync.sh` to reject all-zero `sha256` placeholders and update `Scripts/publish_milestone_releases.sh` to include `v0.4.1`.
  3. Sign with a valid `Developer ID Application` certificate and notarize via `xcrun notarytool` + `xcrun stapler staple` before public distribution.
- **Regression Test Required:**
  `bash Scripts/validate_release.sh --local 0.4.1` (and `--release 0.4.1` once signed/notarized) must pass 10/10 checks.
- **Blocks Release:** **Yes**

---

### `FB-AUD-012` — `AttentionArbiter` Queue Retains Already-Restored Sessions, and `LifecycleCoordinator` Component Rollback Is Unused in `FlowbackService`

- **Severity:** Medium
- **Confidence:** High
- **Category:** Lifecycle & State Consistency
- **Affected Files & Lines:**
  - `Sources/FlowbackApp/FlowbackService.swift:92-218, 250-269, 417-422`
  - `Sources/FlowbackFocus/FocusController.swift:120-126, 487-498`
- **Evidence:**
  1. In `FlowbackService.handleAgentEvent` (`FlowbackService.swift:241-268`), whenever an agent completes, fails, or requires permission, `FlowbackService` unconditionally calls `await attentionArbiter.enqueue(req)` **before** calling `focusController.handleSessionCompletion(...)`. If `decision.shouldActivateApp == true` and focus is immediately restored (`result.outcome.isSuccessful`), neither `FlowbackService` nor `FocusController` removes `req` from `attentionArbiter`! Similarly, `FocusController.manualFocusSession(_:)` (`FocusController.swift:487-498`) never calls `await arbiter.remove(sessionID: session.id)`.
  2. Because `attentionArbiter.pendingRequests()` remains non-empty, `MenuBarController.updateStatusItemAppearance()` (`MenuBarController.swift:72-76`) permanently displays the `exclamationmark.circle.fill` icon (`"Flowback — N agent(s) need attention"`) and `OverviewView` displays the `"Attention Required"` section even for completed sessions that were already automatically or manually focused! (Furthermore, in `OverviewView.swift:109`, the `"Review & Focus"` button inside `"Attention Required"` only renders `if let session = activeSessions.first(where: { $0.id == req.sessionID })` — which is **false** for `.completed` and `.failed` sessions because they are terminal and no longer in `activeSessions`!)
  3. `FlowbackService` never registers any `LifecycleManagedComponent` with `lifecycleCoordinator.start(components:)`, calling only manual state transitions (`FlowbackService.swift:99, 193`).
- **Concrete Failure Scenario:**
  An agent finishes its task (`state = .completed`). The user is idle, so Flowback automatically restores focus to VS Code. However:
  - The menu bar icon switches to `exclamationmark.circle.fill 1` ("1 agent(s) need attention") and never clears for the rest of the app's lifetime!
  - Opening the Dashboard shows the completed agent under `"Attention Required"`, and its `"Review & Focus"` button is missing because `activeSessions` excludes `.completed` sessions (`OverviewView.swift:109`)!
- **Actual Impact:**
  Persistent false-positive "Attention Required" alert state in both the Menu Bar and Dashboard Overview after any agent completes or fails, with no button to dismiss or focus completed/failed items in `OverviewView`.
- **Why Existing Safeguards/Tests Do Not Prevent It:**
  `AttentionArbiter` was unit-tested for `enqueue` and `dequeueHighestPriority`, but no test checked whether `FlowbackService` removes items from `attentionArbiter` upon successful automatic or manual focus restoration, or whether `OverviewView` looks up `allSessions` vs `activeSessions` for attention items.
- **Recommended Remediation:**
  1. Call `await arbiter.remove(sessionID: session.id)` in `FocusController.handleSessionCompletion` and `FocusController.manualFocusSession` whenever `result.outcome.isSuccessful` is `true` (and when a new active turn starts for `session.id`).
  2. In `OverviewView.swift:109`, look up `allSessions` (or pass a session lookup/dismiss action) so completed/failed attention items always have a working `"Review & Focus"` and `"Dismiss"` button.
- **Regression Test Required:**
  Verify that after `handleSessionCompletion` succeeds in restoring focus (or after `manualFocusSession` succeeds), `attentionArbiter.pendingRequests()` no longer contains `session.id`.
- **Blocks Release:** No (P1)

---

### `FB-AUD-013` — `Scripts/test_live_macos.sh` JXA Bug Always Reports `AXIsProcessTrusted: false`, and `Scripts/uninstall.sh` Leaves Current Hooks Behind

- **Severity:** Low
- **Confidence:** High
- **Category:** Scripts & Tooling
- **Affected Files & Lines:**
  - `Scripts/test_live_macos.sh:25`
  - `Scripts/uninstall.sh:24-48`
- **Evidence:**
  1. `Scripts/test_live_macos.sh:25` runs:
     ```bash
     AX_TRUSTED=$(osascript -l JavaScript -e '$.AXIsProcessTrusted()' 2>/dev/null || echo "false")
     ```
     Without `ObjC.import('ApplicationServices');`, JXA throws `execution error: Error: TypeError: $.AXIsProcessTrusted is not a function (-2700)` and always prints `false`.
  2. `Scripts/uninstall.sh:33-35` only deletes `'flowback-agent-focus'` from `~/.gemini/config/hooks.json`, ignoring the current keys `'flowback-antigravity'` and `'flowback-antigravity-cli'`, and does not clean up `~/.codeium/windsurf/hooks.json` or `~/.config/opencode/plugins/flowback.js`.
- **Concrete Failure Scenario:**
  Running `bash Scripts/uninstall.sh` leaves `flowback-antigravity`, `flowback-antigravity-cli`, Windsurf hooks, and the OpenCode plugin active after removing `/usr/local/bin/flowback`.
- **Actual Impact:**
  Incomplete hook uninstallation and misleading live test output.
- **Why Existing Safeguards/Tests Do Not Prevent It:**
  `2>/dev/null || echo "false"` silenced the JXA error in `test_live_macos.sh`, and `uninstall.sh` was not updated when `F-03` renamed the hook keys.
- **Recommended Remediation:**
  1. Change `Scripts/test_live_macos.sh:25` to `osascript -l JavaScript -e 'ObjC.import("ApplicationServices"); $.AXIsProcessTrusted()'`.
  2. Update `Scripts/uninstall.sh` to remove `flowback-antigravity` and `flowback-antigravity-cli` from `~/.gemini/config/hooks.json`, remove Flowback hooks from `~/.codeium/windsurf/hooks.json`, and remove `~/.config/opencode/plugins/flowback.js`.
- **Regression Test Required:**
  Test `uninstall.sh` hook cleanup logic against a temporary directory containing all three hook formats.
- **Blocks Release:** No (P2)

---

### `FB-AUD-014` — Documentation Drift, Non-Existent Documented CLI Flags, Tracked `bmcbrand.zip` Archive, and Test Runner Mutating Tracked Screenshots

- **Severity:** Low
- **Confidence:** High
- **Category:** Documentation & Repository Hygiene
- **Affected Files & Lines:**
  - `INSTALLATION.md:107, 152` & `TROUBLESHOOTING.md:80`
  - `Docs/CONFIGURATION.md:9-12` & `README.md:146`
  - `EVENT_PROTOCOL.md:44-89`
  - `ARCHITECTURE.md:45` & `FOCUS_ENGINE.md:15`
  - `SUPPORT.md:30`
  - `Sources/FlowbackTestRunner/VisualParitySuites.swift:38-41`
  - `bmcbrand.zip` (root directory)
- **Evidence:**
  1. **Non-existent CLI flags in docs:** `INSTALLATION.md:152` documents `flowback hook antigravity --uninstall` and `TROUBLESHOOTING.md:80` documents `flowback hook antigravity --install`. In `Sources/FlowbackCLI/main.swift:70-89`, `flowback hook <provider>` unconditionally blocks waiting to read JSON from `stdin` (`FileHandle.standardInput.readDataToEndOfFile()`) and has no `--install` or `--uninstall` flag! Running `flowback hook antigravity --install` in a terminal hangs waiting for `stdin` EOF!
  2. **Config storage location mismatch:** `README.md:146` and `Docs/CONFIGURATION.md:9-12` instruct users to edit `~/.flowback/config.json`. Flowback never reads `~/.flowback/config.json` automatically; configuration is stored in SQLite (`~/.flowback/flowback.sqlite` `settings` table) and only imported via `flowback config import <file>`.
  3. **Event Protocol schema mismatch:** `EVENT_PROTOCOL.md:44-89` documents an `origin` object and required `timestamp` in the v1 JSON schema, and claims raw `nc -U ~/.flowback/flowback.sock` with `{"command":"emit","params":{...}}` works. In reality, `IPCRequest` expects `{"command":"emit","payload":"<base64>"}`, and `GenericHookPayload` (`GenericHookProvider.swift:7-32`) does not decode `origin` or parse `timestamp`!
  4. **Deduplication window & doctor output mismatch:** `ARCHITECTURE.md:45` and `FOCUS_ENGINE.md:15` state a `500ms` deduplication window, whereas `EventDeduplicator.swift:8` uses `1.5s`. `INSTALLATION.md:107` and `TROUBLESHOOTING.md:15` show mock `flowback doctor` output that differs from actual `FlowbackCLI/main.swift:158-219`. `SUPPORT.md:30` says the diagnostic exporter saves `.json`, whereas `DiagnosticReportExporter.swift:175` saves `.md`.
  5. **Repository hygiene:** A 1.0 MB `bmcbrand.zip` archive is committed to the repository root despite `*.zip` being in `.gitignore` (added before ignore or force-added), and `VisualParitySuites.swift:38-41` writes PNG files directly into the tracked `Docs/audits/screenshots/` directory during test execution rather than a temporary directory.
- **Concrete Failure Scenario:**
  A user follows `TROUBLESHOOTING.md` and runs `flowback hook antigravity --install` in their terminal; the command hangs indefinitely waiting for `stdin`. Another user edits `~/.flowback/config.json` by hand and wonders why Flowback ignores it.
- **Actual Impact:**
  Confusing developer/user experience when following troubleshooting or installation guides, and dirty working trees when running `VisualParitySuites` on systems with different font rendering.
- **Why Existing Safeguards/Tests Do Not Prevent It:**
  `verify_all.sh` validates Markdown relative file links, not CLI flag accuracy or JSON schema fidelity.
- **Recommended Remediation:**
  1. Support `--install` and `--uninstall` flags in `flowback hook <provider>` (or add `flowback install-hooks` / `flowback uninstall-hooks` in `FlowbackCLI/main.swift`) so the documented commands work!
  2. Parse `origin` and `timestamp` in `GenericHookPayload` (`GenericHookProvider.swift`).
  3. Update `Docs/CONFIGURATION.md`, `EVENT_PROTOCOL.md`, `ARCHITECTURE.md`, and `SUPPORT.md` to match the implementation.
  4. Remove tracked `bmcbrand.zip` from git tracking and write `VisualParitySuites` test renders to `NSTemporaryDirectory()` unless an explicit `UPDATE_SCREENSHOTS=1` env var is set.
- **Regression Test Required:**
  CLI argument parsing test for `flowback hook <provider> --install` / `--uninstall` and `GenericHookProvider` test for `origin` + `timestamp` decoding.
- **Blocks Release:** No (P2)

---

## E. Adapter & Provider Audit Matrix (Phase 5)

### 1. Agent Providers (`Sources/FlowbackProviders/`)

| Provider (`AgentProviderID`) | Declared Tier (`supportLevel`) | Detection Method (`checkHealth`) | Hook Install / Uninstall | Active Session Discovery (`discoverActiveSessions`) | Focus Capability & Resume Hint | Known Limitations & Audit Findings |
| :--- | :--- | :--- | :--- | :--- | :--- | :--- |
| **Google Antigravity** (`antigravity`) | `.nativeLifecycle` | Checks `/Applications/Antigravity IDE.app` or `~/.gemini/config` + `hooks.json` (`flowback-antigravity`) | Writes `PreInvocation`, `PostInvocation`, `Stop` to `~/.gemini/config/hooks.json` with backup | Scans `~/.gemini/antigravity-ide/brain/*/transcript.jsonl` (<20m mtime, `PLANNER_RESPONSE` / `fullyIdle`) | `.windowOnly` (resolves window ID via `CGWindowListCopyWindowInfo`) | **`FB-AUD-010`:** Hook `PATH` omits `/opt/homebrew/bin`. **`FB-AUD-001`:** Captures `windowID`, causing `.permissionDenied` if AX is untrusted. |
| **Antigravity CLI** (`antigravity-cli`, aliases `gemini-cli`, `gemini`, `agy`) | `.nativeLifecycle` | Checks `~/.gemini/antigravity-cli` or `agy`/`gemini` binary + `hooks.json` (`flowback-antigravity-cli`); caches `--version` via `AsyncProcessRunner` | Writes `flowback-antigravity-cli` block to `~/.gemini/config/hooks.json` with backup | Scans `~/.gemini/antigravity-cli/brain` transcripts + `presence/*.lock` + `conversation_summaries.db` | `.workspaceAndConversation`; resume hint: `agy --conversation <id>` | Solid implementation; `generateHookResponse` properly returns `{"injectSteps":[]}` for `PreInvocation`. Affected by `FB-AUD-001` when AX untrusted. |
| **Windsurf** (`windsurf`) | `.nativeLifecycle` | Checks `/Applications/Windsurf.app` or `~/.codeium/windsurf` + `hooks.json` (`flowback hook windsurf`) | Merges 9 Cascade lifecycle events into `~/.codeium/windsurf/hooks.json` with backup | Scans `~/.codeium/windsurf/transcripts/*.jsonl` (<20m mtime, 4KB tail read) | `.windowOnly` (resolves `com.codeium.windsurf` window) | Solid hook merging & trajectory deduplication. Affected by `FB-AUD-001` when AX untrusted. |
| **OpenCode** (`opencode`) | `.nativeLifecycle` | Checks `/Applications/OpenCode.app`, `/usr/local/bin/opencode`, or `~/.config/opencode` + `plugins/flowback.js` | Writes `flowback.js` plugin and cleans legacy `"flowback"` npm entry from `opencode.json` | Checks running `ai.opencode.app` / `com.opencode` processes | `.windowOnly` | **`FB-AUD-010`:** `discoverActiveSessions()` fabricates a running session with `Date()` whenever OpenCode app is open. **`FB-AUD-004`:** `session.idle` maps to `.agentWaiting`, which `FlowbackService` ignores. |
| **Cursor Background Agent** (`cursor-background`) | `.nativeLifecycle` (with key) / `.partial` (without key) | Checks `CURSOR_API_KEY` env or `~/.flowback/cursor_api_key` + `lastAuthError` | `uninstallIntegration` removes `~/.flowback/cursor_api_key` | Polls `https://api.cursor.com/v1/agents` (max 5 pages) with HTTP 429 `Retry-After` & 5xx backoff | `.externalURL` (`prUrl` or `https://cursor.com/agents/<id>`) | Well-tested HTTP pagination/backoff; note that cloud polling is an intentional outbound HTTPS call when configured (should be noted as an opt-in exception in `PRIVACY.md`). |
| **Claude Code** (`claude-code`) | `.adapter` | Checks if `~/.claude` and `~/.claude/settings.json` exist | **No-op** (only logs a message) | None (`[]`) | `.workspaceAndConversation`; resume hint: `claude resume <id>` | **`FB-AUD-010`:** `hookInstalled` is `true` if `~/.claude/settings.json` exists even without Flowback hooks; `installIntegration` is a no-op; does not check `/opt/homebrew/bin/claude`. |
| **GitHub Copilot** (`copilot`) | `.adapter` | Checks `~/.copilot` or `~/.config/github-copilot` | **No-op** | None (`[]`) | `.windowOnly`; resume hint: `cd "<ws>" && gh copilot` | **`ProviderHealth.isHealthy`** is always `false` because `hookInstalled` and `hookExecutable` default to `false` in `CopilotProvider.checkHealth()`. |
| **OpenAI Codex** (`codex`) | `.adapter` | **Hardcoded `isInstalled: false`** | **No-op** | None (`[]`) | `.windowOnly` | **`FB-AUD-010`:** `checkHealth()` hardcodes `isInstalled: false`, so Codex always shows `"Not Detected"`. |
| **Aider** (`aider`) | `.adapter` | **Hardcoded `isInstalled: false`** | **No-op** | None (`[]`) | `.windowOnly` | **`FB-AUD-010`:** `checkHealth()` hardcodes `isInstalled: false`, so Aider always shows `"Not Detected"`. |
| **Generic Hook** (`generic-hook`) | `.genericProtocol` | Always healthy (`isInstalled: true`, `hookInstalled: true`) | No-op | None (`[]`) | `.windowOnly` (or payload `focusCapability`) | **`FB-AUD-014`:** `GenericHookPayload` ignores `origin` and `timestamp` fields documented in `EVENT_PROTOCOL.md`. |

### 2. Application Adapters (`Sources/FlowbackFocus/Adapters/`)

| Adapter | Supported Bundle IDs | Restoration Hierarchy | Known Limitations & Audit Findings |
| :--- | :--- | :--- | :--- |
| **`WindsurfAdapter`** | `com.codeium.windsurf` | 1. `raiseWindow(windowID)` + activate → 2. `findWindow(matching: folderName)` + raise + activate → 3. `activateApplication` | Clean implementation. |
| **`VSCodeAdapter`** | `com.microsoft.VSCode`, `VSCodeInsiders`, `code.oss`, `com.google.antigravity-ide`, `com.google.antigravity`, `com.codeium.windsurf`, `com.vscodium`, `com.vscodium.codium`, `co.posit.positron`, `com.rstudio.positron`, `com.byteplus.trae` | 1. `raiseWindow(windowID)` + activate → 2. `findWindow(matching: folderName)` + raise + activate → 3. `activateApplication` | **`FB-AUD-009`:** Duplicates `com.codeium.windsurf`. |
| **`CursorAdapter`** | `com.todesktop.230313mzl4w4u92`, `co.anysphere.cursor`, `com.cursor.Cursor` | 1. `raiseWindow(windowID)` + activate → 2. `findWindow(matching: folderName)` + raise + activate → 3. `findWindow(matching: windowTitle)` + raise + activate → 4. `activateApplication` | Cleanest adapter implementation (includes `windowTitle` fallback at Priority 3). |
| **`TerminalAdapter`** | `com.apple.Terminal`, `com.googlecode.iterm2`, `com.mitchellh.ghostty`, `dev.warp.Warp-Stable`, `co.zeit.hyper`, `org.alacritty`, `net.kovidgoyal.kitty`, `com.github.wez.wezterm` | 1. `raiseWindow(windowID)` + activate → 2. `findWindow(matching: dirName)` + raise + activate → 3. `activateApplication` | Window-level only (does not select internal terminal tabs/panes via AppleScript/CLI). |
| **`BraveAdapter`** | `com.brave.Browser`, `com.google.Chrome`, `company.thebrowser.Browser`, `com.apple.Safari`, `org.mozilla.firefox` | 1. If `workspacePath` is HTTP/HTTPS URL, `NSWorkspace.shared.open(url)` → 2. `raiseWindow(windowID)` → 3. `activateApplication` | **`FB-AUD-009`:** Calls `NSWorkspace.shared.open` directly instead of injected opener; omits `com.brave.Browser.beta` and `com.microsoft.edgemac`. |
| **`GenericApplicationAdapter`** | `*` (Fallback for all other bundle IDs) | 1. `activateApplication(app)` → 2. `_ = raiseWindow(windowID)` | **`FB-AUD-009`:** Activates before raising window; lacks workspace/title fallback when `windowID` is nil or stale. |

---

## F. Subsystem Scorecard (Phase 18.D)

| Subsystem | Score | Supporting Evidence |
| :--- | :--- | :--- |
| **Architecture** | **Adequate** | Clean acyclic 11-target SPM graph and provider-neutral core, but weakened by split-brain state duplication between `FlowbackService`, `IPCHandler`, and `DashboardViewModel` (`FB-AUD-003`) and unused `LifecycleCoordinator` component registration (`FB-AUD-012`). |
| **Correctness** | **Needs improvement** | Core FSM (`AgentStateMachine`) and restoration outcome enums (`RestorationOutcome`) are well-modeled, but `completionBehavior`/`permissionBehavior`/`failureBehavior` are unimplemented dead fields (`FB-AUD-004`), `.agentWaiting` is ignored by `FlowbackService` (`FB-AUD-004`), and CLI `focus-lock` / `ApplicationsView` edits fail to sync (`FB-AUD-003`). |
| **Concurrency** | **Adequate** | `TimeoutCoordinator` and `FocusController` generation tokens (`F-24`, `F-26`), `UIEventCoalescer` (`F-15`), and `AsyncProcessRunner` (`F-14`) are well-engineered, but `SQLiteDatabase.runInTransaction` has an actor reentrancy hazard across `await block()` (`FB-AUD-005`) and `IPCHandler` is `@unchecked Sendable` with unprotected mutable `focusLock` (`FB-AUD-003`). |
| **macOS Integration** | **Needs improvement** | Cooperative activation handoff (`yieldActivation`), `unhide()`, `IsSecureEventInputEnabled()`, `CGEventSource` idle sensing, and `AXUIElementSetMessagingTimeout` are strong, but `FocusController.restoreSession` hard-fails with `.permissionDenied` when `origin.windowIdentifier != nil` and Accessibility is untrusted (`FB-AUD-001`). |
| **Adapters & Providers** | **Adequate** | Antigravity, Antigravity CLI, Windsurf, and Cursor Background providers are thorough, but Codex and Aider hardcode `isInstalled: false`, Claude Code `installIntegration` is a no-op, OpenCode fabricates active sessions when idle (`FB-AUD-010`), and `GenericApplicationAdapter` lacks title/workspace fallback (`FB-AUD-009`). |
| **Security & Privacy** | **Adequate** | Unix socket `0700`/`0600` permissions, `getpeereid()`, 2 MB payload cap, URL scheme validation (`http`/`https` only), and `DiagnosticReportExporter` path/secret scrubbing are strong. `AgentEvent.init(from:)` and `AgentSession.init` need `SecretSanitizer` calls (`FB-AUD-006`). |
| **Process Management & IPC** | **Adequate** | `AsyncProcessRunner` drains pipes continuously into bounded 1 MB buffers and cancels watchdog tasks (`F-14`), and `IPCClient` sets socket timeouts (`F-17`). Needs `SIGKILL` escalation on timeout (`FB-AUD-007`) and async execution in `AdvancedViewModel`/`SupportView` (`FB-AUD-008`). |
| **UI, UX & Accessibility** | **Adequate** | Cohesive card design system (`FlowbackCard`, `ThemeTokens`), WCAG AA contrast ratios, SF Symbol non-color status badges, frozen menu bar slots, and standard AppKit responder menus (`⌘W`, `⌘Q`, `⌘1`–`⌘0`). Impaired by broken AppleScript in `SupportView` (`FB-AUD-008`), unsaved `ApplicationsView` changes (`FB-AUD-003`), and uncleared `AttentionArbiter` queue items (`FB-AUD-012`). |
| **Performance** | **Strong** | Hot event path (`handleAgentEvent` → `uiCoalescer.schedule()`) is $O(1)$ in-memory with zero filesystem/subprocess scans; completed sessions capped at 100 in memory; timeline capped at 50 entries/session across 100 sessions; CLI `--version` probes cached by `mtime`; DB pruning throttled to hourly. |
| **Tests & QA** | **Needs improvement** | Broad test inventory across 36+ suites, but `FlowbackTestRunner` prematurely exits with code `0` inside `V-008` (`MenuBarController.setup()`) in headless environments—masking 9 failed assertions and skipping ~400 trailing assertions (`FB-AUD-002`), and `FocusController` tests depend on host TCC Accessibility trust (`FB-AUD-001`). |
| **CLI & Developer Experience** | **Adequate** | Clean offline `flowback doctor` fallback and comprehensive subcommands, but `flowback focus-lock` and `flowback config import` do not sync with `FlowbackService` (`FB-AUD-003`), and documented `flowback hook antigravity --install/--uninstall` flags do not exist (`FB-AUD-014`). |
| **Packaging & Distribution** | **Needs improvement** | Inside-out signing scripts (`package_app.sh`, `sign_and_notarize.sh`, `package_release_artifacts.sh`, `validate_release.sh`) and CI workflows (`ci.yml`, `release.yml`) are well-structured, but `dist/` still holds `0.4.0` artifacts, `Website/release-manifest.json` reused `0.4.0` SHA-256 hashes for `0.4.1`, `Formula/flowback-cli.rb` has an all-zero SHA-256 (`FB-AUD-011`), and public distribution is blocked on Developer ID signing + notarization. |
| **Documentation** | **Adequate** | Extensive documentation suite with valid internal relative links, but material drift exists around `flowback hook --install`, `~/.flowback/config.json`, `EVENT_PROTOCOL.md` `origin` parsing, and deduplication window timings (`FB-AUD-014`). |
| **Maintainability** | **Strong** | Zero external package dependencies, clean Swift 6 concurrency typing, 0 SwiftLint violations across all 114 Swift files in `--strict` mode. |

---

## G. Test & Command Execution Results (Phase 11 & Phase 18.E)

Every command below was inspected and executed against `/Users/abin/workspace/projects/flowback` without modifying production code:

| Command | Ran? | Exit Code | Output & Assertion Summary | Interpretation & Environment Limitations |
| :--- | :---: | :---: | :--- | :--- |
| `DYLD_FRAMEWORK_PATH="/Library/Developer/CommandLineTools/usr/lib" swiftlint lint --strict --no-cache` | Yes | `0` | `Done linting! Found 0 violations, 0 serious in 114 files.` | **PASS:** All 114 Swift source and test files pass strict SwiftLint rules with zero warnings or errors. |
| `swift build --disable-sandbox` | Yes | `0` | `Build complete! (22.07 secs)` | **PASS:** All 11 package targets compile cleanly in Debug mode with Swift 6.4. (`--disable-sandbox` required because nested `sandbox-exec` is disallowed inside the audit runner). |
| `swift build -c release --disable-sandbox` | Yes | `0` | `Build complete! (16.68 secs)` | **PASS:** All targets (`Flowback`, `flowback-cli`, `FlowbackTestRunner`) compile cleanly in optimized Release mode. |
| `./.build/debug/FlowbackTestRunner` | Yes | `0` *(Premature exit)* | `Passed printed: 627, Failed printed: 9, Reached summary: False`. Stopped inside `[TEST SUITE] V-008: Menu Bar Controller Autosave Configuration`. | **FAILED (Masked by `FB-AUD-002`):** 7 assertions failed due to `FB-AUD-001` (host `AXIsProcessTrusted() == false`), 2 suites failed with `Operation not permitted` on ` UnixSocketServer.start()` due to runner sandbox blocking `listen()`, and `V-008` (`MenuBarController.setup()`) caused AppKit to exit with code `0` before the remaining ~400 assertions or the failure exit gate could run. |
| `bash Scripts/validate_version_sync.sh` | Yes | `0` | `ALL VERSION SYNCHRONIZATION CHECKS PASSED: v0.4.1 (Build 2)` | **PASS (with gap `FB-AUD-011`):** Version strings match `0.4.1` (build `2`), though script does not check `Formula/flowback-cli.rb`'s all-zero `sha256` or `dist/` staleness. |
| `bash Scripts/validate_release.sh --local` | Yes | `1` | Passed Checks 1–6 & 8; **Failed Checks 7, 9, 10** (`Distribution ZIP missing`, `Manifest version mismatch: expected '0.4.1', got '0.4.0'`, `Cask SHA-256 mismatch`). | **FAILED (`FB-AUD-011`):** `dist/Flowback.app` is `0.4.1`, but `dist/*.zip`, `dist/*.dmg`, and `dist/release-manifest.json` are still from `0.4.0`. |
| `bash Scripts/test_website.sh` | Yes | `0` | `9 HTML pages found, 10 assets verified, release-manifest.json schema v1 valid, 244 internal link references verified.` | **PASS:** Static website files and internal links are valid. |
| `node Scripts/test_opencode_plugin.js` | Yes | `1` (`EPERM`) | Passed test 1 (`Plugin exports id and name metadata`), then failed at `server.listen(socketPath)` with `Error: listen EPERM: operation not permitted`. | **BLOCKED by sandbox:** Node.js `net.Server.listen` on Unix domain sockets is blocked by the runner's macOS sandbox (`RequiresNetworkAccess: false`). |
| `bash Scripts/test_live_macos.sh` (and direct binary steps) | Yes | `1` (script) / `0` (binaries) | Script failed at `swift build -c release` (missing `--disable-sandbox`); running its steps directly against `.build/release/Flowback` (`--help`, `--version`) and `.build/release/flowback-cli` (`--version`, `doctor`) exited `0`. Step 3 (`osascript -l JavaScript -e '$.AXIsProcessTrusted()'`) threw `TypeError: $.AXIsProcessTrusted is not a function (-2700)`. | **PARTIAL (`FB-AUD-013`):** Standalone binaries run cleanly without bundle crashes; JXA snippet in `test_live_macos.sh` is missing `ObjC.import('ApplicationServices')`. |
| Markdown Link Check (root & `Docs/`) | Yes | `0` | `Verified 20 root markdown documents` and all `Docs/` markdown files with 0 broken local file links. | **PASS:** All relative Markdown links resolve to existing files. |
| `git_diff` / `git_status` (via MCP) | Yes | `0` | `Working tree clean. No changes.` / `No differences found.` | **PASS:** Clean baseline verified before report creation. |

---

## H. Coverage & Confidence Gaps (Phase 18.F)

The following behaviors could not be verified headlessly in this environment and require targeted interactive or external verification:

1. **Interactive WindowServer & Accessibility Raising (`AXUIElementPerformAction(..., kAXRaiseAction)`):**
   - *Why unverified:* Host runner executes without TCC Accessibility permission (`AXIsProcessTrusted() == false`) and without an interactive multi-window desktop session across macOS Spaces and Fullscreen apps.
   - *How to verify:* Launch packaged `/Applications/Flowback.app` in an interactive macOS session, grant Accessibility permission in **System Settings → Privacy & Security → Accessibility**, open two VS Code workspace windows and a Terminal window across two Spaces, trigger `flowback emit` / agent completions while idle vs. actively typing vs. in Secure Input (`sudo` prompt in Terminal), and verify window raising and Space policies.
2. **Headless-Unblocked `FlowbackTestRunner` & `test_opencode_plugin.js` Socket Bindings:**
   - *Why unverified:* Runner sandbox blocks `bind()`/`listen()` on Unix domain sockets (`EPERM`) and terminates `NSStatusBar.system.statusItem` in `V-008`.
   - *How to verify:* Fix `FB-AUD-001` and `FB-AUD-002`, then run `swift run FlowbackTestRunner` and `node Scripts/test_opencode_plugin.js` in a standard local terminal session outside the agent sandbox.
3. **Full `swift test` (`XCTest`) Execution:**
   - *Why unverified:* Host only has `/Library/Developer/CommandLineTools` installed (`XCTest.framework` requires full `Xcode.app`).
   - *How to verify:* Run `ENABLE_XCTEST=1 swift test --parallel` on a Mac or GitHub Actions runner (`macos-15`) with full Xcode installed.
4. **Live Third-Party Agent End-to-End Hooks:**
   - *Why unverified:* Only `agy` (`/opt/homebrew/bin/agy`) is installed on the host (`claude` and `opencode` CLIs are not installed; no live `CURSOR_API_KEY` is present).
   - *How to verify:* Install hooks in a live environment with Antigravity IDE, `agy`, Windsurf Cascade, OpenCode, and Claude Code, and verify real turn completions.
5. **Apple Developer ID Code Signing, Notarization, Stapling & Clean-Mac Gatekeeper Assessment:**
   - *Why unverified:* Requires Apple Developer ID Application certificate and Apple Notary Service credentials (`APPLE_CERTIFICATE`, `APPLE_ID`, `APPLE_TEAM_ID`).
   - *How to verify:* Run `STRICT_SIGNING=1 STRICT_NOTARIZATION=1 bash Scripts/sign_and_notarize.sh` and `bash Scripts/validate_release.sh --release 0.4.1`, then test mounting the DMG and launching `Flowback.app` on a clean Mac with Gatekeeper enabled.

---

## I. Independent Product Acceptance Assessment (Phase 17)

| # | Product Acceptance Question | Classification | Supporting Evidence |
| :---: | :--- | :---: | :--- |
| **1** | **Does it reliably detect relevant agent/editor/browser activity?** | **Partially Verified** | Verified for Antigravity IDE, Antigravity CLI (`agy`), Windsurf, OpenCode plugin, Cursor Cloud API (via mock transport), and Generic Hook. However, Codex and Aider hardcode `isInstalled: false`, Claude Code hook installer is a no-op, and OpenCode process discovery fabricates active sessions whenever the app is open (`FB-AUD-010`). |
| **2** | **Does it restore focus to the intended application?** | **Failed (When AX Untrusted) / Partially Verified (When AX Trusted)** | When Accessibility is granted, `WindowController` and adapters accurately match window IDs, bounds, and workspace titles. When Accessibility is **not** granted, `FocusController.restoreSession` hard-fails with `.permissionDenied` whenever `origin.windowIdentifier != nil` (`FB-AUD-001`), failing to activate the application. |
| **3** | **Does it avoid stealing focus from unrelated applications?** | **Partially Verified** | `UserIntentEngine` properly suppresses focus switches during active user typing (<5s idle), Secure Event Input (`IsSecureEventInputEnabled`), protected apps (Zoom, Keynote, Teams, FaceTime), fullscreen mode, and inactive user sessions. **However**, enabling Focus Lock via CLI (`flowback focus-lock`) or disabling it in `OverviewView`, or adding protected apps in `ApplicationsView`, fails to sync to `FlowbackService` (`FB-AUD-003`), and setting `completionBehavior = .notificationOnly` in `AdvancedView` is ignored (`FB-AUD-004`). |
| **4** | **Does it recover safely from cancellation, timeouts, process exits, and unavailable permissions?** | **Partially Verified** | `TimeoutCoordinator`, monotonic generation tokens in `FocusController`, `AsyncProcessRunner`, and dead-PID checks in `UserIntentEngine` work well. However, unavailable Accessibility permission causes `.permissionDenied` instead of app-level fallback (`FB-AUD-001`), and `AsyncProcessRunner` lacks `SIGKILL` escalation for `SIGTERM`-ignoring processes (`FB-AUD-007`). |
| **5** | **Are supported integrations genuinely functional, or only partially implemented?** | **Partially Verified** | Antigravity, Antigravity CLI, Windsurf, OpenCode (plugin), Cursor Background, and Generic Hook are genuinely functional. Codex, Aider, Claude Code (installer/health), and Copilot (`isHealthy` always false) are only partially implemented (`FB-AUD-010`). |
| **6** | **Does the CLI behave predictably when run independently?** | **Partially Verified** | Read-only CLI commands (`status`, `agents`, `sessions`, `doctor` online/offline, `config export`, `--version`, `--help`) behave predictably. Mutating commands (`focus-lock`, `config import`) do not synchronize with `FlowbackService`'s in-memory state (`FB-AUD-003`), and documented `flowback hook <provider> --install/--uninstall` flags hang waiting for stdin (`FB-AUD-014`). |
| **7** | **Does the packaged app behave differently from development execution?** | **Verified** | Properly handled via `PermissionManager.isAppBundle` (`Bundle.main.bundleIdentifier != nil`) and `FlowbackVersion.current` (`CFBundleShortVersionString` fallback), preventing `UNUserNotificationCenter` and `SMAppService` crashes in standalone/CLI mode. |
| **8** | **Are failures understandable and recoverable by a normal user?** | **Partially Verified** | Storage degradation banners, `RestorationOutcome` messages, and `DiagnosticsView` deep-links are clear, but `SupportView`'s `"Run 'flowback doctor' in Terminal"` button silently fails due to an AppleScript syntax error (`FB-AUD-008`), and `Attention Required` items remain stuck after focus restoration (`FB-AUD-012`). |
| **9** | **Is the application ready for private development use?** | **Partially Verified (Ready with known workarounds)** | Usable for local development once Accessibility is granted and settings are configured via the `Settings` tab and menu bar (avoiding CLI `focus-lock` and `ApplicationsView` until `FB-AUD-001`/`FB-AUD-003` are fixed). |
| **10** | **Is it ready for broader beta testing?** | **Failed (`NOT READY`)** | Blocked by P0 correctness defects (`FB-AUD-001` through `FB-AUD-005`) and stale `v0.4.0` distribution artifacts/checksums (`FB-AUD-011`). |
| **11** | **Is it ready for public distribution?** | **Failed (`NOT READY`)** | Blocked by P0 defects (`FB-AUD-001`–`FB-AUD-005`), distribution artifact/hash mismatches (`FB-AUD-011`), and absence of Developer ID code signing and Apple notarization. |

---

## J. Prioritized Remediation Roadmap (Phase 18.G)

### P0 — Immediate Release Blockers (Must Fix Before Any Beta or Release)

| Action ID | Finding(s) | Target Files | Remediation Summary | Validation Requirement | Independent? |
| :--- | :--- | :--- | :--- | :--- | :---: |
| **REM-P0-1** | `FB-AUD-001` | `Sources/FlowbackFocus/FocusController.swift`, `Sources/FlowbackTestRunner/main.swift`, `ConversationAwarenessSuites.swift`, `AuditRemediationSuites.swift`, `Tests/FlowbackIntegrationTests/AcceptanceScenariosTests.swift` | When `origin.windowIdentifier != nil && !permissionChecker()`, fall back to application-level activation via `appController.activateApplication(app)` returning `.windowActivatedOnly` (or only return `.permissionDenied` if app activation fails / strict window raising is requested). Inject `permissionChecker: { true }` into mock unit/acceptance test fixtures while preserving explicit permission-denial unit tests. | All focus restoration suites in `FlowbackTestRunner` pass regardless of host `AXIsProcessTrusted()` state; dedicated test verifies app-level fallback when `permissionChecker` returns `false`. | Yes |
| **REM-P0-2** | `FB-AUD-002` | `Sources/FlowbackTestRunner/VorssaintDiscoverySuites.swift`, `Sources/FlowbackUI/MenuBar/MenuBarController.swift`, `Scripts/verify_all.sh` | Guard `NSStatusBar.system.statusItem` creation in headless environments where WindowServer is unavailable (or inspect `MenuBarController` configuration without triggering WindowServer `_exit(0)`), and update `Scripts/verify_all.sh` to assert `ALL VERIFICATION SUITES PASSED!` is present in `FlowbackTestRunner` output. | `./.build/debug/FlowbackTestRunner` executes all 36+ suites to completion, prints `TEST RESULTS SUMMARY`, and returns non-zero exit code on any failure. | Yes |
| **REM-P0-3** | `FB-AUD-003` | `Sources/FlowbackApp/FlowbackService.swift`, `Sources/FlowbackServer/IPCHandler.swift`, `Sources/FlowbackUI/Dashboard/DashboardView.swift`, `Sources/FlowbackUI/Views/OverviewView.swift`, `Sources/FlowbackUI/Views/ApplicationsView.swift`, `Sources/FlowbackFocus/AttentionArbiter.swift` | Unify `focusLock` and `configuration` ownership in `FlowbackService`: wire bidirectional callbacks/actor methods between `IPCHandler`, `FlowbackService`, `OverviewView` (Disable Lock button), and `ApplicationsView` (`.onChange` -> `onSaveConfig`); update `AttentionArbiter` timings when `configuration` changes; make `IPCHandler` an `actor` or lock-protected. | End-to-end tests proving CLI `focus-lock`, Overview Disable Lock button, `ApplicationsView` edits, and CLI `config-import` immediately update `FlowbackService` and `AttentionArbiter`. | Yes |
| **REM-P0-4** | `FB-AUD-004` | `Sources/FlowbackFocus/UserIntentEngine.swift`, `Sources/FlowbackApp/FlowbackService.swift` | Enforce `config.completionBehavior`, `config.permissionBehavior`, and `config.failureBehavior` inside `UserIntentEngine.evaluate(...)`, and update `FlowbackService.handleAgentEvent` to check `if event.type.isActionableForAttention` (handling `.agentWaiting` and `.agentIdle`). | Unit and integration tests verifying each behavior enum (`.notificationOnly`, `.askUser`, `.focusAgent`, `.restoreOrigin`) and `.agentWaiting` attention routing. | Depends on `REM-P0-3` (touches `FlowbackService`) |
| **REM-P0-5** | `FB-AUD-005` | `Sources/FlowbackStorage/SQLiteDatabase.swift`, `Sources/FlowbackStorage/Migrations.swift` | Replace async `runInTransaction` suspension across `await block()` with a synchronous transaction body inside the `SQLiteDatabase` actor (or serialize transactions with an async mutex so interleaved actor calls cannot enter an open transaction). | Concurrent stress test running parallel `runInTransaction` and `saveSession` calls on a single `SQLiteDatabase` actor with 0 SQLite errors. | Yes |

### P1 — Required Before Public Release

| Action ID | Finding(s) | Target Files | Remediation Summary | Validation Requirement | Independent? |
| :--- | :--- | :--- | :--- | :--- | :---: |
| **REM-P1-1** | `FB-AUD-006` | `Sources/FlowbackCore/Events/AgentEvent.swift`, `Sources/FlowbackCore/Domain/AgentSession.swift`, `Sources/FlowbackCore/Sessions/TimelineTracker.swift` | Invoke `SecretSanitizer.sanitizeMetadata` and `SecretSanitizer.sanitizeText` in `AgentEvent.init(from:)`, `AgentSession.init`, `AgentSession.init(from:)`, and on `summary` in `TimelineTracker.record(...)`. | Unit tests verifying secret redaction across JSON-decoded `AgentEvent`s, directly initialized `AgentSession`s, and timeline summaries. | Yes |
| **REM-P1-2** | `FB-AUD-007`, `FB-AUD-008` | `Sources/FlowbackCore/Services/AsyncProcessRunner.swift`, `Sources/FlowbackUI/Views/AdvancedView.swift`, `Sources/FlowbackUI/Views/SupportView.swift` | Add `SIGKILL` escalation after `process.terminate()` in `AsyncProcessRunner`; refactor `AdvancedViewModel.resetSystemPermissions` to use `AsyncProcessRunner`; fix the multi-line AppleScript syntax in `SupportView` and run it asynchronously. | Test `AsyncProcessRunner` against a `SIGTERM`-ignoring script; test `NSAppleScript.compileAndReturnError` on the `SupportView` script. | Yes |
| **REM-P1-3** | `FB-AUD-009`, `FB-AUD-010` | `Sources/FlowbackFocus/Adapters/*`, `Sources/FlowbackProviders/*` | Add workspace/title fallback and raise-before-activate ordering to `GenericApplicationAdapter`; remove duplicate `com.codeium.windsurf` from `VSCodeAdapter`; add `com.brave.Browser.beta` and `com.microsoft.edgemac` to `BraveAdapter`; implement real binary/config health checks in `CodexProvider`, `AiderProvider`, and `ClaudeCodeProvider`; add `/opt/homebrew/bin` to `AntigravityProvider` hook `PATH`; stop fabricating running sessions for idle `OpenCode.app` windows. | Adapter and provider unit tests covering health detection, hook `PATH`, and generic window fallback. | Yes |
| **REM-P1-4** | `FB-AUD-011` | `dist/*`, `Website/release-manifest.json`, `Casks/flowback.rb`, `Formula/flowback-cli.rb`, `Scripts/validate_version_sync.sh`, `Scripts/publish_milestone_releases.sh` | Rebuild `v0.4.1` release artifacts (`package_release_artifacts.sh 0.4.1 universal 2`), compute real SHA-256 hashes for `Website/release-manifest.json`, `Casks/flowback.rb`, and `Formula/flowback-cli.rb`, add non-zero SHA-256 validation to `validate_version_sync.sh`, update `publish_milestone_releases.sh` to `v0.4.1`, and sign/notarize with Apple Developer ID credentials. | `bash Scripts/validate_version_sync.sh` and `bash Scripts/validate_release.sh --local 0.4.1` (and `--release 0.4.1` when signed) pass 100%. | Run after P0/P1 code fixes |
| **REM-P1-5** | `FB-AUD-012` | `Sources/FlowbackApp/FlowbackService.swift`, `Sources/FlowbackFocus/FocusController.swift`, `Sources/FlowbackUI/Views/OverviewView.swift` | Remove sessions from `AttentionArbiter` once focus restoration succeeds (automatic or manual) or when a session starts a new turn; update `OverviewView` attention list to resolve sessions from `allSessions` and provide a Dismiss button. | Test verifying `attentionArbiter.pendingRequests()` is empty after successful session focus restoration. | Depends on `REM-P0-3` |

### P2 — Important Follow-Up Improvements

| Action ID | Finding(s) | Target Files | Remediation Summary | Validation Requirement | Independent? |
| :--- | :--- | :--- | :--- | :--- | :---: |
| **REM-P2-1** | `FB-AUD-013`, `FB-AUD-014` | `Sources/FlowbackCLI/main.swift`, `Sources/FlowbackProviders/GenericHook/GenericHookProvider.swift`, `Scripts/test_live_macos.sh`, `Scripts/uninstall.sh`, `Docs/*.md`, `*.md` | Implement `--install` / `--uninstall` in `flowback hook <provider>`; parse `origin` and `timestamp` in `GenericHookPayload`; fix `ObjC.import("ApplicationServices")` in `test_live_macos.sh`; update `uninstall.sh` to clean all provider hooks; harmonize documentation (`CONFIGURATION.md`, `EVENT_PROTOCOL.md`, `ARCHITECTURE.md`, `SUPPORT.md`). | CLI hook `--install`/`--uninstall` tests, `GenericHookProvider` origin/timestamp tests, and `test_live_macos.sh` execution. | Yes |

### P3 — Optional Polish & Long-Term Hygiene

| Action ID | Finding(s) | Target Files | Remediation Summary | Validation Requirement | Independent? |
| :--- | :--- | :--- | :--- | :--- | :---: |
| **REM-P3-1** | `FB-AUD-012`, `FB-AUD-014` | `bmcbrand.zip`, `Sources/FlowbackTestRunner/VisualParitySuites.swift`, `Sources/FlowbackApp/FlowbackService.swift` | Remove `bmcbrand.zip` from Git tracking; write `VisualParitySuites` renders to `NSTemporaryDirectory()` unless `UPDATE_SCREENSHOTS=1` is set; either wrap `FlowbackService` subsystems in `LifecycleManagedComponent` conformances or simplify `LifecycleCoordinator`. | `git status` remains clean after running `VisualParitySuites` regardless of host display profile. | Yes |

---

## K. Release Verdict (Phase 18.H)

### Verdict: **`NOT READY`**

**Justification:**
1. **Confirmed High-Severity Behavioral & Reliability Defects (`FB-AUD-001` – `FB-AUD-005`):**
   - Users running without Accessibility permission experience hard `.permissionDenied` failures instead of documented application-level fallback whenever `origin.windowIdentifier` was captured (`FB-AUD-001`).
   - `FlowbackTestRunner` exits prematurely with code `0` inside `V-008` in headless environments, masking test failures and skipping ~400 assertions (`FB-AUD-002`).
   - CLI `flowback focus-lock`, Overview's Focus Lock "Disable" button, `ApplicationsView` protected-app edits, and CLI `flowback config import` fail to synchronize with `FlowbackService`'s live orchestration state (`FB-AUD-003`).
   - `completionBehavior`, `permissionBehavior`, and `failureBehavior` in Advanced Preferences are unimplemented dead fields, and `.agentWaiting`/`.agentIdle` events do not trigger attention arbitration (`FB-AUD-004`).
   - `SQLiteDatabase.runInTransaction` is vulnerable to Swift actor reentrancy across `await block()` (`FB-AUD-005`).
2. **Release Artifact & Distribution Blockers (`FB-AUD-011`):**
   - `bash Scripts/validate_release.sh --local` currently fails (3 failed checks) because `dist/` contains stale `0.4.0` archives, `Website/release-manifest.json` and `Casks/flowback.rb` reuse `0.4.0` SHA-256 hashes under `0.4.1` filenames, `Formula/flowback-cli.rb` has an all-zero `sha256` placeholder, and `Flowback.app` is ad-hoc signed without Apple Developer ID signing or notarization.

**Recommended Next Step:**
Authorize implementation of **P0 remediations (`REM-P0-1` through `REM-P0-5`)** and **P1 remediations (`REM-P1-1` through `REM-P1-5`)**, re-run the full verification and packaging suite (`FlowbackTestRunner` and `validate_release.sh`), and then proceed to controlled beta or Developer ID signing and notarization.
