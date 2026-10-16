# Flowback CLI Reference Manual

The `flowback` command-line tool communicates with the running Flowback daemon over the local Unix domain socket (`~/.flowback/flowback.sock`).

---

## Global Syntax

```bash
flowback [command] [options]
```

---

## Commands

### `flowback status`
Displays active agent sessions, focus lock status, and background daemon health:
```bash
$ flowback status
● Flowback Daemon: Active (PID 48201)
  Database: Connected (~/.flowback/flowback.sqlite)
  Focus Lock: Inactive

Active Agent Sessions: 2
  [1] Antigravity — /Users/username/src/matchday (Running, 4m20s)
  [2] Claude Code — /Users/username/src/payment-service (Waiting, 1m12s)
```

---

### `flowback doctor`
Executes comprehensive diagnostics on permissions, SQLite WAL integrity, socket connection, and provider hooks:
```bash
$ flowback doctor
=== Flowback Doctor Diagnostics ===
✓ Operating System: macOS 14.0+ supported
✓ Accessibility Permission: Granted
✓ Notification Permission: Authorized
✓ Database: Connected (~/.flowback/flowback.sqlite)
✓ IPC Socket: Active (~/.flowback/flowback.sock)
✓ Event Bus: Operational
✓ Focus Controller: Ready
```

---

### `flowback refresh`
Forces an immediate proactive scan of all registered providers and active transcripts:
```bash
$ flowback refresh
Proactive scan triggered across 6 providers. Found 2 active sessions.
```

---

### `flowback agents`
Lists detailed state and origin context for all active and recently completed sessions:
```bash
$ flowback agents
SESSION ID   PROVIDER     STATUS    ORIGIN APP       WORKSPACE
sess-482a    antigravity  running   com.google.ide   /Users/username/src/flowback
sess-910b    claude-code  waiting   com.apple.term   /Users/username/src/api
```

---

### `flowback focus-lock [duration]`
Temporarily silences automatic window restoration while keeping notifications active:
```bash
# Lock focus for 30 minutes
flowback focus-lock 30m

# Supported durations: 15m, 30m, 45m, 1h, 2h, indefinite
```

### `flowback focus-unlock`
Disables Focus Lock and re-enables normal automatic focus restoration:
```bash
flowback focus-unlock
```

---

### `flowback emit [json_payload]`
Emits a raw agent lifecycle event adhering to schema version 1:
```bash
flowback emit '{"schemaVersion":1,"event":"agent.completed","provider":"custom","sessionId":"s1","workspace":"/Users/user/repo"}'
```

---

### `flowback test-focus`
Triggers a simulation test: captures your current window and tests intent-aware focus restoration:
```bash
flowback test-focus
```

---

### `flowback test-notification`
Verifies macOS UserNotifications delivery by sending an immediate test banner with interactive buttons:
```bash
flowback test-notification
```

---

### `flowback hook [provider] [--install | --uninstall]`
Manages lifecycle hook injection for specific agents:
```bash
# Install Antigravity lifecycle hooks
flowback hook antigravity --install

# Remove Antigravity hooks cleanly
flowback hook antigravity --uninstall
```
