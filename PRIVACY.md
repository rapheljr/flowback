# Flowback Privacy Manifesto

> **"Flowback knows WHERE you were, not WHAT you were doing."**

---

## The Privacy Contract

Flowback was built from the ground up for developers who work on proprietary, sensitive, and air-gapped codebases. 

### What Flowback NEVER Captures or Stores

* ❌ **NO Screenshots or Screen Recordings**
* ❌ **NO Keystrokes or Keyboard Logging**
* ❌ **NO Mouse Coordinates or Pointer Tracking**
* ❌ **NO Source Code or File Contents**
* ❌ **NO Terminal Commands or Shell History**
* ❌ **NO Environment Variables, API Keys, or Secrets**
* ❌ **NO Prompts, LLM Responses, or Context Dumps**
* ❌ **NO User Accounts or Remote Authentication**
* ❌ **NO Telemetry, Analytics, or Crash Logs to Remote Servers**

---

## What Flowback DOES Capture

Flowback stores minimal structural metadata strictly required to return you to your working window:

| Field | Purpose | Example |
|---|---|---|
| `bundleIdentifier` | Which application was active | `com.microsoft.VSCode` |
| `processIdentifier` | Application process ID | `1042` |
| `windowIdentifier` | Target macOS window ID | `42` |
| `windowTitle` | To match directory name | `MatchDay — Visual Studio Code` |
| `workspacePath` | Project root directory | `/Users/username/src/matchday` |
| `timestamp` | Time of context switch | `2026-09-10T14:30:00Z` |

---

## Local Storage & Retention

* All metadata is stored exclusively on your Mac at:
  ```text
  ~/.flowback/flowback.sqlite
  ```
* Sessions older than 30 days are automatically pruned during database maintenance.
* You can wipe all Flowback storage and history at any time:
  ```bash
  rm -rf ~/.flowback
  ```
