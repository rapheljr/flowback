# Flowback Development Guide

This guide covers building, testing, and contributing to Flowback.

---

## Toolchain & Requirements

* **macOS:** 14.0+ (Apple Silicon or Intel)
* **Swift:** 6.0+
* **Compiler:** Apple Command Line Tools or Xcode 16+

---

## Directory Structure

```text
focus-switcher/
├── Package.swift                    # Swift Package definition
├── Scripts/
│   ├── build.sh                     # Compiles release binaries
│   ├── package_app.sh               # Assembles and codesigns Flowback.app
│   ├── create_dmg.sh                # Generates compressed DMG installer
│   └── install_cli.sh               # Installs flowback CLI to PATH
├── Sources/
│   ├── FlowbackCore/                # Domain models, state machine, event bus, policies
│   ├── FlowbackStorage/             # SQLite engine, migrations, repositories, recovery
│   ├── FlowbackFocus/               # Adapters, intent engine, arbiter, focus controller
│   ├── FlowbackProviders/           # Antigravity, Claude Code, Codex, Generic Hook
│   ├── FlowbackServer/              # Unix socket server and IPC handler
│   ├── FlowbackNotifications/       # UNUserNotificationCenter manager
│   ├── FlowbackUI/                  # Menu bar controller & SwiftUI dashboard
│   ├── FlowbackApp/                 # App composition root & NSApplicationDelegate
│   ├── FlowbackCLI/                 # flowback CLI executable
│   ├── FlowbackTestHarness/         # Test doubles, mocks, and fixtures
│   └── FlowbackTestRunner/          # Standalone test runner executable
```

---

## Building Locally

### Debug Build
```bash
swift build
```

### Release Build
```bash
swift build -c release
```

Output binaries will be placed in `.build/release/`:
* `Flowback` — Native macOS GUI application
* `flowback` — Command-line interface
* `FlowbackTestRunner` — Test suite runner

---

## Running the Verification Test Suite

Flowback includes a deterministic test harness covering:
* Agent State Machine transitions & terminal state enforcement
* Sliding-window event deduplication
* Policy resolution hierarchy (Workspace > Application > Provider > Global)
* SQLite WAL mode, schema migrations, and recovery
* Antigravity hook payload parsing & `fullyIdle` prioritization
* Acceptance Scenarios A through J (focus restoration, active typing suppression, cooldowns, invalid window fallback, fullscreen protection, focus lock, wake reconciliation, crash recovery)

To run the complete test suite:
```bash
swift run FlowbackTestRunner
```

Expected output:
```text
================================================================
Flowback Universal Context & Focus Manager — Verification Suites
================================================================
...
================================================================
TEST RESULTS SUMMARY
Total tests executed: 37
Passed: 37
Failed: 0
================================================================
ALL VERIFICATION SUITES PASSED! ✓
```

---

## Packaging the Application Bundle

To assemble `Flowback.app` and sign it with Hardened Runtime entitlements:
```bash
bash Scripts/package_app.sh
```

The output bundle is generated at:
`dist/Flowback.app`

To package into a distributable disk image:
```bash
bash Scripts/create_dmg.sh
```

The output DMG is generated at:
`dist/Flowback.dmg`

---

## Testing IPC & CLI Locally

1. Start Flowback in the background or terminal:
   ```bash
   ./.build/release/Flowback
   ```
2. In another terminal window, use the CLI:
   ```bash
   ./.build/release/flowback status
   ./.build/release/flowback doctor
   ./.build/release/flowback providers
   ./.build/release/flowback test-focus
   ```
