# Contributing to Flowback

Thank you for your interest in improving Flowback! We welcome contributions ranging from bug fixes and documentation polish to new agent providers and editor adapters.

Please read this document before opening a pull request or submitting substantial changes.

---

## Code of Conduct

All contributors and maintainers are expected to follow our [Code of Conduct](CODE_OF_CONDUCT.md). Please report any unacceptable behavior to our private security/governance reporting channel.

---

## Prerequisites & Development Environment

* **macOS:** 14.0 (Sonoma) or newer on Apple Silicon or Intel.
* **Swift:** 6.0 or newer.
* **Developer Tools:** Apple Command Line Tools (`xcode-select --install`) or Xcode 16+.
* **Git:** 2.30+.

---

## Repository Setup & Local Build

```bash
# 1. Clone repository
git clone https://github.com/rapheljr/flowback.git
cd flowback

# 2. Build local debug binaries
swift build

# 3. Run full verification test suite (61 tests)
swift run FlowbackTestRunner
```

---

## Testing & Quality Assurance

Flowback enforces strict deterministic testing. Any pull request introducing logic or bug fixes must include corresponding test assertions.

### Verification Test Runner
Run all verification suites (State Machine, Deduplication, Policy Hierarchy, SQLite WAL, Antigravity Hooks, Acceptance Scenarios A–J, and Robustness Audits):

```bash
swift run FlowbackTestRunner
```

### Make Targets
A convenient `Makefile` is provided in the repository root:
* `make build` — Compiles debug targets.
* `make release` — Compiles optimized release targets.
* `make test` — Executes the test suite.
* `make package` — Packages `Flowback.app`.
* `make dmg` — Creates the distributable `Flowback.dmg`.
* `make lint` — Validates Swift code formatting and linting rules.
* `make clean` — Cleans build directories and temporary test databases.

---

## Architecture & Code Organization

Before modifying code, familiarize yourself with [ARCHITECTURE.md](ARCHITECTURE.md):

* **`FlowbackCore/`**: Core domain entities (`AgentSession`, `OriginContext`, `AttentionRequest`), finite state machine (`AgentStateMachine`), sliding-window deduplicator, and event bus.
* **`FlowbackFocus/`**: User intent detection (`UserIntentEngine`), priority arbitration (`AttentionArbiter`), window raising (`FocusController`), and application adapters (`VSCodeAdapter`, `CursorAdapter`, `TerminalAdapter`, `BraveAdapter`).
* **`FlowbackProviders/`**: Agent lifecycle translators (`AntigravityProvider`, `ClaudeCodeProvider`, `CodexProvider`, `GenericHookProvider`).
* **`FlowbackStorage/`**: Local SQLite engine with WAL mode, migrations (`Migrations.swift`), session repository, and recovery logic.
* **`FlowbackServer/`**: Unix domain socket server (`~/.flowback/flowback.sock`) and IPC dispatcher.
* **`FlowbackNotifications/`**: macOS UserNotifications integration.
* **`FlowbackUI/`**: AppKit status bar menu item and SwiftUI Dashboard views.
* **`FlowbackCLI/`**: `flowback` CLI command suite.
* **`FlowbackTestHarness/`**: Mock window controllers, idle trackers, and simulated agent fixtures.

### Key Architectural Invariants
1. **Providers NEVER Steal Focus Directly:** Providers translate agent hooks into normalized `AgentEvent`s dispatched over `EventBus`. Only `FocusController` invokes AppKit/Accessibility window operations after `PolicyEngine` and `AttentionArbiter` approvals.
2. **Local-First & Privacy First:** Zero telemetry, zero outbound networking, zero secret or code extraction.
3. **Graceful Degradation:** If macOS Accessibility permissions are absent, fall back to application-level activation without throwing uncaught exceptions.

---

## Branch & Commit Conventions

### Conventional Commits
We follow the [Conventional Commits](https://www.conventionalcommits.org/) specification:

```text
feat(provider): add Windsurf proactive agent tracking
fix(focus): prevent focus restore when user is typing in Slack
docs(install): clarify Accessibility permissions on macOS Sonoma
test(storage): add multi-threaded SQLite transaction rollback test
refactor(server): optimize IPC chunk streaming
```

Common scopes: `core`, `focus`, `provider`, `storage`, `server`, `ui`, `cli`, `docs`, `ci`.

---

## Proposing Substantial Changes

For significant architectural changes, new providers requiring filesystem watchers, or breaking protocol alterations:
1. Open an issue with the `proposal` or `feature-request` template first.
2. Discuss the problem statement, alternatives, privacy implications, and macOS permission requirements before submitting code.
3. This saves your time and ensures alignment with project goals.

---

## Pull Request Checklist

When submitting a pull request, ensure:

- [ ] All changes are focused and directly relevant to the issue.
- [ ] No unrelated refactoring or whitespace reformatting is included.
- [ ] New code includes corresponding unit or integration test assertions in `FlowbackTestRunner` or `Tests/`.
- [ ] Verification suite passes 100%: `swift run FlowbackTestRunner`.
- [ ] Code follows Swift 6 concurrency rules (no data races or unsafe actor boundaries).
- [ ] Documentation (in `README.md`, `Docs/`, or `Website/`) is updated if user-facing behavior changed.
- [ ] Zero secrets, personal file paths, tokens, or private test data are introduced.
- [ ] macOS permission and privacy implications have been reviewed.
- [ ] Platform limitations (e.g. macOS Spaces behavior) are clearly documented.

---

## Adding a New Agent Provider

To add support for a new coding agent:
1. Implement the `AgentProvider` protocol in `Sources/FlowbackProviders/`.
2. Map agent-specific lifecycle hooks or CLI output into normalized `AgentEvent` states:
   * `agentStarted`
   * `agentWaiting`
   * `agentPermissionRequired`
   * `agentCompleted`
   * `agentFailed`
   * `agentCancelled`
3. Add provider health diagnostics and automatic hook detection.
4. Add comprehensive unit tests in `Tests/FlowbackProviderTests/` and include simulation scenarios in `FlowbackTestRunner`.
5. Update `PROVIDERS.md` and `README.md` feature matrix.

---

## Adding an Application Adapter

To add support for an IDE, text editor, or terminal:
1. Implement `ApplicationAdapter` in `Sources/FlowbackFocus/Adapters/`.
2. Register the application's bundle identifiers (e.g., `com.example.editor`).
3. Implement `findWindow(for:context:)` using window title pattern matching or AppleScript dictionary discovery.
4. Verify graceful degradation when Accessibility permission is denied.
5. Add test coverage in `FlowbackTestRunner`.
