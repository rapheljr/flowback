# Flowback Security Policy & Model

Flowback is designed under a strict **least-privilege, local-only, zero-trust** security model.

---

## 1. Network Boundary

* **Zero Cloud Connections:** Flowback makes zero outbound network requests.
* **No Telemetry:** No analytics, crash telemetry, or tracking servers exist in the codebase.
* **No Local Web Servers:** Flowback does not open HTTP or TCP ports. IPC is strictly bounded to a local POSIX Unix domain socket (`~/.flowback/flowback.sock`).
* **Socket Permissions:** Created with file mode `0600` (readable and writable strictly by the current user's UID).

---

## 2. macOS Permissions Rationale

Flowback requests only permissions strictly necessary for its functionality:

### Accessibility (`AXUIElement`)
* **Why Required:** Needed to query specific window IDs (`_AXUIElementGetWindow`), match window titles to project directories, and raise background windows (`AXUIElementPerformAction(kAXRaiseAction)`).
* **Graceful Degradation:** If Accessibility permission is denied by the user, Flowback continues operating in **Application-Level Mode**. It activates the target application using `NSWorkspace` without error.

### Notifications (`UNUserNotificationCenter`)
* **Why Required:** Needed to deliver non-intrusive alert banners when the user is actively working or when multiple agents complete simultaneously. Includes actionable `[Focus]` and `[Review]` buttons.

### Launch at Login (`SMAppService`)
* **Why Required:** Registers Flowback as a modern user login service so it can monitor agents continuously in the menu bar. Managed via macOS `SMAppService.mainApp`.

---

## 3. Sandboxing & Hardened Runtime

* **Hardened Runtime Enabled:** Compiled with `--options runtime` and signed with Ad-hoc or Apple Developer ID credentials.
* **Entitlements:**
  * `com.apple.security.automation.apple-events`: Required to coordinate application activation with AppKit.

---

## 4. Hook Safety

When installing hooks (e.g. `~/.gemini/config/hooks.json` for Antigravity):
* Flowback never overwrites user configurations blindly.
* It creates a timestamped backup before any write operation.
* It verifies hook file permissions and executable flags before invoking.
* It cleans up only its own injected commands on uninstallation.
