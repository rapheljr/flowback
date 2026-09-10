# Flowback Local Event Protocol (v1 Schema)

The Generic Hook Protocol allows any external agent, CLI tool, shell script, or IDE plugin to feed lifecycle events into Flowback over a local Unix domain socket.

---

## Socket Location

```text
~/.flowback/flowback.sock
```

The socket is accessible only to processes running under the current user's UID (permissions `0600`).

---

## JSON Schema (v1)

```json
{
  "$schema": "https://json-schema.org/draft/2020-12/schema",
  "title": "FlowbackGenericEvent",
  "type": "object",
  "required": [
    "schemaVersion",
    "event",
    "provider",
    "sessionId",
    "timestamp"
  ],
  "properties": {
    "schemaVersion": {
      "type": "integer",
      "minimum": 1,
      "maximum": 1
    },
    "event": {
      "type": "string",
      "enum": [
        "agent.started",
        "agent.running",
        "agent.waiting",
        "agent.permission_required",
        "agent.progress",
        "agent.completed",
        "agent.failed",
        "agent.cancelled",
        "agent.stopped",
        "agent.idle"
      ]
    },
    "provider": {
      "type": "string",
      "minLength": 1
    },
    "sessionId": {
      "type": "string",
      "minLength": 1
    },
    "taskId": {
      "type": "string"
    },
    "workspace": {
      "type": "string"
    },
    "origin": {
      "type": "object",
      "properties": {
        "bundleId": { "type": "string" },
        "pid": { "type": "integer" },
        "windowId": { "type": "integer" },
        "windowTitle": { "type": "string" }
      }
    },
    "timestamp": {
      "type": "string",
      "format": "date-time"
    },
    "metadata": {
      "type": "object",
      "additionalProperties": true
    }
  }
}
```

---

## Event Normalization Mapping

| Protocol Event String | Normalized Internal `AgentEventType` | Default Focus Impact |
|---|---|---|
| `agent.started` | `.agentStarted` | Origin context captured |
| `agent.running` | `.agentRunning` | Session marked active |
| `agent.waiting` | `.agentWaiting` | Priority: waiting |
| `agent.permission_required` | `.agentPermissionRequired` | Priority: permissionRequired (high) |
| `agent.progress` | `.agentProgress` | Timeline progress record |
| `agent.completed` | `.agentCompleted` | Focus evaluation evaluated |
| `agent.failed` | `.agentFailed` | Priority: failure (high) |
| `agent.cancelled` | `.agentCancelled` | Session cleanly closed |
| `agent.stopped` | `.agentStopped` | Check for `fullyIdle` |
| `agent.idle` | `.agentIdle` | Provider idle signal |

---

## Validation & Safety Rules

1. **Schema Version Check:** If `schemaVersion != 1`, the event is rejected with `INVALID_SCHEMA_VERSION`.
2. **Deduplication:** Events with identical hash (`provider + sessionID + event + timestamp_bucket`) arriving within 500ms are safely discarded.
3. **Idempotence:** Sending multiple `agent.completed` events will not trigger multiple focus switches.
4. **Sanitization:** Metadata strings containing binary data or exceeding 64KB are rejected.

---

## Example Usage

### Via Flowback CLI
```bash
flowback emit agent.completed \
    --provider custom-linter \
    --session lint-982 \
    --workspace /Users/abin/workspace/projects/focus-switcher
```

### Via Bash / `nc -U`
```bash
cat << 'EOF' | nc -U ~/.flowback/flowback.sock
{
  "command": "emit",
  "params": {
    "schemaVersion": 1,
    "event": "agent.completed",
    "provider": "my-agent",
    "sessionId": "task-500",
    "workspace": "/Users/abin/workspace/projects/my-app",
    "timestamp": "2026-09-10T14:30:00Z"
  }
}
EOF
```
