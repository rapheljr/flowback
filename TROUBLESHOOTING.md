# Flowback Troubleshooting Guide

---

## 1. Running Flowback Doctor

The first step in diagnosing any issue is running `flowback doctor` in your terminal:

```bash
flowback doctor
```

Example healthy output:
```text
=== Flowback Doctor Diagnostics ===
✓ Operating System: macOS 14.0+ supported
✓ Accessibility Permission: Granted
✓ Notification Permission: Authorized
✓ Database: Connected (~/.flowback/flowback.sqlite)
✓ IPC Socket: Active (~/.flowback/flowback.sock)
✓ Event Bus: Operational
✓ Focus Controller: Ready

--- Provider Integrations ---
[Antigravity]
  Installed: YES
  Hook Registered: YES
  Hook Executable: YES
  Recent Events: 14 received

[Claude Code]
  Installed: YES
  Hook Registered: YES

[OpenAI Codex]
  Installed: NO (Optional)
```

---

## 2. Common Issues & Solutions

### Issue A: Windows don't raise; only the application activates
* **Cause:** Accessibility permission is not granted. macOS requires Accessibility permissions to raise background windows without switching applications blindly.
* **Solution:**
  1. Open **System Settings** → **Privacy & Security** → **Accessibility**.
  2. Ensure **Flowback** is toggled **ON**.
  3. Alternatively, click **Request Permission** in the Flowback Dashboard Diagnostics tab.

---

### Issue B: Notifications are not appearing
* **Cause:** Notifications disabled in macOS System Settings or Focus / Do Not Disturb is active.
* **Solution:**
  1. Open **System Settings** → **Notifications** → **Flowback**.
  2. Ensure **Allow Notifications** is enabled with **Alerts** or **Banners**.
  3. Run `flowback test-notification` to verify delivery.

---

### Issue C: Antigravity agent completes but Flowback doesn't react
* **Cause:** Hook is not installed in `~/.gemini/config/hooks.json`.
* **Solution:**
  1. Check if the hook is installed:
     ```bash
     cat ~/.gemini/config/hooks.json
     ```
  2. Reinstall the hook via CLI or Dashboard:
     ```bash
     flowback hook antigravity --install
     ```
  3. Or click **Repair Integration** under Antigravity in the Flowback Dashboard.

---

### Issue D: "Socket connection refused" from CLI
* **Cause:** Flowback application is not running or socket was left in a stale state after an ungraceful shutdown.
* **Solution:**
  1. Check if Flowback is running:
     ```bash
     pgrep Flowback
     ```
  2. If not running, launch Flowback:
     ```bash
     open -a Flowback || ./.build/release/Flowback &
     ```
  3. If running but socket is unresponsive, clean stale socket:
     ```bash
     rm -f ~/.flowback/flowback.sock
     ```

---

### Issue E: Windows on other Spaces do not activate
* **Cause:** Flowback's default Space policy is `neverSwitchSpaces` to avoid disorienting desktop jumping.
* **Solution:**
  * Open Flowback **Settings** → **macOS Spaces Policy** and set to **Allow Space Switching** or **Activate Application Only**.

---

### Issue F: Database Corruption / Fresh Start
* **Recovery:** Flowback automatically detects corrupted databases, backs up the corrupted file to `flowback.sqlite.corrupt.<timestamp>`, and starts a fresh database with schema version 1.
* **Manual Reset:**
  ```bash
  rm -f ~/.flowback/flowback.sqlite*
  ```
