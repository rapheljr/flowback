# Flowback Quick Start Guide

This guide gets you up and running with Flowback in less than 3 minutes.

---

## 1. Launch Flowback

After downloading and moving `Flowback.app` to `/Applications`:

```bash
open /Applications/Flowback.app
```

The Flowback compass icon will appear in your macOS menu bar.

---

## 2. Verify System Health

Run the diagnostic health check from your terminal:

```bash
flowback doctor
```

If Accessibility or Notification permissions have not yet been granted, macOS System Settings will prompt you, or you can grant them directly:
* **System Settings → Privacy & Security → Accessibility → Flowback [ON]**
* **System Settings → Notifications → Flowback [Allow]**

---

## 3. Verify Active Coding Agents

Flowback automatically discovers active coding agent sessions running on your system:

```bash
flowback status
flowback agents
```

If an Antigravity agent or Claude Code session is running in your editor or terminal, Flowback captures its origin context (Application bundle, window identifier, working directory, and start timestamp).

---

## 4. Test Intent-Aware Focus Restoration

To experience Flowback's intelligent attention arbitration:

1. Open your code editor (e.g. Visual Studio Code, Cursor, Windsurf) in a project directory.
2. Run a background agent command or emit a simulated test completion:
   ```bash
   flowback test-focus
   ```
3. Immediately switch to another application (such as Brave, Slack, or Notes) and:
   * **Test Case A (Active Typing):** Type continuously on your keyboard. Flowback detects system key events within the last 5 seconds, suppressing focus stealing and delivering an actionable macOS notification instead.
   * **Test Case B (Idle):** Hands off keyboard/mouse for 5 seconds. Flowback smoothly brings the origin editor window back to the foreground.

---

## 5. Enable Focus Lock When Deep in Thought

When in a meeting, presenting, or writing critical code where you do not want any window switching:

```bash
# Enable Focus Lock for 30 minutes
flowback focus-lock 30m

# Or toggle via the Menu Bar icon
```

During Focus Lock, window auto-restoration is silenced while notification banners remain active so you never lose context.
