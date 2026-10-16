# Getting Support for Flowback

Thank you for using Flowback! Here is how to find help, ask questions, and report issues.

---

## 1. Diagnostic Self-Check First

Before opening an issue, run Flowback's built-in diagnostic tool from your terminal:

```bash
flowback doctor
```

This tests:
* macOS version compatibility
* Accessibility permissions (`AXUIElement`)
* Notification authorizations
* SQLite database connectivity & WAL mode integrity
* Unix domain socket server responsiveness
* Hook registrations (Antigravity, Claude Code, Codex, etc.)

Check [TROUBLESHOOTING.md](TROUBLESHOOTING.md) for step-by-step solutions to common diagnostic errors.

---

## 2. Asking Questions & General Discussion

For questions such as:
* How do I configure focus rules for my workspace?
* How can I integrate a custom CLI agent or script using the Generic Hook Protocol?
* General discussions about macOS focus management and agent workflows.

👉 **Join the conversation on [GitHub Discussions](https://github.com/rapheljr/flowback/discussions)** (or the [Q&A category](https://github.com/rapheljr/flowback/discussions/categories/q-a)).

---

## 3. Reporting Bugs & Issues

If you encountered a bug, unexpected behavior, or a crash:
1. Search [Existing Issues](https://github.com/rapheljr/flowback/issues) to see if it has already been reported.
2. If not, open a new issue using our [Bug Report Form](https://github.com/rapheljr/flowback/issues/new?template=bug_report.yml).
3. Please provide sanitized output from `flowback doctor` and reproduction steps.

> [!CAUTION]
> Never paste API keys, passwords, private source code, or proprietary directory structures in public issues.

---

## 4. Proposing New Agent Providers or Features

* To request or contribute an adapter for a new coding agent, use our [New Agent Provider Template](https://github.com/rapheljr/flowback/issues/new?template=new_agent_provider.yml).
* For application compatibility requests (e.g. support for a specific terminal or IDE), use our [App Compatibility Template](https://github.com/rapheljr/flowback/issues/new?template=app_compatibility.yml).

---

## 5. Security Vulnerabilities

For security concerns and vulnerability reports, please refer to our [Security Policy](SECURITY.md) and report privately at:
👉 **[GitHub Private Vulnerability Reporting](https://github.com/rapheljr/flowback/security/advisories/new)**
