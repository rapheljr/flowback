# Flowback Product Roadmap

This roadmap outlines current deliverables, active development priorities, and planned future milestones for Flowback.

Status Legend:
* 🟢 **Completed & Verified**
* 🟡 **In Progress / Active Development**
* 🔵 **Planned (Next Milestones)**
* 🟣 **Exploratory / Research**

---

## Completed Pre-1.0 Milestones (v0.0.1 – v0.4.0) 🟢

**Goal:** Establish a rock-solid, production-ready macOS native foundation for agent session tracking and focus restoration across rapid pre-1.0 iterations.

* 🟢 **v0.0.1 (Prototype):** Multi-chunk Unix domain socket IPC, SQLite transient memory safety, and proactive Antigravity process discovery.
* 🟢 **v0.1.0 (Core Engine):** Deterministic 12-step focus engine, process liveness protection, headless daemon/CLI flags, and socket security.
* 🟢 **v0.2.0 (Provider Expansion):** Native background agent integrations for Windsurf, OpenCode, Cursor, and official Antigravity CLI (`agy`).
* 🟢 **v0.3.0 (Intelligence & Scale):** Conversation-aware event resolution, SQLite Schema v2 with migration runner, and 1,000-event burst UI coalescing.
* 🟢 **v0.4.0 (Design System & Destinations — Current):** macOS Card Design System with HIG/WCAG AA compliance, Copilot provider, General Sidebar Destinations, and canonical metadata.

---

## Milestone 0.5.0 — Enhanced Multi-Display & Ecosystem Integration 🔵

**Target:** Q4 2026

* 🔵 **Multi-Monitor Display Pinning:** Remember which physical display and virtual Space each agent session originated on and optionally restrict focus switching to the active monitor.
* 🔵 **Official Homebrew Cask:** Direct distribution via `brew install --cask flowback`.
* 🔵 **Terminal Tab & Pane Deep Links:** Deeper tab/pane restoration for Ghostty and iTerm2 via AppleScript / Apple Events dictionaries.
* 🔵 **Custom Notification Audio Chimes:** Optional subtle macOS sound cues per priority level (e.g., distinct chime for `permissionRequired` vs. `completed`).

---

## Milestone 0.6.0 — Multi-Agent Session Grouping & Advanced Policies 🔵

**Target:** Q1 2027

* 🔵 **Workspace Grouping Presets:** Group parallel agents working on the same repository (e.g. backend worker + frontend worker) and restore both editor and browser simultaneously.
* 🔵 **Scheduled Focus Lock:** Time-based Focus Lock schedules (e.g. "Do Not Disturb focus during calendar events").
* 🔵 **Custom External Webhook Actions:** Option to trigger a local custom script when a session completes or requires permission.

---

## Milestone 1.0.0 — Production API Freeze & Future Directions 🟣

* 🟣 **API & Schema Stability:** Formal freeze of public CLI commands, JSON hook schemas, and database formats.
* 🟣 **Custom Out-of-Process Provider Sidecars:** Allow developers to author providers in Python, TypeScript, or Go communicating via a lightweight POSIX FIFO without recompiling Flowback.
* 🟣 **Cross-Platform Linux Support:** Headless background daemon (`flowbackd`), Freedesktop D-Bus notifications, X11 EWMH / Wayland (`xdg-activation-v1`, Hyprland, Sway) focus restoration drivers, and systemd user services ([#7](https://github.com/rapheljr/flowback/issues/7)).
* 🟣 **Swift Testing Migration:** Adopt native `swift-testing` once upstream tooling and Command Line Tools fully standardize framework availability across all macOS environments.

