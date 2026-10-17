# Flowback Product Roadmap

This roadmap outlines current deliverables, active development priorities, and planned future milestones for Flowback.

Status Legend:
* 🟢 **Completed & Verified**
* 🟡 **In Progress / Active Development**
* 🔵 **Planned (Next Milestones)**
* 🟣 **Exploratory / Research**

---

## Milestone 1.0.0 — Universal Core & Multi-Agent Focus Management 🟢

**Goal:** Deliver a rock-solid, production-ready macOS native foundation for agent session tracking and focus restoration.

* 🟢 **Native Engine:** 100% Swift 6 Concurrency, AppKit, SwiftUI, zero Electron, zero web servers.
* 🟢 **Official Agent Providers:**
  * Antigravity provider with proactive active transcript scanning, lifecycle hook execution (`fullyIdle=true`), and refresh triggers.
  * Claude Code provider with session detection.
  * OpenAI Codex provider.
  * Antigravity CLI (formerly Gemini CLI) & Aider integrations.
  * Generic JSON Hook Protocol v1 over Unix socket (`~/.flowback/flowback.sock`).
* 🟢 **Editor & Terminal Adapters:**
  * VS Code, VS Code Insiders, Code OSS, Windsurf, VSCodium, Positron, Trae, and Cursor.
  * Apple Terminal, iTerm2, Kitty, Alacritty, Ghostty, Warp.
* 🟢 **Focus Engine & Attention Arbiter:**
  * User Intent Engine sensing system idle via `CGEventSource` (suppressing focus stealing if user typed within 5 seconds).
  * Priority ordering (`permissionRequired` > `failure` > `completed` > `waiting` > `informational`).
  * 1000ms focus cooldown to eliminate window thrashing.
  * Multi-agent completion aggregation into single digestible notifications.
* 🟢 **Persistence & Recovery:**
  * SQLite WAL mode at `~/.flowback/flowback.sqlite`.
  * Startup reconciliation & crash recovery.
* 🟢 **Interface & Ergonomics:**
  * Status bar menu item with quick ⌘1–⌘9 session restoration and Focus Lock controls.
  * Native SwiftUI Dashboard with live Session Timeline, Provider Diagnostics, and Settings.
  * Full CLI `flowback` (`doctor`, `status`, `refresh`, `focus-lock`, `emit`, `test-focus`).

---

## Milestone 1.1.0 — Enhanced Multi-Display & Ecosystem Integration 🔵

**Target:** Q4 2026

* 🔵 **Multi-Monitor Display Pinning:** Remember which physical display and virtual Space each agent session originated on and optionally restrict focus switching to the active monitor.
* 🔵 **Official Homebrew Cask:** Direct distribution via `brew install --cask flowback`.
* 🔵 **Terminal Tab & Pane Deep Links:** Deeper tab/pane restoration for Ghostty and iTerm2 via AppleScript / Apple Events dictionaries.
* 🔵 **Custom Notification Audio Chimes:** Optional subtle macOS sound cues per priority level (e.g., distinct chime for `permissionRequired` vs. `completed`).

---

## Milestone 1.2.0 — Multi-Agent Session Grouping & Advanced Policies 🔵

**Target:** Q1 2027

* 🔵 **Workspace Grouping Presets:** Group parallel agents working on the same repository (e.g. backend worker + frontend worker) and restore both editor and browser simultaneously.
* 🔵 **Scheduled Focus Lock:** Time-based Focus Lock schedules (e.g. "Do Not Disturb focus during calendar events").
* 🔵 **Custom External Webhook Actions:** Option to trigger a local custom script when a session completes or requires permission.

---

## Milestone 2.0.0 — Exploratory / Future Directions 🟣

* 🟣 **Custom Out-of-Process Provider Sidecars:** Allow developers to author providers in Python, TypeScript, or Go communicating via a lightweight POSIX FIFO without recompiling Flowback.
* 🟣 **Cross-Platform Linux Support:** Headless background daemon (`flowbackd`), Freedesktop D-Bus notifications, X11 EWMH / Wayland (`xdg-activation-v1`, Hyprland, Sway) focus restoration drivers, and systemd user services ([#7](https://github.com/rapheljr/flowback/issues/7)).
* 🟣 **Swift Testing Migration:** Adopt native `swift-testing` once upstream tooling and Command Line Tools fully standardize framework availability across all macOS environments.

