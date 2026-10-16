# Flowback Configuration & Policies

Flowback uses a multi-tier policy resolution engine allowing granular focus management defaults and overrides.

---

## Configuration Location

Flowback stores user settings in:
```text
~/.flowback/config.json
```
And session metadata in SQLite (WAL mode):
```text
~/.flowback/flowback.sqlite
```

---

## Policy Resolution Hierarchy

When an agent event arrives, Flowback computes the active focus behavior using a 4-tier resolution hierarchy:

```text
Workspace Override  (Highest Priority: specific repo path)
       ↓
Application Override (Target Editor / Terminal bundle ID)
       ↓
Provider Override    (Antigravity, Claude Code, Codex, Generic)
       ↓
Global Defaults      (Lowest Priority: general system settings)
```

---

## Example `config.json`

```json
{
  "global": {
    "idleThresholdSeconds": 5.0,
    "cooldownDurationMs": 1000,
    "aggregationWindowSeconds": 1.5,
    "spacesPolicy": "neverSwitchSpaces",
    "restoreFullscreen": false,
    "soundEnabled": true
  },
  "providers": {
    "antigravity": {
      "autoRestoreOnCompletion": true,
      "requirePermissionImmediateFocus": true,
      "proactiveTranscriptScanning": true
    },
    "claude-code": {
      "autoRestoreOnCompletion": true,
      "requirePermissionImmediateFocus": true
    }
  },
  "workspaces": {
    "/Users/username/src/critical-prod-repo": {
      "autoRestoreOnCompletion": false,
      "notificationOnly": true
    }
  },
  "applications": {
    "com.google.antigravity-ide": {
      "restoreStrategy": "exactWindowId"
    },
    "com.microsoft.VSCode": {
      "restoreStrategy": "workspaceTitleMatch"
    }
  }
}
```

---

## Setting Parameters

| Parameter | Type | Default | Description |
|---|---|---|---|
| `idleThresholdSeconds` | Float | `5.0` | Minimum system idle duration before auto-focusing origin window. |
| `cooldownDurationMs` | Int | `1000` | Window (in milliseconds) preventing rapid repeated window switches. |
| `aggregationWindowSeconds` | Float | `1.5` | Sliding window for grouping multiple simultaneous completions. |
| `spacesPolicy` | String | `neverSwitchSpaces` | Options: `neverSwitchSpaces`, `allowSpaceSwitching`, `activateAppOnly`. |
| `restoreFullscreen` | Bool | `false` | If true, permits switching to full-screen spaces. |
| `soundEnabled` | Bool | `true` | Play system notification chimes on completion. |
