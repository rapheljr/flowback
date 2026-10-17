# Agent Integrations & Providers

Flowback tracks coding agent sessions using dedicated provider adapters and the normalized Generic JSON Hook Protocol.

---

## Supported Providers Matrix

| Provider | Status | Mechanism | Hook Location / Lifecycle |
|---|---|---|---|
| **Google Antigravity** | **Supported** | Official JSON Hook | `~/.gemini/config/hooks.json` (`PreInvocation`, `PostInvocation`, `Stop` with `fullyIdle=true`) + live transcript scan |
| **Windsurf** | **Supported** | Official Cascade Hooks | `~/.codeium/windsurf/hooks.json` (`pre_user_prompt`, `post_cascade_response`, `pre_run_command`, etc.) + `~/.codeium/windsurf/transcripts/` |
| **OpenCode** | **Supported** | Official Plugin API | `~/.config/opencode/plugins/flowback.js` event subscriptions over authenticated local IPC |
| **Cursor Background Agent** | **Supported** | Cloud Agents API + Window Adapter | Remote `api.cursor.com/v1/agents` tracking, subagent hierarchy, repo/branch tracking + local window restoration |
| **Claude Code** | **Supported** | Process & Hook | Terminal process monitoring & hook callbacks |
| **OpenAI Codex** | **Supported** | Process & IPC | CLI process monitoring & status mapping |
| **Antigravity CLI** | **Supported** | Native Lifecycle Hooks (`agy`) | `~/.gemini/config/hooks.json` (`PreInvocation`, `PostInvocation`, `Stop`) + terminal restoration (formerly Gemini CLI) |
| **Aider** | **Supported** | Git / Terminal Hook | Notification & terminal watcher |
| **Generic Hook Protocol** | **Supported** | Unix Domain Socket | Emits schema v1 JSON over `~/.flowback/flowback.sock` |

---

## 1. Google Antigravity Integration

Flowback registers lifecycle hooks in `~/.gemini/config/hooks.json`:

```json
{
  "hooks": {
    "PreInvocation": [
      {
        "command": "/usr/local/bin/flowback hook antigravity --event PreInvocation"
      }
    ],
    "PostInvocation": [
      {
        "command": "/usr/local/bin/flowback hook antigravity --event PostInvocation"
      }
    ],
    "Stop": [
      {
        "command": "/usr/local/bin/flowback hook antigravity --event Stop"
      }
    ]
  }
}
```

### Proactive Discovery
In addition to hook events, Flowback includes proactive transcript scanning:
* Discovers active Antigravity conversations in `~/.gemini/antigravity-ide/brain/`.
* Tracks step progression and recognizes `USER_INPUT` prompts requiring human attention.
* Translates `fullyIdle=true` status into verified agent completion.

---

## 2. Antigravity CLI Integration (`agy`)

> **Note:** Google's Gemini CLI (`gemini`) is now the official Antigravity CLI (`agy`). Flowback provides first-class native lifecycle integration while maintaining full backward-compatibility for existing aliases (`gemini-cli`, `gemini`, `agy`).

* **Binary Detection:** Automatically detects `agy` (or `gemini`) in `/opt/homebrew/bin`, `/usr/local/bin`, and `PATH`.
* **Hooks Integration:** Shares lifecycle hook definitions in `~/.gemini/config/hooks.json` (`PreInvocation`, `PostInvocation`, `Stop`) with command: `flowback hook antigravity-cli`.
* **Proactive Discovery:** Scans active transcripts in `~/.gemini/antigravity-cli/brain/` and active lockfiles in `~/.gemini/antigravity-cli/presence/`.
* **Terminal Focus Restoration:** Restores focus directly to the terminal emulator running the session (Ghostty, Apple Terminal, iTerm2, Warp, Hyper, etc.) matching the workspace directory.

---

## 3. Windsurf Integration (Cascade Hooks)

Flowback integrates natively with Windsurf via official Cascade Hooks configured in `~/.codeium/windsurf/hooks.json`:

```json
{
  "hooks": {
    "pre_user_prompt": [
      {
        "command": "/usr/local/bin/flowback hook windsurf",
        "show_output": false
      }
    ],
    "post_cascade_response": [
      {
        "command": "/usr/local/bin/flowback hook windsurf",
        "show_output": false
      }
    ],
    "pre_run_command": [
      {
        "command": "/usr/local/bin/flowback hook windsurf",
        "show_output": false
      }
    ]
  }
}
```

* **Session Identity:** Preserves Cascade `trajectory_id` and `execution_id`.
* **Proactive Fallback:** Scans recent `.jsonl` session files in `~/.codeium/windsurf/transcripts/` without collecting sensitive code contents.
* **Window Restoration:** Supported by `WindsurfAdapter` targeting `com.codeium.windsurf`.

---

## 4. OpenCode Integration (Plugin Architecture)

Flowback provides a native OpenCode plugin installed to `~/.config/opencode/plugins/flowback.js`:

* **Subscription:** Listens to `ctx.event.subscribe` (`session.created`, `session.running`, `tool.execute.before`, `session.idle`, `session.deleted`).
* **Transport:** Emits structured events directly over the local Unix Domain Socket (`~/.flowback/flowback.sock`).
* **Session & Workspace Identity:** Retains OpenCode session and directory bindings.

---

## 5. Cursor Background Agent Integration

Flowback decouples local Cursor windows from cloud-hosted background agents:

* **Local Editor Focus:** `CursorAdapter` restores exact windows and workspace directory titles across `co.anysphere.cursor`, `com.todesktop.230313mzl4w4u92`, and `com.cursor.Cursor`.
* **Cloud Agents API:** `CursorBackgroundProvider` queries `https://api.cursor.com/v1/agents` using `CURSOR_API_KEY`:
  * Tracks statuses (`RUNNING`, `WAITING`, `CONFIRMATION_REQUIRED`, `COMPLETED`, `FAILED`).
  * Preserves repository URLs, branches, PR URLs, and hierarchical subagents (`parentAgentId`).
  * Restores local matching git workspace or opens PR dashboard navigation.
* **Credential Protection:** API keys are never written to logs or event metadata.

---

## 6. Generic Hook Protocol (v1 Schema)

Any custom CLI agent, CI runner, or developer script can integrate with Flowback by piping JSON events into `flowback emit`:

```bash
flowback emit '{
  "schemaVersion": 1,
  "event": "agent.completed",
  "provider": "my-custom-agent",
  "sessionId": "agent-session-42",
  "workspace": "/Users/username/src/project",
  "title": "Build Finished",
  "message": "All 12 microservices compiled successfully"
}'
```

### Standard Event Types:
* `agent.started`: Session launched; captures origin window ID.
* `agent.waiting`: Agent paused awaiting background task or timer.
* `agent.permission_required`: Agent blocked waiting for user authorization or command review. (Elevated priority).
* `agent.completed`: Agent finished its work. Triggers focus restoration or notification.
* `agent.failed`: Agent encountered fatal error or exception.
* `agent.cancelled`: Session terminated by user.
