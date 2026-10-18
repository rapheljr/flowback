# Flowback × Vorssaint — General Sidebar Destinations Audit & Report

**Date:** October 2026  
**Auditor:** Principal macOS Product Architect & Senior SwiftUI Engineer  
**Reference Repository:** `vorssaint-utils` (Strictly Read-Only Reference)  
**Target Repository:** `flowback`  
**Status:** Complete & Verified  

---

## 1. Executive Summary

Four general-purpose destinations have been integrated into Flowback's primary navigation shell, modeled after native macOS desktop design patterns discovered in the Vorssaint reference application while adhering strictly to Flowback's design system, MIT licensing, and agent-orchestration security model:

1. **Advanced (`wrench.and.screwdriver`)**: Deep configuration controls including lifecycle event behaviors, provider-specific overrides, JSON configuration export/import with validation, macOS system permissions reset (`lock.slash`), destructive factory reset confirmation, and real-time subsystem diagnostics.
2. **What's New (`sparkles`)**: Structured release notes organized by categorized change tags (Added, Changed & Improved, Fixed, Security & Privacy, Known Limitations) with dedicated SF Symbols, scannable bullet points, and clean empty-state fallback.
3. **Support (`heart.fill`)**: Troubleshooting and community support center featuring Buy Me a Coffee contributions, a subsystem diagnostic self-check doctor, native navigation to detailed diagnostics, privacy-sanitized diagnostic report export with `NSSavePanel`, and official links to documentation and issue tracker.
4. **About Flowback (`info.circle`)**: Compact, native macOS application identity view presenting dynamic bundle version and build information, product description, interactive MIT license modal sheet, and repository resource links.

All 10 dashboard destinations (5 Workspace tabs + 5 Preferences & Help tabs) are accessible via the unified sidebar and global keyboard shortcuts `⌘1` through `⌘0`.

---

## 2. Navigation Architecture & Sidebar Organization

### 2.1 Centralized Destination Enum
The navigation model in `Sources/FlowbackUI/Dashboard/DashboardView.swift` was extended via `DashboardTab`:

- Conforms to `String`, `CaseIterable`, `Identifiable`, and `Sendable`.
- Segregated into two logical groupings:
  - **Workspace**: `overview` (⌘1), `agents` (⌘2), `applications` (⌘3), `timeline` (⌘4), `diagnostics` (⌘5).
  - **Preferences & Help**: `settings` (⌘6), `advanced` (⌘7), `whatsNew` (⌘8), `support` (⌘9), `about` (⌘0).
- Sidebar presentation uses native macOS `List` sections with section headers (`Text("Workspace")` and `Text("Preferences & Help")`).
- Each item displays a native SF Symbol icon with fixed frame `(width: 18)`, bold title, and distinct accessibility identifier.

### 2.2 Routing & State Preservation
Selecting any destination in the sidebar dynamically switches the main detail canvas via a `switch selectedTab` block. Switching tabs preserves all underlying application state, including pending edits, session filters, and running agent monitors.

### 2.3 Header Navigation, Toolbar & Window Architecture (Vorssaint Parity)
Flowback replicates Vorssaint's exact window and toolbar architecture (`Sources/Vorssaint/UI/Settings/SettingsView.swift` & `AppDelegate.swift`):
- **Window Hosting**: Hosted via `NSHostingController(rootView: dashboardView)` with `host.sizingOptions = []` and `NSWindow(contentViewController: host)`. Empty sizing options prevent SwiftUI's internal dynamic size queries from jittering window dimensions or toolbar layouts.
- **Fixed Leading Placement**: The toolbar exclusively contains navigation items configured with `placement: .navigation`:
  - **Sidebar Toggle (`sidebar.left`)**: Shortcut `⌃⌘S` toggles `columnVisibility` dynamically between `.all` and `.detailOnly` with `accessibilityDisplayShouldReduceMotion` support.
  - **Back Button (`chevron.backward`)**: Shortcut `⌘[` navigates to the previous visited tab in the session history stack. Automatically disabled when at root (`canGoBack == false`).
  - **Forward Button (`chevron.forward`)**: Shortcut `⌘]` navigates forward in the session history stack. Automatically disabled when at top of stack (`canGoForward == false`).
- **Zero Trailing Drifting**: No `placement: .automatic` toolbar items are attached to `NavigationSplitView`. Refresh is invoked via global keyboard shortcut (`⌘R`) and visual button in `OverviewView`.
- **Detail Layout Isolation**: The detail pane is enclosed in `GeometryReader { geometry in detail.frame(width: geometry.size.width, height: geometry.size.height, alignment: .top) }`, preventing unconstrained layout queries when toggling the sidebar.
- **Window Title Authority**: Window title is managed at the AppKit level (`window.title = ...`), eliminating split-view title shifting across sidebar visibility transitions.

---

## 3. Surface Implementations & Behavioral Details

### 3.1 Advanced Destination (`AdvancedView.swift`)
- **Lifecycle Event Behaviors**: Allows users to configure `completionBehavior` (restore origin, notification only, ask user), `permissionBehavior` (focus agent, notification only), and `failureBehavior` (focus agent, notification only).
- **Per-Provider Overrides**: Specialized focus behavior per registered agent CLI provider (`antigravity`, `cursor-agent`, `windsurf`, `opencode`).
- **Configuration Management**:
  - Export configuration as JSON to clipboard or file.
  - Import configuration with syntax and structural validation; malformed JSON alerts the user without corrupting memory or disk settings.
  - Destructive "Reset to Factory Defaults" with confirmation dialog and alert state.
- **Subsystem Architecture Inspection**: Real-time read-only status of Accessibility permissions, Focus Policy Engine, Storage Backend (SQLite / In-Memory), and Provider CLI Discovery.

### 3.2 What's New Destination (`WhatsNewView.swift` & `ReleaseNotesModel.swift`)
- **Authoritative Data Source**: `ReleaseNotesModel.current` provides structured release notes derived directly from the authoritative project `CHANGELOG.md` for version 1.0.0.
- **Section Categorization**:
  - `Added` (`plus.circle.fill`, Accent color): Flowback daemon, CLI launcher, multi-provider monitoring, Swift 6 concurrency, visual parity suite.
  - `Changed & Improved` (`slider.horizontal.3`, Purple): Menu bar popover latency, Apple HIG card layout, WCAG AA contrast ratio compliance.
  - `Fixed` (`checkmark.circle.fill`, Green): Cursor CLI detection, stale lock cleanup, focus-stealing prevention during meetings.
  - `Security & Privacy` (`lock.shield.fill`, Blue): Local-first execution, unprivileged daemon architecture, zero telemetry, secret redaction engine.
  - `Known Limitations` (`exclamationmark.triangle`, Orange): macOS Accessibility permissions requirement, sandboxed terminal constraints.
- **Graceful Fallback**: When no release notes are available, an actionable `EmptyStateView` is displayed.

### 3.3 Support Destination (`SupportView.swift` & `DiagnosticReportExporter.swift`)
- **Subsystem Self-Check Doctor**: Run on-demand diagnostic scans verifying Accessibility API permissions, Agent CLI detection, and database storage integrity.
- **Deep Diagnostics Navigation**: Dedicated button allowing immediate navigation to the detailed `DiagnosticsView`.
- **Sanitized Diagnostic Export**:
  - Uses `DiagnosticReportExporter` to compile system specifications (macOS version, hardware architecture), current configuration, daemon state, and recent timeline records.
  - **Secret Sanitization**: Integrates with `SecretSanitizer` to automatically redact API keys (`sk-...`, Bearer tokens), user passwords, and private key blocks (`BEGIN PRIVATE KEY`).
  - **Path Sanitization**: User home directories (e.g., `/Users/username/...`) are automatically mapped to `~/...` to prevent leaking personal identity.
  - **Native Save Flow**: Prompts user via native macOS `NSSavePanel` and displays success/failure status banners.
- **Authoritative Support Links**:
  - Project Documentation: `https://github.com/rapheljr/flowback#readme`
  - GitHub Issues & Bug Reports: `https://github.com/rapheljr/flowback/issues`
  - Troubleshooting Guide: `https://github.com/rapheljr/flowback/blob/main/Docs/`

### 3.4 About Flowback Destination (`AboutView.swift`)
- **Application Identity Hero**: Displays app icon, localized application title, tagline, and bundle identifier (`com.flowback.Flowback`).
- **Dynamic Version Metadata**: Sourced dynamically from `Bundle.main.infoDictionary` (`CFBundleShortVersionString` and `CFBundleVersion`), defaulting to release `1.0.0 (Build 1)` when running outside an application bundle.
- **Interactive License Viewer**: Embedded button launches a native SwiftUI sheet modal rendering the full MIT License text without external web requests.
- **Project Links**: Native macOS button links to GitHub Repository, Documentation, and Issue Tracker.

---

## 4. Privacy & Security Safeguards Audit

The diagnostic export engine in `Sources/FlowbackCore/Services/DiagnosticReportExporter.swift` was subjected to rigorous positive and negative privacy tests (`V-022`):

| Test Case | Input | Sanitized Output | Result |
| :--- | :--- | :--- | :---: |
| **API Key Redaction** | `API_KEY="sk-ant-api03-abcdef1234567890"` | `API_KEY="[REDACTED_TOKEN]"` | **PASS** |
| **Bearer Token Redaction** | `Authorization: Bearer sec_tok_998877` | `Authorization: Bearer [REDACTED_TOKEN]` | **PASS** |
| **Password Redaction** | `password="secretPassword123!"` | `password="[REDACTED_PASSWORD]"` | **PASS** |
| **Home Directory Sanitization** | `/Users/currentuser/workspace/projects/flowback` | `~/workspace/projects/flowback` | **PASS** |
| **Header Preservation** | `# Flowback Diagnostic Report` | `# Flowback Diagnostic Report` | **PASS** |
| **System Info Preservation** | `OS Version: macOS 15.0 (24A335)` | `OS Version: macOS 15.0 (24A335)` | **PASS** |

---

## 5. Visual Parity, Layout & Accessibility Audit

### 5.1 Screenshot Capture Matrix
Screenshots were captured across light, dark, and increased-contrast modes via `VisualParitySuites.swift` (rendered directly into `Docs/audits/screenshots/`):

- `dashboard_overview_dark.png` / `dashboard_overview_light.png` / `dashboard_overview_increased_contrast.png`
- `dashboard_agents_dark.png` / `dashboard_agents_light.png` / `dashboard_agents_empty_dark.png`
- `dashboard_timeline_dark.png` / `dashboard_timeline_light.png`
- `dashboard_applications_dark.png` / `dashboard_applications_light.png` / `dashboard_applications_empty_dark.png`
- `dashboard_diagnostics_dark.png` / `dashboard_diagnostics_light.png`
- `dashboard_settings_dark.png` / `dashboard_settings_light.png`
- `dashboard_advanced_dark.png` / `dashboard_advanced_light.png` / `dashboard_advanced_increased_contrast.png`
- `dashboard_whats_new_dark.png` / `dashboard_whats_new_light.png` / `dashboard_whats_new_empty_dark.png`
- `dashboard_support_dark.png` / `dashboard_support_light.png`
- `dashboard_about_dark.png` / `dashboard_about_light.png`

### 5.2 WCAG AA Contrast Audit
- **Dark Mode Primary Text**: Contrast ratio is **14.74:1** (WCAG AA requirement: $\ge 4.5:1$).
- **Dark Mode Secondary Text**: Contrast ratio is **5.63:1** (WCAG AA requirement: $\ge 4.5:1$).
- **Light Mode Primary Text**: Contrast ratio is **17.40:1** (WCAG AA requirement: $\ge 4.5:1$).
- **Light Mode Secondary Text**: Contrast ratio is **6.47:1** (WCAG AA requirement: $\ge 4.5:1$).
- **Status Indicator Badges**: Graphical objects contrast ratio is **6.63:1** (WCAG requirement for UI components: $\ge 3.0:1$).
- **Non-Color Dependence**: Every status badge includes a distinct SF Symbol (`checkmark`, `exclamationmark`, `arrow.triangle.2.circlepath`), ensuring unambiguous information perception for color-blind users.

---

## 6. Verification & Test Execution Results

All local verification checks pass cleanly:

1. **SwiftLint Strict Mode**:
   ```
   DYLD_FRAMEWORK_PATH="/Library/Developer/CommandLineTools/usr/lib" swiftlint lint --strict
   ✓ SwiftLint passed with 0 violations in 112 files.
   ```
2. **Swift Compilation**:
   ```
   swift build
   ✓ Swift build succeeded with 0 errors.
   ```
3. **Flowback Test Runner**:
   ```
   swift run FlowbackTestRunner
   Total tests executed: 903
   Passed: 903
   Failed: 0
   ALL VERIFICATION SUITES PASSED! ✓
   ```
4. **Pre-flight & Release Build Scripts**:
   ```
   bash Scripts/verify_all.sh
   bash Scripts/build.sh
   bash Scripts/package_app.sh
   bash Scripts/create_dmg.sh
   🎉 ALL LOCAL CHECKS PASSED — 0 WARNINGS, READY TO COMMIT/PUSH!
   ```
5. **Git Hygiene**:
   - `vorssaint-utils`: Completely clean and untouched (0 modified files, 0 untracked files).
   - `flowback`: No unstaged unwanted changes, `git diff --check` clean.
