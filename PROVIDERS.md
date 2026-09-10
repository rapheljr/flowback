# Agent Providers Specification & Integration Guide

Flowback integrates with AI coding agents using a modular, protocol-oriented provider architecture.

---

## The `AgentProvider` Protocol

All providers conform to `AgentProvider` defined in `FlowbackCore`:

```swift
public protocol AgentProvider: Sendable {
    var providerID: AgentProviderID { get }
    var displayName: String { get }
    var isSupported: Bool { get }
    
    func checkHealth() async -> ProviderHealth
    func parseLifecyclePayload(data: Data) throws -> AgentEvent?
    func installIntegration() async throws
    func uninstallIntegration() async throws
}
```

This ensures that adding a new agent requires **zero changes** to:
* Domain Models
* Event Bus
* Session Manager
* Policy Engine
* Attention Arbiter
* Focus Controller
* UI & Persistence

---

## 1. Antigravity Provider (`AntigravityProvider`)

Antigravity is Flowback's primary provider integration.

### Integration Mechanism
* **Hook Configuration File:** `~/.gemini/config/hooks.json`
* **Hook Trigger:** `Stop` event
* **Payload Format:**
  ```json
  {
    "hook_event_name": "Stop",
    "fullyIdle": true,
    "executionNum": 4,
    "conversation_id": "733f120f-02e0-4c23-bab1-142635d3ecc9",
    "workspace": "/Users/abin/workspace/projects/matchday",
    "error": null
  }
  ```
* **Completion Contract:**
  * If `fullyIdle == true`, Flowback emits `.agentCompleted`.
  * If `error != nil`, Flowback emits `.agentFailed`.
  * If `fullyIdle == false`, Flowback treats the agent as still actively working (`.agentRunning`), ignoring premature intermediate pauses.

### Safe Installation & Rollback
Before modifying `~/.gemini/config/hooks.json`:
1. Flowback creates a timestamped backup: `hooks.json.backup.<timestamp>`.
2. Checks if a `Stop` hook command pointing to `flowback hook antigravity` already exists.
3. Idempotently merges the hook command without clobbering existing commands or hooks.
4. On uninstall, restores original configurations cleanly.

---

## 2. Claude Code Provider (`ClaudeCodeProvider`)

* **Integration Mechanism:** Process and hook-based integration with Anthropic's Claude Code CLI.
* **Health Check:** Verifies existence of `claude` CLI in PATH (`/usr/local/bin/claude`, `~/.npm-global/bin/claude`).
* **Origin Context:** Resolves terminal process ID and working directory to restore the exact terminal tab/window.

---

## 3. OpenAI Codex Provider (`CodexProvider`)

* **Integration Mechanism:** Process-based session tracking and generic hook receiver.
* **Health Check:** Checks for active Codex agent sessions and hook registrations.

---

## 4. Gemini CLI Provider (`GeminiCLIProvider`)

* **Integration Mechanism:** Detects `gemini` command line tool and listens for completion hooks.

---

## 5. Aider Provider (`AiderProvider`)

* **Integration Mechanism:** Git repository change watcher and terminal session tracker.

---

## 6. Generic Hook Provider (`GenericHookProvider`)

For custom agents, scripts, CI runners, or tools without a dedicated provider, Flowback exposes a local JSON Event Protocol over IPC:

```bash
flowback emit agent.completed \
    --provider custom-agent \
    --session session-42 \
    --workspace /Users/abin/workspace/projects/flowback
```

Or by sending JSON directly to `~/.flowback/flowback.sock`:
```json
{
  "schemaVersion": 1,
  "event": "agent.completed",
  "provider": "custom-agent",
  "sessionId": "session-42",
  "workspace": "/Users/abin/workspace/projects/flowback",
  "timestamp": "2026-09-10T14:30:00Z"
}
```

---

## How to Add a New Provider

1. Create a new file in `Sources/FlowbackProviders/`:
   ```swift
   import Foundation
   import FlowbackCore

   public struct NewAgentProvider: AgentProvider {
       public let providerID = AgentProviderID("new-agent")
       public let displayName = "New Agent"
       public let isSupported = true

       public init() {}

       public func checkHealth() async -> ProviderHealth {
           // Verify agent installation, config paths, etc.
           return ProviderHealth(...)
       }

       public func parseLifecyclePayload(data: Data) throws -> AgentEvent? {
           // Parse incoming hook payload to normalized AgentEvent
           return AgentEvent(...)
       }

       public func installIntegration() async throws {
           // Safely register hooks or scripts
       }

       public func uninstallIntegration() async throws {
           // Remove hooks cleanly
       }
   }
   ```
2. Register the provider instance in `FlowbackService` provider registry:
   ```swift
   self.providers = [
       AntigravityProvider(),
       ClaudeCodeProvider(),
       CodexProvider(),
       GeminiCLIProvider(),
       AiderProvider(),
       NewAgentProvider(),
       GenericHookProvider()
   ]
   ```
Core focus decision and UI logic remain untouched.
