# Security Policy & Vulnerability Reporting

Flowback takes the security of developer environments seriously. We appreciate the responsible disclosure of security issues by researchers and community members.

---

## 1. Supported Versions

Security updates are provided for the latest stable release of Flowback:

| Version | Supported | Notes |
|---|---|---|
| `1.0.x` | :white_check_mark: Yes | Current active release branch |
| `< 1.0` | :x: No | Pre-release and development snapshots |

---

## 2. Reporting a Vulnerability

**Please do NOT report security vulnerabilities through public GitHub issues or public discussions.**

### Preferred Reporting Method: GitHub Private Vulnerability Reporting
Please submit all vulnerability reports directly through GitHub's Private Vulnerability Advisory interface:
👉 **[Report a security vulnerability on GitHub](https://github.com/rapheljr/flowback/security/advisories/new)**

This opens an encrypted, private advisory between you and the maintainers where the vulnerability can be investigated, patched, and coordinated without premature exposure.

### Report Contents
When submitting a report, please include:
1. **Description:** Clear explanation of the issue and potential security impact.
2. **Affected Component:** (e.g., IPC Unix socket server, hook installation, focus controller, SQLite database).
3. **Reproduction Steps:** Step-by-step instructions or minimal proof-of-concept script.
4. **Environment:** macOS version, Mac architecture (Apple Silicon vs. Intel), and Flowback version.
5. **Mitigation:** Any temporary workarounds or recommended remediation if known.

> [!WARNING]
> Do NOT include real passwords, API tokens, proprietary source code, or private keys in reproduction steps.

---

## 3. What Qualifies as a Security Vulnerability?

Examples of valid security reports:
* **Arbitrary Command Execution:** Malicious payload injected via the Unix domain socket (`flowback.sock`) or provider hook that triggers unauthorized code execution.
* **Privilege Escalation:** Exploiting Accessibility (`AXUIElement`) or AppleScript automation to interact with sensitive system dialogs outside Flowback's scope.
* **Local Information Disclosure:** Reading private user workspace files or unauthenticated access to the local database across distinct local user accounts (POSIX UID boundaries).
* **Denial of Service:** Crafting malformed socket packets that cause the menu bar daemon or system window server to hang or crash repeatedly.

Non-qualifying reports:
* Attacks requiring physical access to an unlocked Mac with full root/sudo access already acquired.
* Social engineering or phishing of developers.
* Known behavior of user-configured hooks executing commands defined explicitly by the user in `hooks.json`.

---

## 4. Response & Remediation Goals

The maintainers aim to meet the following response milestones on a best-effort basis:
* **Initial Acknowledgment:** Within 48 hours of report receipt.
* **Assessment & Severity Triaging:** Within 5 business days.
* **Fix Development & Testing:** Dependent on complexity; high-severity fixes are prioritized for hotfix releases.
* **Coordinated Disclosure:** We work with reporters on a reasonable embargo period (typically 30–90 days) until a patched release is published.

---

## 5. How Fixes are Released

1. Security fixes are developed in private forks associated with the GitHub Security Advisory.
2. A patch release (e.g., `v1.0.1`) is tagged and built.
3. Release notes will detail the impact, credited researchers (unless anonymity is requested), and CVE assignment when applicable.

---

## 6. Flowback Architectural Security Model

Flowback is designed under a strict **least-privilege, local-only, zero-trust** security model:

### Network Boundary
* **Zero Cloud Connections:** Flowback makes zero outbound network requests.
* **No Telemetry:** No analytics, crash telemetry, or tracking servers exist in the codebase.
* **No Local Web Servers:** Flowback does not open HTTP or TCP ports. IPC is strictly bounded to a local POSIX Unix domain socket (`~/.flowback/flowback.sock`).
* **Socket Permissions:** Created with file mode `0600` (readable and writable strictly by the current user's UID).

### macOS Permissions Rationale
* **Accessibility (`AXUIElement`):** Needed to query specific window IDs (`_AXUIElementGetWindow`), match window titles to project directories, and raise background windows (`kAXRaiseAction`). If denied, Flowback degrades gracefully to application-level activation via `NSWorkspace`.
* **Notifications (`UNUserNotificationCenter`):** Delivers non-intrusive alert banners when the user is actively working or when multiple agents complete simultaneously.
* **Launch at Login (`SMAppService`):** Registers Flowback as a modern user login service.

### Sandboxing & Hardened Runtime
* Compiled with `--options runtime` and prepared for Apple Developer ID code signing.
* Entitlements are restricted to necessary Apple Events coordination (`com.apple.security.automation.apple-events`).

### Hook Safety
When managing hooks (e.g. `~/.gemini/config/hooks.json` for Antigravity):
* Never overwrites existing user hook configurations without creating a timestamped backup.
* Verifies hook file permissions and executable flags.
* Removes only Flowback's own injected commands during uninstallation.
