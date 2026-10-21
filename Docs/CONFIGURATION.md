# Flowback Configuration & Policies

Flowback uses a multi-tier policy resolution engine allowing granular focus management defaults and overrides.

---

## Configuration Location

Flowback persists active policy configuration and session metadata in a local SQLite database (WAL mode):
```text
~/.flowback/flowback.sqlite
```
Configuration snapshots can be exported to and imported from portable JSON files (such as `~/.flowback/config.json`) via the CLI (`flowback config export` / `flowback config import`) or the **Advanced** tab in the Flowback Dashboard.

---

## Policy Resolution Hierarchy

When an agent event arrives, Flowback computes the active focus policy using a 4-tier resolution hierarchy:

```text
Workspace Override   (Highest Priority: specific repository filesystem path)
       ↓
Application Override (Target Editor / Terminal bundle identifier)
       ↓
Provider Override    (Antigravity, Windsurf, OpenCode, Cursor, Copilot, etc.)
       ↓
Global Focus Policy  (Lowest Priority: general system baseline)
```

---

## Canonical Configuration Schema (`config.json`)

Flowback serializes and validates settings against the strongly-typed `PolicyConfiguration` model:

```json
{
  "schemaVersion": 1,
  "focusPolicy": "smart",
  "completionBehavior": "restore-origin",
  "permissionBehavior": "focus-agent",
  "failureBehavior": "focus-agent",
  "spacePolicy": "never-switch",
  "focusCooldownMs": 1000,
  "attentionAggregationMs": 1500,
  "activeInteractionThresholdSeconds": 5.0,
  "protectedApplications": [
    "com.apple.keynote",
    "us.zoom.xos",
    "com.microsoft.teams",
    "com.cisco.webexmeetingsapp",
    "com.apple.FaceTime",
    "com.apple.QuickTimePlayerX",
    "com.telestream.screenflow10"
  ],
  "launchAtLogin": false,
  "providerOverrides": {
    "antigravity": "smart",
    "claude-code": "restore-if-left-origin"
  },
  "applicationOverrides": {
    "com.google.antigravity-ide": "smart",
    "com.microsoft.VSCode": "always-restore"
  },
  "workspaceOverrides": {
    "/Users/username/src/critical-prod-repo": "notification-only",
    "/Users/username/src/silent-evals": "never-interrupt"
  }
}
```

---

## Configuration Parameters Reference

| Parameter | Type | Default | Description & Valid Options |
|---|---|---|---|
| `schemaVersion` | Integer | `1` | Configuration schema version identifier. |
| `focusPolicy` | String | `"smart"` | Base focus policy. Options: `"smart"`, `"always-restore"`, `"restore-if-left-origin"`, `"notification-only"`, `"never-interrupt"`. |
| `completionBehavior` | String | `"restore-origin"` | Action on agent completion. Options: `"restore-origin"`, `"notification-only"`, `"ask-user"`. |
| `permissionBehavior` | String | `"focus-agent"` | Action when agent requires confirmation. Options: `"focus-agent"`, `"notification-only"`. |
| `failureBehavior` | String | `"focus-agent"` | Action when agent fails. Options: `"focus-agent"`, `"notification-only"`. |
| `spacePolicy` | String | `"never-switch"` | Handling of macOS Spaces. Options: `"never-switch"`, `"app-only"`, `"app-and-window"`, `"allow-switching"`. |
| `focusCooldownMs` | Integer | `1000` | Cooldown window (in milliseconds) preventing rapid repeated window switches. |
| `attentionAggregationMs` | Integer | `1500` | Sliding window (in milliseconds) to aggregate simultaneous agent completions. |
| `activeInteractionThresholdSeconds` | Double | `5.0` | Minimum seconds of user idle before auto-restoring origin window. |
| `protectedApplications` | Array[String] | `[...]` | Bundle IDs of apps (video calls, presentations) that suppress automatic focus stealing when frontmost. |
| `launchAtLogin` | Boolean | `false` | Automatically launch Flowback menu bar daemon on user login via `SMAppService`. |
| `providerOverrides` | Map[String, Policy] | `{}` | Per-provider policy overrides (e.g. `{"antigravity": "smart"}`). |
| `applicationOverrides` | Map[String, Policy] | `{}` | Per-application bundle ID overrides (e.g. `{"com.microsoft.VSCode": "always-restore"}`). |
| `workspaceOverrides` | Map[String, Policy] | `{}` | Per-workspace folder path overrides (e.g. `{"/Users/me/repo": "notification-only"}`). |

---

## Focus Policy Values Explained

* **`smart` (Default):** Evaluates user activity via hardware event source. If the user was actively typing or clicking within the last 5 seconds, suppresses focus stealing and displays an actionable macOS notification; if idle, smoothly raises the origin window.
* **`always-restore`:** Unconditionally raises the origin window when an agent turn completes (unless a protected application like Zoom or Keynote is currently frontmost).
* **`restore-if-left-origin`:** Restores focus only if the user navigated to a different application after the agent started.
* **`notification-only`:** Never switches focus automatically. Displays an actionable notification banner with a `[Focus Window]` button.
* **`never-interrupt`:** Complete quiet mode. Suppresses automatic focus switches and notification alerts.

---

## Managing Configuration via CLI

Flowback provides command-line utilities to export, modify, and import configuration:

```bash
# Export active configuration to standard output:
flowback config export

# Export configuration to a file:
flowback config export ~/.flowback/config.json

# Import configuration from a file:
flowback config import ~/.flowback/config.json
```

