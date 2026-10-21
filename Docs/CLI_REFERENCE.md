# Flowback CLI Reference Manual

The `flowback` command-line companion communicates with the running Flowback daemon over the local Unix domain socket (`~/.flowback/flowback.sock`).

---

## Global Syntax

```bash
flowback <command> [arguments]
```

### Global Options:
* `flowback help`, `flowback -h`, `flowback --help` — Display CLI usage and command list.
* `flowback version`, `flowback -v`, `flowback --version` — Print current version and build number.

---

## Commands

### `flowback status`
Displays background daemon health, database connection, focus lock state, and active agent summary:
```bash
$ flowback status
Flowback Status: Flowback is running
----------------------------------------
  activeSessionsCount: 2
  focusLockActive: false
  providersConfigured: 10
  status: online
```

---

### `flowback refresh`
Forces an immediate proactive scan across all registered agent providers and active session transcripts:
```bash
$ flowback refresh
Proactive scan completed.
Active Agents:
  • [running] antigravity — flowback
  • [waiting] claude-code — api-service
```

---

### `flowback agents`
Lists currently active agent sessions with provider, workspace, elapsed duration, and origin process information:
```bash
$ flowback agents
Found 2 active sessions
• [running] antigravity — flowback (Started: 4m 12s ago)
    Origin: Visual Studio Code (PID: 34120)
• [waiting] claude-code — api-service (Started: 1m 05s ago)
    Origin: Terminal (PID: 49210)
```

---

### `flowback sessions`
Lists the 20 most recent agent sessions with their states, provider, project name, session ID prefix, and origin label:
```bash
$ flowback sessions
Found 8 recent sessions
• [completed] antigravity — flowback [ID: 733f120f]
    Origin: Visual Studio Code
• [completed] windsurf — frontend [ID: 9a8b7c6d]
    Origin: Windsurf
• [failed] claude-code — payment-service [ID: 1e2d3c4b]
    Origin: iTerm2
```

---

### `flowback doctor` / `flowback providers`
Runs comprehensive diagnostics on permissions, SQLite WAL database, socket health, and provider integrations.

#### Online Mode (when Flowback is running):
```bash
$ flowback doctor
========================================
Flowback Doctor Diagnostics
========================================

Permissions:
  ✓ accessibility
  ✓ notifications

Agent Providers:
  ✓ Antigravity [native-lifecycle]: Google Antigravity IDE detected
  ✓ Antigravity CLI [native-lifecycle]: Antigravity CLI (agy) found at /opt/homebrew/bin/agy
  ✓ Windsurf [native-lifecycle]: Windsurf Cascade hooks installed
  ✓ OpenCode [native-lifecycle]: OpenCode plugin active
  ✓ Cursor Background [adapter]: Local Cursor editor detected
  ✓ GitHub Copilot [adapter]: GitHub Copilot environment detected
  ✓ Claude Code [adapter]: Claude Code CLI found at /usr/local/bin/claude
  ✓ OpenAI Codex [adapter]: Ready
  ✓ Aider [adapter]: Ready
  ✓ Generic Hook [generic-protocol]: Socket listener ready
```

#### Offline Diagnostic Mode (when daemon is not running):
If the daemon is offline, `flowback doctor` inspects local filesystem state, database files, hook registrations, and PATH binaries:
```bash
$ flowback doctor
========================================
Flowback Doctor Diagnostics (Offline)
========================================
Status: Flowback daemon is not currently running.
Socket: ~/.flowback/flowback.sock [Not Connected]

Local Filesystem & Storage:
  ✓ State directory: ~/.flowback
  ✓ Database store: ~/.flowback/flowback.sqlite

Provider Hook Configurations:
  ✓ Antigravity hooks: ~/.gemini/config/hooks.json
  ✓ OpenCode plugin: ~/.config/opencode/plugins/flowback.js

Developer CLI Tools:
  ✓ Antigravity CLI (agy): /opt/homebrew/bin/agy
  ✓ Claude Code (claude): /usr/local/bin/claude
  ✓ OpenCode (opencode): /opt/homebrew/bin/opencode

Run 'open -a Flowback' or launch the Flowback app to start the daemon.
```

---

### `flowback focus [session-id]`
Manually restores focus to the origin window and workspace of the specified session (or frontmost active session if omitted):
```bash
flowback focus 733f120f-02e0-4c23-bab1-142635d3ecc9
```

---

### `flowback focus-lock [duration]`
Enables, sets, or toggles Focus Lock mode to temporarily silence automatic window switching while keeping notifications active.

```bash
# Lock focus for 30 minutes
flowback focus-lock 30m

# Supported preset durations: 15m, 30m, 45m, 1h, 2h, indefinite
flowback focus-lock 1h

# Disengage Focus Lock (re-enable auto-restoration):
flowback focus-lock off

# Toggle Focus Lock state:
flowback focus-lock
```

---

### `flowback config [export [file] | import <file>]`
Exports or imports Flowback policy configurations (`PolicyConfiguration`) in JSON format:

```bash
# Export active configuration to stdout:
flowback config export

# Export active configuration to a file:
flowback config export my-settings.json

# Import configuration from a file:
flowback config import my-settings.json
```

See [CONFIGURATION.md](CONFIGURATION.md) for full configuration schema and override options.

---

### `flowback hook <provider>`
Receives agent lifecycle hook payloads over `stdin` (for Google Antigravity, Antigravity CLI, Windsurf, etc.) and emits appropriate hook response decisions.
If the Flowback daemon is temporarily offline, `flowback hook` degrades safely and outputs a permissive response (`{"decision":"allow"}` or `{"injectSteps":[]}`), ensuring your coding agent is never blocked.

```bash
# Example invocation by Antigravity in ~/.gemini/config/hooks.json:
/usr/local/bin/flowback hook antigravity
```

---

### `flowback emit <json>`
Emits a raw agent lifecycle event adhering to schema version 1 directly into Flowback:
```bash
flowback emit '{
  "schemaVersion": 1,
  "event": "agent.completed",
  "provider": "custom-agent",
  "sessionId": "task-42",
  "workspace": "/Users/username/src/my-project",
  "timestamp": "2026-10-18T14:30:00Z"
}'
```

---

### `flowback test-focus`
Simulates a focus restoration evaluation on your frontmost application, logging the intent engine decision and explanation:
```bash
flowback test-focus
```

---

### `flowback test-notification`
Dispatches an interactive test macOS notification banner with `[Focus]` and `[Review]` action buttons:
```bash
flowback test-notification
```

---

### `flowback quit` / `flowback shutdown`
Requests a graceful shutdown of the background Flowback daemon:
```bash
flowback quit
```

