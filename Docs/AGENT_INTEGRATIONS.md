# Agent Integrations & Providers

Flowback tracks coding agent sessions using dedicated provider adapters and the normalized Generic JSON Hook Protocol.

---

## Supported Providers Matrix

| Provider | Status | Mechanism | Hook Location / Lifecycle |
|---|---|---|---|
| **Google Antigravity** | **Supported** | Official JSON Hook | `~/.gemini/config/hooks.json` (`PreInvocation`, `PostInvocation`, `Stop` with `fullyIdle=true`) + live transcript scan |
| **Claude Code** | **Supported** | Process & Hook | Terminal process monitoring & hook callbacks |
| **OpenAI Codex** | **Supported** | Process & IPC | CLI process monitoring & status mapping |
| **Gemini CLI** | **Supported** | Command Hook | Shell wrapper & post-execution callback |
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

## 2. Generic Hook Protocol (v1 Schema)

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
