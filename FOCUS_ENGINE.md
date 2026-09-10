# The Flowback Focus Engine

The Flowback Focus Engine is a deterministic arbitration system that decides whether to switch focus or notify the user when an agent completes or requires input.

> **CRITICAL RULE:** An LLM does NOT make focus decisions. All focus decisions are 100% deterministic, audit-logged, and testable.

---

## 1. Deterministic Decision Algorithm

```text
                                 [Agent Event Received]
                                            ↓
                               [Focus Lock Active?]
                                   ├── YES ──► [Notify Only]
                                   └── NO
                                            ↓
                              [Effective Policy == Never?]
                                   ├── YES ──► [Suppress Focus & Notification]
                                   └── NO
                                            ↓
                         [Protected App Frontmost? (Zoom/Slack/Game)]
                                   ├── YES ──► [Notify Only]
                                   └── NO
                                            ↓
                             [Frontmost App in Fullscreen?]
                                   ├── YES ──► [Notify Only]
                                   └── NO
                                            ↓
                        [User Actively Interacting Elsewhere? (<5s)]
                                   ├── YES ──► [Notify Only (Do Not Steal Focus)]
                                   └── NO
                                            ↓
                       [Origin Window on Different macOS Space?]
                                   ├── YES (and SpacePolicy != Allow) ──► [Notify Only]
                                   └── NO
                                            ↓
                             [Focus Cooldown Active? (<1000ms)]
                                   ├── YES ──► [Defer to Attention Queue / Notify]
                                   └── NO
                                            ↓
                           [Restore Origin Context (Section 14)]
```

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
