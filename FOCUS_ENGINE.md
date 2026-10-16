# The Flowback Focus Engine

The Flowback Focus Engine is a deterministic arbitration system that decides whether to switch focus or notify the user when an agent completes or requires input.

> **CRITICAL RULE:** An LLM does NOT make focus decisions. All focus decisions are 100% deterministic, audit-logged, and testable.

---

## 1. 12-Step Deterministic Decision Pipeline

Flowback processes lifecycle events through an explicit, 12-step deterministic decision sequence:

```text
 1. Event Validation & Authenticity    ──► Reject malformed / unauthorized peer UID
 2. Deduplication Check                ──► Suppress identical event within 500ms
 3. Stale & Out-of-Order Check         ──► Suppress event older than session update time
 4. Actionability Evaluation           ──► Only evaluate focus for actionable states
 5. Focus Lock State                   ──► Suppress focus switch; Notify only
 6. Policy Resolution & Precedence     ──► Workspace > App > Provider > Global
 7. Protected Application Check        ──► If frontmost app is protected (Zoom/Teams), Notify only
 8. Presentation / Fullscreen Check    ──► If frontmost window is fullscreen, Notify only
 9. Origin Liveness & Validity Check   ──► If target app/PID terminated, Notify only (.originProcessTerminated)
10. User Intent & Active Input Sensing ──► If user actively typing elsewhere (<5s), Notify only
11. macOS Space Policy Check           ──► If window on another Space & disallowed, Notify only
12. Focus Cooldown & Restoration       ──► If within 1000ms cooldown, Defer (.cooldownActive); Else Restore Origin
```

---

## 1.1 Structured Focus Outcomes & Reason Codes

Every decision emits one of four canonical focus outcomes accompanied by a typed `FocusReasonCode` and human-readable explanation:

| Canonical Outcome | Internal Enum | Description |
|---|---|---|
| `restore` | `FocusOutcome.restore` | Restores originating application window and workspace |
| `notify` | `FocusOutcome.notify` | Dispatches actionable macOS user notification |
| `defer` | `FocusOutcome.defer` | Postpones action until cooldown expires or condition is met |
| `ignore` | `FocusOutcome.ignore` | Safely drops irrelevant, duplicate, or stale events |

### Structured Reason Codes (`FocusReasonCode`)
* `.focusLockActive`: Focus Lock prevents automatic window switching.
* `.userActivelyInteracting`: User typing/mouse active in another window within threshold (<5s).
* `.protectedApplicationFrontmost`: Protected software (e.g. video conferencing) is frontmost.
* `.fullscreenPresentationMode`: Display is in macOS fullscreen presentation.
* `.originProcessTerminated`: Target application or process ID has terminated.
* `.cooldownActive`: Restoration deferred because another focus switch occurred recently (<1000ms).
* `.spaceSwitchProhibited`: Target window resides on a different macOS Space.
* `.policyNeverInterrupt`: User configured `.neverInterrupt` policy.
* `.policyNotificationOnly`: User configured `.notificationOnly` policy.
* `.restorationSucceeded`: Context restoration completed successfully.
* `.restorationFailedFallback`: Restoration failed, safely degrading to notification banner.
* `.eventStaleOrOutOfOrder`: Dropped due to expired timestamp or skew.
* `.eventNotActionable`: Background lifecycle event that does not request user attention.
* `.manualUserTrigger`: Focus manually requested via CLI or Menu Bar.

---

## 2. User Intent Detection

Flowback never steals focus when the user is in the middle of active work.
* **Hardware Idle Sensing:** Uses macOS `CGEventSource.secondsSinceLastEventType(.combinedSessionState, .any)`.
* **Activity Threshold:** Default is 5.0 seconds (`activeInteractionThresholdSeconds`).
* **Evaluation:**
  * If the user moved away from origin (e.g. now in Brave) and interacted with mouse/keyboard within the last 5 seconds, focus-stealing is strictly suppressed.
  * An actionable macOS banner notification is displayed instead.

---

## 3. Focus Policies

Users can configure policies globally or with granular overrides:
* **`smart` (Default):** Restores focus if the user is idle; notifies if user is actively engaged elsewhere.
* **`alwaysRestore`:** Unconditionally restores origin window when the agent completes.
* **`restoreIfUserLeftOrigin`:** Only switches focus if the user transitioned away from the origin application.
* **`notificationOnly`:** Never switches focus automatically; displays notification with a `[Focus]` action button.
* **`neverInterrupt`:** Completely suppresses notifications and focus switches for silent background agents.

### Policy Resolution Precedence
```text
1. Workspace Override (highest precedence)
2. Application Override
3. Provider Override
4. Global Default (lowest precedence)
```

---

## 4. Attention Arbitration

When multiple agents run concurrently (e.g. Antigravity in VS Code, Claude in Terminal, Codex in Cursor), Flowback prevents chaos.

### Priority Hierarchy
```text
1. permissionRequired  (Agent is blocked waiting for user approval)
2. failure             (Agent encountered an error / crashed)
3. completed           (Agent successfully finished task)
4. waiting             (Agent waiting on external dependencies)
5. informational       (Background progress / checkpoint)
```

### Event Aggregation Window
* Agents completing within 1.5 seconds (`attentionAggregationMs: 1500`) are bundled into a single aggregated notification:
  ```text
  "3 agents need attention"
  Antigravity — MatchDay
  Codex — API refactor
  Claude — Tests
  ```

### Focus Cooldown
* After restoring an application, Flowback enters a 1.0-second focus cooldown (`focusCooldownMs: 1000`). If another agent completes during this window, Flowback will **not** flip focus immediately, preventing rapid desktop flashing.

---

## 5. Protected Applications

Users can designate applications that should never be interrupted by automatic focus restoration:
* Video calls (Zoom, Google Meet, Microsoft Teams, FaceTime)
* Presentation tools (Keynote, PowerPoint)
* Gaming or full-screen video players

Default configuration:
```json
{
  "protectedApplications": [
    "us.zoom.xos",
    "com.apple.FaceTime",
    "com.microsoft.teams",
    "com.google.Chrome.app"
  ]
}
```

---

## 6. macOS Spaces Handling

Switching Spaces unexpectedly is disruptive to users. Flowback defaults to:
* `spacePolicy`: `neverSwitchSpaces`

Available options:
1. `neverSwitchSpaces`: If the target window is on an inactive Space, sends a notification instead of switching desktop spaces.
2. `activateApplicationOnly`: Activates the app on the current Space if possible.
3. `activateApplicationAndWindow`: Restores the window regardless of Space location.
4. `allowSpaceSwitching`: Permits native macOS Space switching.

---

## 7. Focus Lock

Users can activate Focus Lock directly from the menu bar or CLI:
```bash
flowback focus-lock 45m
```
* **Durations:** 15m, 30m, 45m, 1 hour, or indefinite.
* **Effect:** Disables all automatic focus transitions while keeping notifications and session history intact.
