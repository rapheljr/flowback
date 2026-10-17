# Flowback × Vorssaint — Screen & Surface Inventory

**Date:** October 2026  
**Auditor:** Principal macOS Product Designer & Senior SwiftUI Engineer  
**Reference Repository:** `vorssaint-utils` (Strictly Read-Only Reference)  
**Target Repository:** `flowback`  

---

## 1. Comprehensive Surface Matrix

The following table inventories all primary and secondary user-facing surfaces across Flowback and maps them against corresponding patterns in Vorssaint:

| Surface | User Task | Flowback Implementation | Vorssaint Reference | Concrete UX / Visual Gap | Priority | Proposed Action | Verification Criteria |
| :--- | :--- | :--- | :--- | :--- | :---: | :--- | :--- |
| **Main Window & Shell** | Navigate major product areas, view global status, execute refresh | `Sources/FlowbackUI/Dashboard/DashboardView.swift` | `Sources/Vorssaint/UI/Settings/SettingsView.swift` | Flowback's sidebar uses plain system text; window minimum size (800x550) is good, but sidebar lacks session counter badges and unified title styling. | **P1** | Enhance sidebar rows with badge indicators; unify toolbar styling and window insets. | Sidebar displays live active session badge; window resizes cleanly down to 780x520. |
| **Overview / Dashboard** | High-level glance at agent workload, attention requests, quick focus | `Sources/FlowbackUI/Views/OverviewView.swift` | `Sources/Vorssaint/UI/MenuPanel/MenuPanelView.swift` | Flowback stat cards use raw control backgrounds; spacing is rigid; active session list rows lack hover highlights and consistent padding. | **P0** | Adopt unified `DesignTokens.CardModifier`, responsive metric stat cards, and hoverable session cards. | Stat cards adapt to light/dark/high-contrast; hover states highlight rows smoothly. |
| **Agent Session List** | Discover, search, filter, and switch focus to active/past agent sessions | `Sources/FlowbackUI/Views/AgentsView.swift` | `Sources/Vorssaint/UI/Switcher/SwitcherView.swift`, `Sources/Vorssaint/UI/Settings/SettingsCard.swift` | Search bar is functional but lacks keyboard escape clear, result count feedback, and detailed tabular column alignment for paths and origins. | **P0** | Upgrade session row to a structured 2-column card; add keyboard navigation shortcuts and clear feedback on empty search. | Search filters instantly with escape-to-clear; session rows display crisp metadata tags. |
| **Settings & Preferences** | Configure focus policies, desktop spaces, timing thresholds, launch behavior | `Sources/FlowbackUI/Views/SettingsView.swift` | `Sources/Vorssaint/UI/Settings/SettingsCard.swift`, `SettingsRow.swift` | Flowback uses standard SwiftUI `.grouped` Form which feels like an iOS port; lacks icon tiles, secondary descriptions, and card grouping. | **P0** | Reimplement settings using structured `FlowbackSettingsCard` and `FlowbackSettingsRow` with SF Symbol icon tiles. | Settings match native macOS Ventura/Sonoma card aesthetic; sliders and pickers align to 12pt grid. |
| **Protected Applications** | Prevent focus stealing during presentations, meetings, and screen recording | `Sources/FlowbackUI/Views/ApplicationsView.swift` | `Sources/Vorssaint/UI/Settings/WindowMaximizerExclusionsList.swift`, `ClipboardIgnoredAppsList.swift` | App list lacks running application picker or quick suggestions (e.g. Zoom, Keynote, FaceTime, Teams); plain text field only. | **P1** | Add quick-add chip suggestions for common presentation apps; style list rows as cards with application icons. | Quick suggestions populate bundle ID on click; remove button has hover feedback. |
| **Session Timeline** | Review historical orchestration decisions and understand why focus moved | `Sources/FlowbackUI/Views/SessionTimelineView.swift` | `Sources/Vorssaint/UI/MenuPanel/MetricDetailView.swift` | Plain list with text-only badges; lacks decision reason color coding, timeline connector lines, and event type icons. | **P1** | Add visual category icons, decision badges, and vertical timeline indicator line. | Timeline entries show distinct iconography for focus restoration, notification, and suppression. |
| **Doctor & Diagnostics** | Check permissions, test triggers, inspect agent provider health | `Sources/FlowbackUI/Views/DiagnosticsView.swift` | `Sources/Vorssaint/UI/PermissionGuideOverlay.swift`, `Sources/Vorssaint/UI/Settings/ShortcutsSettings.swift` | Diagnostic rows have plain borders; permission action buttons lack clear status icons (green checkmark / red warning icon). | **P1** | Adopt card-based diagnostic status rows with prominent status glyphs and action links. | All subsystems show clear green/orange/red badges; permission guides link directly. |
| **Menu Bar Ambient Popover** | Check agent status from menu bar and switch focus with 1 click | `Sources/FlowbackUI/MenuBar/MenuBarController.swift` | `Sources/Vorssaint/UI/MenuPanel/MenuPanelView.swift` | Flowback uses native `NSMenu` dropdown (rock-solid and accessible), but menu items lack provider-branded glyphs and keyboard shortcuts display. | **P1** | Enrich `NSMenu` items with custom status glyphs, provider icons, and explicit `⌘1`..`⌘9` key equivalents. | Menu bar opens with zero lag; active sessions display provider icons and key shortcuts. |
| **Empty & Loading States** | Guide the user when no data is available or during initial setup | All Views (`AgentsView`, `OverviewView`, `TimelineView`, `ApplicationsView`) | `Sources/Vorssaint/UI/SharedUI.swift` | Flowback empty states show static SF Symbol + text, but lack actionable buttons (e.g. "Refresh Scan", "Add App", "Configure Policy"). | **P0** | Create reusable `EmptyStateView` with optional action button and secondary tip. | Every empty state provides a clear next action for the user. |
| **Status Badges & Indicators** | Communicate agent state (running, waiting, completed, failed) | `Sources/FlowbackUI/Common/StatusBadge.swift` | `Sources/Vorssaint/UI/Theme.swift` | Flowback `StatusBadge` has color, but lacks icon glyphs for users with color vision deficiencies and subtle pulse for running state. | **P0** | Add SF Symbol glyphs inside badge capsules (`checkmark`, `exclamationmark`, `arrow.triangle.2.circlepath`). | Badges are unambiguous without color perception (WCAG 1.4.1 compliance). |

---

## 2. Priority Ranking & Action Plan

1. **P0 (Critical Usability & Consistency):**
   - Centralize design system tokens (`Spacing`, `Typography`, `Radius`, `CardSurfaces`).
   - Reimplement `SettingsView` using modern macOS card layouts (`FlowbackSettingsCard` & `FlowbackSettingsRow`).
   - Refine `AgentsView` session list rows with tabular metadata and instant search clear.
   - Upgrade `StatusBadge` to include icon glyphs for accessible status identification.
   - Standardize `EmptyStateView` across all screens with recovery actions.
2. **P1 (High-Value Polish & Experience):**
   - Upgrade `OverviewView` metric stat cards with icon tiles and hoverable session cards.
   - Add quick-add suggested apps in `ApplicationsView`.
   - Add event category icons and decision visual styling to `SessionTimelineView`.
   - Polish `DiagnosticsView` subsystem rows.
3. **P2 (Secondary Refinements):**
   - Fine-tune sidebar row badges and menu bar icon rendering.
