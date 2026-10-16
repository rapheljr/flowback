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
        "agent.idle",
        "session.context_changed",
        "session.disappeared"
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
        "windowTitle": { "type": "string" },
        "workspacePath": { "type": "string" },
        "provenance": {
          "type": "string",
          "enum": ["native_hook", "provider_transcript", "system_frontmost", "ipc_explicit", "inferred"]
        },
        "confidence": {
          "type": "number",
          "minimum": 0.0,
          "maximum": 1.0
        },
        "restorationCapability": {
          "type": "string",
          "enum": ["exact_window_and_workspace", "workspace_window", "app_activation_only", "notification_fallback_only", "unsupported"]
        },
        "capturedAt": { "type": "string", "format": "date-time" }
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

| Protocol Event String | Normalized Internal `AgentEventType` | Default Focus Impact | Actionable for Attention |
|---|---|---|---|
| `agent.started` | `.agentStarted` | Origin context captured | No |
| `agent.running` | `.agentRunning` | Session marked active | No |
| `agent.waiting` | `.agentWaiting` | Priority: waiting (user input required) | **Yes** |
| `agent.permission_required` | `.agentPermissionRequired` | Priority: permissionRequired (high) | **Yes** |
| `agent.progress` | `.agentProgress` | Timeline progress record | No |
| `agent.completed` | `.agentCompleted` | Focus evaluation evaluated | **Yes** |
| `agent.failed` | `.agentFailed` | Priority: failure (high) | **Yes** |
| `agent.cancelled` | `.agentCancelled` | Session cleanly closed | No |
| `agent.stopped` | `.agentStopped` | Check for `fullyIdle` | No |
| `agent.idle` | `.agentIdle` | Provider idle signal | **Yes** |
| `session.context_changed` | `.sessionContextChanged` | Updates session active window/path | No |
| `session.disappeared` | `.sessionDisappeared` | Cleanly marks session dead | No |

---

## Security, Validation & Safety Rules

1. **Peer Authentication (`getpeereid`):** The Unix socket enforces that connecting client process UID matches `getuid()` of the running Flowback daemon. Non-matching UIDs receive immediate access denial.
2. **Strict Payload Bounds:** Maximum IPC payload size is strictly capped at **2MB** (`maxPayloadSize = 2 * 1024 * 1024`) to eliminate memory exhaustion and buffer overflow risks.
3. **Socket Timeouts:** Both `SO_RCVTIMEO` and `SO_SNDTIMEO` are enforced at 5.0 seconds.
4. **Duplicate Daemon Protection:** Prior to binding, Flowback probes for an active listening socket. If an instance is alive, bind fails with `EADDRINUSE`. Stale socket files from ungraceful host power cuts are safely removed.
5. **Schema Version Check:** If `schemaVersion != 1`, the event is rejected with an explanatory error.
6. **Deduplication:** Events with identical hash (`provider + sessionID + event + timestamp_bucket`) arriving within 500ms are safely discarded.
7. **Stale/Out-of-Order Rejection:** Events carrying timestamps older than the session's recorded update time (with a 2-second skew tolerance) are dropped to prevent stale focus switches.
8. **Idempotence:** Sending multiple `agent.completed` events will not trigger multiple focus switches.
9. **Sanitization:** Metadata strings containing binary data or exceeding 64KB are rejected.

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
