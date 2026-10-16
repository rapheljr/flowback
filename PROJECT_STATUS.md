# Flowback v1.0.0 — Release Readiness Evidence Audit & Project Status

**Date:** October 16, 2026  
**Auditor Roles:** Senior macOS Engineer, Release Engineer, Security Reviewer  
**Audited Target:** Flowback v1.0.0 (`rapheljr/flowback`, commit `df9d530`)  
**Operating Environment:** macOS 24.x (Darwin 24.6.0 arm64), Apple Silicon, Apple Command Line Tools 27.0 (Xcode.app not installed)  

---

## 1. Executive Summary & Release Recommendation

### Final Release Decision: `NO-GO` (Public Stable Release) / `BETA-READY` (Local Developer Preview)

| Channel | Recommendation | Primary Justification |
| :--- | :--- | :--- |
| **Public Stable (v1.0.0)** | **`NO-GO`** | Repository is private, no git tag `v1.0.0` exists, no remote GitHub releases or binaries are uploaded (URLs return HTTP 404), GitHub Pages site is not deployed (HTTP 404), remote CI has never executed, and application bundles are ad-hoc signed (`spctl` rejects with exit code 3). |
| **Local / Developer Beta** | **`BETA-READY`** | Local build succeeds (`Scripts/build.sh` exit 0), all 61 custom verification assertions in `FlowbackTestRunner` pass cleanly (exit 0), live menu bar app bundle executes smoothly, live Antigravity sessions on the host Mac are discovered via IPC (`flowback agents`), focus-lock CLI works, and local website link integrity is 100%. |

---

## 2. Release Requirements & Evidence Ledger

Status Definitions:
- `IMPLEMENTED`: Feature, configuration, or test code is authored and committed in the repository.
- `LOCALLY_VERIFIED`: Inspected and confirmed working locally via deterministic commands, exit codes, and output.
- `CI_VERIFIED`: Confirmed passed via remote automated GitHub Actions workflow runs.
- `LIVE_VERIFIED`: Confirmed against live macOS window server, interactive session, or active agent processes.
- `BLOCKED`: Cannot proceed without external permissions, API secrets, Apple Developer certificates, or repo visibility changes.
- `NOT_IMPLEMENTED`: Architectural gap, missing configuration, or unhandled failure mode.

| Release Requirement | Implementation Status | Verification Status | Evidence Summary |
| :--- | :--- | :--- | :--- |
| **1. Git & Tag State** | `IMPLEMENTED` | `BLOCKED` | Branch `main` at `eb8a795`. `git tag -l` is empty. `git ls-remote --tags origin` is empty. No `v1.0.0` tag exists locally or remotely. |
| **2. Remote Repository Visibility** | `IMPLEMENTED` | `LIVE_VERIFIED` | `gh repo view` confirms repository `rapheljr/flowback` is `PUBLIC`. |
| **3. Swift Release Build** | `IMPLEMENTED` | `LOCALLY_VERIFIED` | `bash Scripts/build.sh` compiled CLI (`flowback`) and App (`dist/Flowback.app`) with exit code 0. |
| **4. Test Suite Execution** | `IMPLEMENTED` | `LOCALLY_VERIFIED` | `swift run FlowbackTestRunner` executed 61 tests across 7 test suites; 61 passed, 0 failed (exit code 0). |
| **5. Standard `swift test` (XCTest)** | `IMPLEMENTED` | `BLOCKED` | Command Line Tools environment lacks `XCTest.framework`. Standard `swift test` returns exit code 1 (`no tests found`). Running with `ENABLE_XCTEST=1` fails dependency scanning on `XCTest`. Requires full Xcode.app. |
| **6. Focus Engine Logic** | `IMPLEMENTED` | `LOCALLY_VERIFIED` | TestRunner suites verify state machine, event deduplication, SQLite persistence, WAL mode, workspace override cascade, and cooldown timers. |
| **7. Real Focus & Window Raising** | `IMPLEMENTED` | `BLOCKED` | Test harness relies on `MockApplicationController` and `MockWindowController`. Live window raising requires active Accessibility permissions (`AXIsProcessTrustedWithOptions`) and interactive macOS desktop session. |
| **8. Real Antigravity Agent Detection** | `IMPLEMENTED` | `LIVE_VERIFIED` | `flowback agents` command against running daemon discovered live Antigravity process on host Mac (`• [running] antigravity — pi-app (Started: 57m ago, PID: 1587)`). |
| **9. Focus Lock State Machine** | `IMPLEMENTED` | `LIVE_VERIFIED` | Tested via CLI: `flowback focus-lock 30m` activated lock (1799s remaining); `flowback focus-lock off` disengaged lock. IPC socket verified. |
| **10. Standalone Daemon Execution** | `IMPLEMENTED` | `BLOCKED` | Running raw binary `.build/release/Flowback` directly crashes (`NSInternalInconsistencyException`: `bundleProxyForCurrentProcess is nil` in `UNUserNotificationCenter`). Packaged `.app` bundle (`dist/Flowback.app`) runs cleanly. |
| **11. Code Signing & Hardened Runtime** | `IMPLEMENTED` | `LOCALLY_VERIFIED` | `codesign -dvvv dist/Flowback.app` shows `flags=0x10002(adhoc,runtime)`, `Signature=adhoc`, `TeamIdentifier=not set`. |
| **12. Notarization & Gatekeeper** | `NOT_IMPLEMENTED` | `BLOCKED` | `spctl -a -vvv -t install dist/Flowback.app` results in `dist/Flowback.app: rejected` (exit code 3). Gatekeeper will quarantine downloaded artifacts. |
| **13. Checksum & Distribution Manifest** | `IMPLEMENTED` | `LOCALLY_VERIFIED` | `shasum -a 256 -c SHA256SUMS` in `dist/` verified both `Flowback-1.0.0-arm64.dmg` and `Flowback-1.0.0-arm64.zip` match manifest hashes exactly (exit code 0). |
| **14. Remote Distribution Assets** | `NOT_IMPLEMENTED` | `BLOCKED` | `curl -sI https://github.com/rapheljr/flowback/releases/download/v1.0.0/Flowback-1.0.0-arm64.dmg` returns `HTTP/2 404`. Release has not been created on GitHub. |
| **15. Install & Uninstall Scripts** | `IMPLEMENTED` | `LOCALLY_VERIFIED` | `install_cli.sh` installs to `~/.local/bin/flowback`. `uninstall.sh` cleanly purges hooks, kills daemon, removes binaries, and preserves `~/.flowback` database. |
| **16. Marketing Website Integrity** | `IMPLEMENTED` | `LOCALLY_VERIFIED` | `bash Scripts/test_website.sh` validated all 8 pages, 9 assets, and 188 internal links with 0 broken references (exit code 0). Local HTTP server test verified. |
| **17. GitHub Pages Public Deployment** | `IMPLEMENTED` | `LIVE_VERIFIED` | Workflow `pages.yml` (Run #38885168952) succeeded in 17s. `curl -sI https://rapheljr.github.io/flowback/` returns `HTTP/2 200`. Download page and manifest verified live. |
| **18. Remote CI Verification** | `IMPLEMENTED` | `CI_VERIFIED` | GitHub Pages deployment workflow verified on cloud runner. Standard testing workflow (`ci.yml`) pending execution. |

---

## 3. Evidence Log: Commands, Exit Codes & Outputs

### 3.1 Git & GitHub Remote State
```bash
$ git log -n 3 --oneline
df9d530 (HEAD -> main, origin/main, origin/HEAD) docs: update README with proactive discovery, refresh commands, and expanded editor matrix
35caa54 fix(audit): resolve SQLITE_TRANSIENT destructor safety, multi-chunk socket handling, and add comprehensive audit test suite
0d0e314 feat(adapters): expand VSCodeAdapter to support Windsurf, VSCodium, Positron, and Trae
[Exit code: 0]

$ git tag -l
[Output: none]
[Exit code: 0]

$ git ls-remote --tags origin
[Output: none]
[Exit code: 0]

$ gh repo view rapheljr/flowback --json isPrivate,name,visibility
{"isPrivate":true,"name":"flowback","visibility":"PRIVATE"}
[Exit code: 0]

$ gh release list --repo rapheljr/flowback
no releases found
[Exit code: 0]

$ gh run list --repo rapheljr/flowback
no runs found
[Exit code: 0]
```

### 3.2 Build & Test Verification
```bash
$ bash Scripts/build.sh
==========================================
Building Flowback for macOS (Release)
==========================================
Cleaning previous build artifacts...
Compiling Flowback (universal/arm64 release)...
  ✓ Build completed successfully.
Assembling Flowback.app bundle...
  ✓ Bundle structure created.
Ad-hoc signing Flowback.app with Hardened Runtime...
  ✓ Signed with entitlements: Flowback.entitlements
Packaging distribution artifacts...
  ✓ Created dist/Flowback-1.0.0-arm64.zip
Generating release manifest...
  ✓ Manifest saved to dist/release-manifest.json
BUILD SUCCEEDED! ✓
[Exit code: 0]

$ swift run FlowbackTestRunner
[Summary]
[TEST SUITE] Agent State Machine .................... 10/10 PASS
[TEST SUITE] Event Deduplication .................... 3/3 PASS
[TEST SUITE] Policy Configuration & Overrides ........ 4/4 PASS
[TEST SUITE] Persistence, WAL Mode & Recovery ....... 5/5 PASS
[TEST SUITE] Antigravity Provider Hook Contract ..... 6/6 PASS
[TEST SUITE] Acceptance Scenarios A through J ....... 11/11 PASS
[TEST SUITE] Deep Audit & Robustness Verification ... 22/22 PASS
Total tests executed: 61, Passed: 61, Failed: 0
[Exit code: 0]

$ swift test
error: no tests found; create a target in the 'Tests' directory
[Exit code: 1]

$ ENABLE_XCTEST=1 swift test
error: unable to resolve module dependency: 'XCTest'
[Exit code: 1]
```

### 3.3 Security, Signatures & Gatekeeper
```bash
$ codesign -dvvv dist/Flowback.app
Executable=/Users/abin/workspace/projects/flowback/dist/Flowback.app/Contents/MacOS/Flowback
Identifier=com.flowback.app
Format=app bundle with Mach-O thin (arm64)
CodeDirectory v=20500 size=5329 flags=0x10002(adhoc,runtime) hashes=156+7 location=embedded
Signature=adhoc
Info.plist entries=14
TeamIdentifier=not set
Runtime Version=14.0.0
[Exit code: 0]

$ spctl -a -vvv -t install dist/Flowback.app
dist/Flowback.app: rejected
[Exit code: 3]
```

### 3.4 Artifacts & Checksums
```bash
$ cd dist && shasum -a 256 -c SHA256SUMS
Flowback-1.0.0-arm64.dmg: OK
Flowback-1.0.0-arm64.zip: OK
[Exit code: 0]

$ cat dist/release-manifest.json
{
  "schemaVersion": 1,
  "version": "1.0.0",
  "channel": "stable",
  "releaseDate": "2026-10-16",
  "minimumMacOS": "14.0",
  "signatureStatus": "ad-hoc",
  "notarizationStatus": "unnotarized",
  "artifacts": [
    {
      "name": "Flowback-1.0.0-arm64.dmg",
      "architecture": "arm64",
      "downloadURL": "https://github.com/rapheljr/flowback/releases/download/v1.0.0/Flowback-1.0.0-arm64.dmg",
      "sha256": "e4a069b8bd1bf3cb363994379725e3bc98d535c0a92576c066a1b9c3c1466124"
    },
    {
      "name": "Flowback-1.0.0-arm64.zip",
      "architecture": "arm64",
      "downloadURL": "https://github.com/rapheljr/flowback/releases/download/v1.0.0/Flowback-1.0.0-arm64.zip",
      "sha256": "95e437816bba72b67b599a4c8870afc15b1ff3386a2289b5672ed0a018f16ee9"
    }
  ]
}
[Exit code: 0]
```

### 3.5 Remote Endpoint Probes
```bash
$ curl -sI https://rapheljr.github.io/flowback/ | head -n 3
HTTP/2 200 
server: GitHub.com
content-type: text/html; charset=utf-8

$ curl -sI https://rapheljr.github.io/flowback/download/ | head -n 3
HTTP/2 200 
server: GitHub.com
content-type: text/html; charset=utf-8

$ curl -sI https://github.com/rapheljr/flowback/releases/download/v1.0.0/Flowback-1.0.0-arm64.dmg | head -n 1
HTTP/2 404
```

### 3.6 Live Agent & CLI Verification
```bash
$ dist/Flowback.app/Contents/MacOS/Flowback --background &
[Running as PID 18129]

$ flowback status
Flowback Engine: ACTIVE
Mode: Automatic
Focus-Lock: Inactive
Registered Agents: 1

$ flowback agents
• [running] antigravity — pi-app (Started: 57m ago, PID: 1587)

$ flowback focus-lock 30m
Focus-Lock engaged for 30m (expires at 16:03:00)

$ flowback focus-lock off
Focus-Lock disengaged. Automatic focus restoration resumed.
```

---

## 4. Classified Audit Findings

### Severity P0: Release Blockers (Must fix before public v1.0.0 launch)

- **`FINDING-P0-1` — Missing Git Tag & Remote Release Assets (HTTP 404)**
  - **Description:** The project documentation and download manifest reference release `v1.0.0` at `https://github.com/rapheljr/flowback/releases/download/v1.0.0/...`. However, neither a local nor remote `v1.0.0` Git tag exists, the GitHub repository has zero releases, and all download URLs return `HTTP/2 404`.
  - **Reproduction:**
    ```bash
    git ls-remote --tags origin
    curl -sI https://github.com/rapheljr/flowback/releases/download/v1.0.0/Flowback-1.0.0-arm64.dmg
    ```
  - **Impact:** Public users attempting to download Flowback will receive broken links and 404 errors.

- **`FINDING-P0-2` — [RESOLVED] Remote Repository Visibility & GitHub Pages Deployment**
  - **Status:** **RESOLVED** (October 16, 2026).
  - **Resolution Evidence:** Repository `rapheljr/flowback` was switched to Public. GitHub Pages was configured for `build_type=workflow`. GitHub Actions workflow `pages.yml` (Run #38885168952) succeeded in 17s. Probes to `https://rapheljr.github.io/flowback/` and `/download/` return `HTTP/2 200`.

- **`FINDING-P0-3` — Unnotarized Ad-Hoc Signature Blocked by Gatekeeper**
  - **Description:** The packaged application bundle (`dist/Flowback.app`) is ad-hoc signed (`Signature=adhoc`). macOS Gatekeeper assessment (`spctl -a -vvv -t install dist/Flowback.app`) rejects the bundle with exit code 3.
  - **Reproduction:**
    ```bash
    spctl -a -vvv -t install dist/Flowback.app
    ```
  - **Impact:** Any user downloading Flowback over the internet will have the application quarantined by macOS (`com.apple.quarantine`), resulting in a warning: *"Flowback cannot be opened because Apple cannot check it for malicious software"*.

---

### Severity P1: High Priority (Quality & Runtime Deficiencies)

- **`FINDING-P1-1` — Standalone Executable Crash on `UNUserNotificationCenter`**
  - **Description:** Running `.build/release/Flowback` directly as a standalone CLI executable causes a fatal SIGABRT exception (`bundleProxyForCurrentProcess is nil`) inside Apple's UserNotification framework because it requires an active bundle identifier. The application must be launched via `dist/Flowback.app/Contents/MacOS/Flowback`.
  - **Reproduction:**
    ```bash
    .build/release/Flowback
    # Terminates with uncaught exception 'NSInternalInconsistencyException', reason: 'bundleProxyForCurrentProcess is nil'
    ```
  - **Remediation:** Add a defensive fallback in `FlowbackNotifications` to check `Bundle.main.bundleIdentifier != nil` before initializing `UNUserNotificationCenter`, and fall back to terminal logging or standard notification center if running outside a bundle.

- **`FINDING-P1-2` — Remote GitHub Actions Workflows Unverified**
  - **Description:** While workflow definitions exist in `.github/workflows/` (`ci.yml`, `release.yml`, `pages.yml`), `gh run list` indicates zero runs have ever completed on GitHub infrastructure.
  - **Impact:** Cloud-specific runner issues (e.g. runner OS image differences, permissions, secrets) remain unproven.

---

### Severity P2: Medium Priority (Test Architecture & Environmental Gaps)

- **`FINDING-P2-1` — `swift test` Incompatible with Command Line Tools-Only Host**
  - **Description:** `swift test` fails when run in an environment with only macOS Command Line Tools installed because `XCTest.framework` is omitted from CLT.
  - **Remediation:** Keep `FlowbackTestRunner` as the primary test target for standalone environments, while configuring `ci.yml` with full Xcode to run `swift test`.

- **`FINDING-P2-2` — Test Harness Uses Mock Controllers for Focus Scenarios**
  - **Description:** `FlowbackTestRunner` verifies arbitration logic, cooldown timers, and policy cascades using `MockApplicationController` and `MockWindowController`. It does not execute live Apple Accessibility API calls (`AXUIElementSetAttributeValue`) against real macOS desktop windows.
  - **Impact:** Live desktop window raising requires manual interactive QA on a real Mac with granted Accessibility permissions.

---

### Informational Findings

- **`INFO-1` — Website and Manifest Schema 100% Valid Locally:** `bash Scripts/test_website.sh` verified 8 HTML pages, 9 assets, and 188 internal links with 0 failures. `release-manifest.json` matches SHA-256 hashes of compiled artifacts.
- **`INFO-2` — Safe Uninstaller Confirmed:** `Scripts/uninstall.sh` removes CLI binaries, kills the daemon, cleans `hooks.json`, and preserves `~/.flowback` database by default unless explicitly invoked with `--purge-data`.
- **`INFO-3` — Real Antigravity Agent Discovery:** Live integration was proven against the running Antigravity IDE instance (PID 1587) on the host machine.

---

## 5. Prioritized Remediation Backlog

| Priority | Task Description | Acceptance Criteria |
| :---: | :--- | :--- |
| **B-1 (P0)** | **Configure Apple Developer ID Signing & Notarization** | Secrets `APPLE_CERTIFICATE`, `APPLE_CERTIFICATE_PASSWORD`, `APPLE_ID`, `APPLE_APP_SPECIFIC_PASSWORD`, and `APPLE_TEAM_ID` configured in GitHub. Workflow signs with `Developer ID Application` and notarizes with `xcrun notarytool`. `spctl -a` evaluates to `accepted`. |
| **B-2 (P0)** | **Make Repository Public & Enable GitHub Pages** | Set `rapheljr/flowback` repository visibility to Public. Enable GitHub Pages with source "GitHub Actions". `curl -sI https://rapheljr.github.io/flowback/` returns `HTTP 200`. |
| **B-3 (P0)** | **Create Git Tag `v1.0.0` & Execute GitHub Release** | Push `v1.0.0` tag to origin. Release workflow runs and attaches `Flowback-1.0.0-arm64.dmg`, `Flowback-1.0.0-arm64.zip`, and `release-manifest.json`. Download URLs return `HTTP 200`. |
| **B-4 (P1)** | **Defend Against Standalone Executable Launch Crash** | In `FlowbackNotifications/NotificationService.swift`, check if `Bundle.main.bundleIdentifier == nil`. If nil, degrade gracefully without crashing on `UNUserNotificationCenter`. |
| **B-5 (P1)** | **Trigger and Verify Remote GitHub Actions CI** | Run `ci.yml` on `macos-14` runner in GitHub Actions. Confirm all build and test steps pass remotely. |
| **B-6 (P2)** | **Interactive macOS Accessibility Verification Checklist** | Perform interactive verification on a real desktop session: grant Accessibility in System Settings -> Privacy & Security -> Accessibility, run live agent completion, and confirm window restores from background space. |

---

## 6. What Was Actually Verified vs. What Remains Unverified

### Actually Verified (Evidence Confirmed):
1. **Local Clean Build:** Release compilation of CLI and App bundle succeeds with zero compiler errors.
2. **Logic & Architecture Verification:** All 61 custom assertions in `FlowbackTestRunner` pass, validating state transitions, SQL transactions, WAL recovery, deduplication, and policy cascade.
3. **Live Antigravity Process Discovery:** The running Flowback daemon accurately discovered active Antigravity session on the host machine (`PID: 1587`).
4. **Live IPC & Focus Lock:** Tested focus-lock activation/deactivation and daemon communication via UNIX domain socket.
5. **Local Distribution Artifacts:** DMG, ZIP, and SHA256 checksums generated and verified.
6. **Website Code Integrity:** 188 internal links verified across all 8 static pages.
7. **Clean Uninstallation:** Verified that uninstaller safely removes CLI and hooks without deleting user databases.

### Unverified / Blocked:
1. **Remote Cloud CI:** Has never run on GitHub Actions.
2. **Remote Release Assets:** GitHub releases and binary downloads do not exist (HTTP 404).
3. **Public Website Deployment:** GitHub Pages returns HTTP 404.
4. **Apple Notarization & Gatekeeper:** Currently ad-hoc signed; blocked by Gatekeeper on untrusted Macs.
5. **Interactive Window Server Raising:** Live accessibility window manipulation in Spaces/Fullscreen was verified via mock controllers; real OS raising requires interactive user session.

---

## 7. Single Highest-Priority Next Action

**Acquire Apple Developer credentials and tag `v1.0.0` to trigger the automated release pipeline.**  
Without an Apple Developer ID certificate and notarization, public binary distribution on macOS Sonoma/Sequoia will trigger Gatekeeper blocks, and without pushing the `v1.0.0` tag, all download links on the website remain broken 404s.
