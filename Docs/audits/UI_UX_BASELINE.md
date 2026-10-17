# Flowback × Vorssaint — UI/UX Baseline Audit

**Date:** October 2026  
**Auditor:** Principal macOS Product Designer & Senior SwiftUI/AppKit Engineer  
**Reference Repository:** `vorssaint-utils` (Strictly Read-Only Reference)  
**Target Repository:** `flowback`  
**Licensing Constraint:** Vorssaint is GPL-3.0-or-later; Flowback is MIT. All implementations must be independently authored in Flowback using native Swift, SwiftUI, AppKit, and SF Symbols.

---

## 1. Environment & Repository Baseline

### 1.1 Repositories & State

| Repository | Path | Git Branch | HEAD Commit | Working Tree Status | Licensing |
| :--- | :--- | :---: | :---: | :---: | :---: |
| **Flowback** (Target) | `/Users/abin/workspace/projects/flowback` | `main` | `c25464f` | Working tree clean of external uncommitted changes; local remediation & discovery additions active | MIT License |
| **Vorssaint** (Reference) | `/Users/abin/workspace/projects/vorssaint-utils` | `main` | `125167ae` | Clean, 0 uncommitted changes | GPL-3.0-or-later |

### 1.2 Toolchain & Platform Targets

- **Operating System:** macOS 14.0+ (Sonoma, Sequoia, and future versions)
- **Swift Version:** Swift 6.0 toolchain (`Package.swift` `// swift-tools-version: 6.0`)
- **UI Frameworks:** SwiftUI + AppKit interoperability
- **Linting & Code Quality:** SwiftLint 0.65.1 (strict mode, 0 violations across 103 source files)
- **Authoritative Test Suites:** `FlowbackTestRunner` (659 automated unit/integration/acceptance tests)

---

## 2. Existing UI Surfaces & Entry Points

Flowback currently exposes two primary UI surfaces to users:

```text
┌────────────────────────────────────────────────────────────────────────┐
│                        macOS Menu Bar                                  │
│  [Flowback Status Item]  [ ⤹ 2 ] ──> Interactive NSMenu Dropdown       │
│                                      ├── Section: Status & Active Count│
│                                      ├── Section: Active Conversations │
│                                      ├── Submenu: Recent Agent Sessions│
│                                      ├── Submenu: Attention Queue      │
│                                      ├── Focus Lock Controls           │
│                                      └── App Navigation (Dashboard...) │
└────────────────────────────────────────────────────────────────────────┘
                                     │
                        (User clicks "Dashboard...")
                                     ▼
┌────────────────────────────────────────────────────────────────────────┐
│                 Flowback Main Dashboard Window (800x550)                │
│  NavigationSplitView                                                   │
│  ├── Sidebar (DashboardTab)                                            │
│  │    ├── Overview         (Live activity, quick stats, active list)   │
│  │    ├── Agents           (Filtered session list, search bar)         │
│  │    ├── Timeline         (Chronological decision audit log)          │
│  │    ├── Applications     (Protected application bundle rules)        │
│  │    ├── Diagnostics      (Doctor checks, permissions, test buttons)  │
│  │    └── Settings         (Focus policy, space policy, timing sliders)│
│  └── Detail Area                                                       │
│       ├── Durable Storage Recovery Warning Banner (when fallback active│
│       └── Selected Tab Content View                                    │
└────────────────────────────────────────────────────────────────────────┘
```

### 2.1 Screen-by-Screen Inventory in Flowback

| Surface / Screen | File Path | Primary Purpose | Controls & Actions |
| :--- | :--- | :--- | :--- |
| **Menu Bar Controller** | `Sources/FlowbackUI/MenuBar/MenuBarController.swift` | Persistent ambient status & quick focus switching | Focus session, toggle focus lock (15m/30m/1h/indefinite), refresh, open Dashboard, Settings, Diagnostics, Quit |
| **Dashboard Shell** | `Sources/FlowbackUI/Dashboard/DashboardView.swift` | Window frame, sidebar navigation, toolbar, shortcut routing | Tab switching (`⌘1`..`⌘6`), manual refresh (`⌘R`), storage warning banner |
| **Overview View** | `Sources/FlowbackUI/Views/OverviewView.swift` | High-level glance at agent count, attention requests, focus mode | Focus Lock dismiss, StatCards (Active, Queue, Mode), attention list, active session rows with "Restore Focus" |
| **Agents View** | `Sources/FlowbackUI/Views/AgentsView.swift` | Discover and search across active and past agent sessions | Segmented filter (`All`, `Active`, `Completed`, `Failed`), search query field, row focus button |
| **Session Timeline View** | `Sources/FlowbackUI/Views/SessionTimelineView.swift` | Audit trail of focus orchestration and agent events | Session picker filter, timestamped event rows with decision explanations |
| **Applications View** | `Sources/FlowbackUI/Views/ApplicationsView.swift` | Manage protected apps that inhibit focus stealing | Text field to add bundle IDs (e.g. `us.zoom.xos`), list of protected apps with delete buttons |
| **Diagnostics View** | `Sources/FlowbackUI/Views/DiagnosticsView.swift` | Subsystem doctor, permission guides, simulator triggers | Test Focus button, Test Notification button, Accessibility settings deep-link, provider health status |
| **Settings View** | `Sources/FlowbackUI/Views/SettingsView.swift` | Configure focus policy, spaces policy, timing, and launch at login | Radio group focus policy, Space policy menu, sliders for cooldowns/thresholds, Launch at login toggle, Save button |

---

## 3. Current Design Tokens & Conventions

Flowback previously introduced `ThemeTokens.swift` and `StatusBadge.swift`:

- **High Contrast Awareness:** `NSWorkspace.shared.accessibilityDisplayShouldIncreaseContrast`
- **Dynamic Borders:** `ThemeTokens.cardBorder(for: colorScheme)` (adaptive 0.10 to 0.35 opacity)
- **Status Colors:** Luminance-adjusted WCAG AA colors for `.starting`, `.running`, `.completed`, `.permissionRequired`, `.failed`, `.cancelled`.
- **Card Fill:** `ThemeTokens.cardFill(for: colorScheme)`

### Identified Deficiencies in Existing Baseline:
1. **Ad-hoc Backgrounds:** Views frequently use `Color(NSColor.controlBackgroundColor)` instead of `ThemeTokens.cardFill`.
2. **Inconsistent Radius:** Corner radii vary across views (8pt, 10pt, 12pt) without a unified token hierarchy.
3. **Hardcoded Spacing:** Padding values (24pt in Overview/Agents, 20pt in Settings, 16pt in Timeline) are scattered across views rather than using semantic spacing tokens (`Spacing.xs`, `.sm`, `.md`, `.lg`, `.xl`).
4. **Settings Form Structure:** Standard macOS Form `.grouped` style creates narrow, centered form rows with excessive whitespace and poor information hierarchy compared to modern card-based settings (e.g. Vorssaint's `SettingsCard`).
5. **Session Row Density:** `AgentsView` rows stack 4 lines of small text without tabular columnar alignment, making scanning difficult with long workspace paths.
6. **Empty States:** Empty states lack actionable recovery buttons (e.g. "Refresh Agents" or "Add Rule").

---

## 4. Baseline Verification Status

The Flowback repository baseline was tested prior to new UI modifications:

- `git diff --check`: **0 errors**
- `DYLD_FRAMEWORK_PATH="/Library/Developer/CommandLineTools/usr/lib" swiftlint lint --strict`: **103 files, 0 violations**
- `swift build -c debug`: **Passed (Exit 0)**
- `swift build -c release`: **Passed (Exit 0)**
- `swift run FlowbackTestRunner`: **659 tests passed, 0 failed**
- `node Scripts/test_opencode_plugin.js`: **12 tests passed, 0 failed**
- `swift run flowback-cli doctor`: **Passed (Exit 0)**
- `bash Scripts/verify_all.sh`: **Passed (Exit 0)**
