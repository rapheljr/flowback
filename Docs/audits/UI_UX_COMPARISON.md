# Flowback × Vorssaint — Side-by-Side UI/UX Comparison Report

**Date:** October 2026  
**Auditor:** Principal macOS Product Designer & Senior SwiftUI Engineer  
**Reference Repository:** `vorssaint-utils` (Strictly Read-Only Reference)  
**Target Repository:** `flowback`  

---

## 1. Executive Summary

A thorough architectural and visual comparison between Flowback and Vorssaint reveals that while Flowback has a robust domain model, high-performance concurrency architecture, and comprehensive backend orchestration, its user interface was previously constructed using standard boilerplate SwiftUI components (`Form`, `.grouped`, unstyled `List` rows).

In contrast, Vorssaint achieves an exceptionally refined native macOS aesthetic through:
1. **Cohesive Card-Based Layouts:** Content is grouped into rounded cards (`cornerRadius: 12-16pt`) with continuous curvature, subtle borders that adapt to system contrast settings, and restrained translucent surface fills.
2. **Icon Tiles & Semantic Visual Anchors:** Settings rows and list items feature dedicated icon tiles (24x24 to 28x28 pt) with subtle tinting, giving users immediate visual orientation.
3. **Tabular Density & Scannable Hierarchy:** Metadata (durations, provider names, process IDs, workspace paths) are aligned on a clean typographic baseline with monospaced numbers.
4. **Resilient Interaction Feedback:** Every button, toggle, and text field provides immediate visual feedback, explicit confirmation dialogs for destructive actions, and actionable empty states.

---

## 2. Detailed Gap Analysis by Surface

### 2.1 Settings & Policy Configuration

| Dimension | Flowback Baseline | Vorssaint Reference | User Impact | Priority | Proposed Flowback Improvement |
| :--- | :--- | :--- | :--- | :---: | :--- |
| **Container & Hierarchy** | Standard SwiftUI `.grouped` `Form`. Creates narrow centered bands with large gray margins. | Custom `SettingsCard` with 16pt corner radius, headline title, and 16pt internal padding. | High: Flowback settings look like an unstyled iPad app port rather than a premium macOS utility. | **P0** | Implement `FlowbackSettingsCard` using `RoundedRectangle(cornerRadius: 14, style: .continuous)` and adaptive surface fills. |
| **Row Alignment** | Standard label-to-control layout with inconsistent slider widths (180pt vs 280pt). | Standardized `SettingsRow` with 28x28pt icon tile, title, badge, secondary caption, and right-aligned control. | Medium: Eye travels erratically across inconsistent control baselines. | **P0** | Implement `FlowbackSettingsRow` with standard icon tiles, title, explanatory caption, and right accessory slot. |
| **Feedback on Save** | Tiny text line at bottom of form: "Preferences apply and save automatically." | Clear checkmark state badge with subtle transition and manual trigger. | Low: User is unsure whether slider adjustments persisted to SQLite. | **P1** | Add persistent footer with animated save confirmation badge. |

---

### 2.2 Agent Session List & Discovery

| Dimension | Flowback Baseline | Vorssaint Reference | User Impact | Priority | Proposed Flowback Improvement |
| :--- | :--- | :--- | :--- | :---: | :--- |
| **Row Structure** | Plain SwiftUI `List` row. Four lines of stacked text with small bullet separators. | Structured multi-column card row with distinct visual boundaries, hover highlight, and quick action. | High: Difficult to scan when 10+ sessions are listed. | **P0** | Restructure session rows into card components with provider icon tile, title, project tag, duration, and focus button. |
| **Search Interaction** | Text field filters in real-time, but has no result counter and no escape-key clear. | Search input with clear button, query result count, and keyboard shortcut focus. | Medium: User cannot quickly clear or dismiss search with keyboard. | **P1** | Add result count chip ("Showing 3 of 12 sessions") and escape shortcut handling. |
| **Shared Repository Badge** | Tiny text with orange background: "Shared Repo". | Prominent capsule tag with icon indicator explaining that multiple agents are operating in the same workspace. | Medium: High visual noise without clear explanation. | **P1** | Replace with `Label("Shared Workspace", systemImage: "folder.badge.gearshape")` capsule. |

---

### 2.3 Overview & Live Metrics

| Dimension | Flowback Baseline | Vorssaint Reference | User Impact | Priority | Proposed Flowback Improvement |
| :--- | :--- | :--- | :--- | :--- | :---: |
| **Stat Cards** | `StatCard` uses `Color(NSColor.controlBackgroundColor)` with 12pt radius. Visual weight is flat. | Metric cards with subtle gradient borders, colored glyph tiles, and bold rounded typography. | Medium: Overview feels plain and lacks visual hierarchy. | **P1** | Upgrade `StatCard` to use `ThemeTokens.cardFill`, colored background glyph tiles, and dynamic contrast stroke. |
| **Attention Queue** | Plain orange rectangle banner. | Polished notification card with severity icon, action button, and timestamp. | High: Critical attention requests blend into secondary content. | **P0** | Redesign attention requests into prominent warning cards with "Review & Focus" button. |

---

### 2.4 Status Badges & Accessibility

| Dimension | Flowback Baseline | Vorssaint Reference | User Impact | Priority | Proposed Flowback Improvement |
| :--- | :--- | :--- | :--- | :--- | :---: |
| **Color Dependency** | Colored text + capsule border. Relies solely on color perception to distinguish states. | Color + icon symbol + high-contrast stroke adapting to system settings. | High: Fails WCAG 1.4.1 (Use of Color) for users with deuteranopia / protanopia. | **P0** | Add distinct SF Symbol glyphs inside `StatusBadge` (e.g. `arrow.triangle.2.circlepath` for running, `checkmark` for completed, `exclamationmark` for failed). |
| **High Contrast Mode** | High-contrast border width increases from 0.7 to 1.2pt. | Border opacity increases and fill color adjusts for maximum legibility. | Medium: Border alone was insufficient in light mode. | **P1** | Adjust fill brightness and stroke opacity in `ThemeTokens`. |

---

### 2.5 Empty States & Failure Recovery

| Dimension | Flowback Baseline | Vorssaint Reference | User Impact | Priority | Proposed Flowback Improvement |
| :--- | :--- | :--- | :--- | :--- | :---: |
| **Actionability** | Static SF Symbol + "No sessions found" text. No action button. | Illustrated empty state with descriptive paragraph and primary action button (e.g. "Check Configuration" or "Refresh"). | High: User reaches an empty state and has no obvious next step. | **P0** | Implement reusable `FlowbackEmptyState` component with icon, title, description, and primary/secondary action buttons. |

---

## 3. Acceptance Criteria for UI/UX Parity

1. **Design System:** All views consume unified tokens from `ThemeTokens.swift` (colors, spacing, corner radius, borders).
2. **Settings Window:** Grouped into clear `FlowbackSettingsCard` containers with icon tiles and consistent slider baselines.
3. **Session List:** Clear visual hierarchy, provider icon tiles, status badges with accessible glyphs, and responsive search.
4. **Accessibility:** Passes WCAG AA contrast standards (minimum 4.5:1 text contrast, non-color status identification).
5. **Native macOS Behavior:** Smooth resizing, keyboard shortcuts (`⌘1`..`⌘6`, `⌘R`, Escape), and full support for Dark Mode and Increase Contrast.
