# Agent Providers Specification & Integration Guide

Flowback integrates with AI coding agents using a modular, protocol-oriented provider architecture.

---

## Provider Support Levels

Flowback assigns an honest, evidence-backed support level to every integrated provider:

* **`native-lifecycle`**: Provider-specific lifecycle events and stop hooks are natively implemented, validated, and tested.
* **`adapter`**: Lifecycle events are derived through a documented CLI wrapper, terminal watcher, or process adapter.
* **`generic-protocol`**: Events arrive through the public Flowback integration contract (`~/.flowback/flowback.sock`).
* **`context-only`**: Application/workspace context is available, but reliable lifecycle events are not.
* **`partial`**: Material capabilities work, but material limitations remain.
* **`planned`**: Not yet implemented.

### Verification Tiers
To ensure technical accuracy, Flowback distinguishes four verification states:
* **`Implemented`**: Adapter class and data models exist in the codebase conforming to `AgentProvider`.
* **`Unit-Tested`**: Individual payload parsing, error normalization, and deduplication verified by unit tests.
* **`Integration-Tested`**: Configuration backup/mutation, local plugin/hook installation, protocol IPC boundary, injectable HTTP transport (pagination, rate-limiting, error handling), and session manager event bus propagation verified in deterministic test suites.
* **`Runtime-Verified`**: End-to-end execution verified against an active, live instance of the target software with real credentials in a real user environment.

---

## Provider Conversation Capability Matrix

Flowback evaluates conversation identity and restoration capabilities independently. A provider can expose a reliable conversation ID and title without exposing a mechanism to deep-link into that conversation.

| Provider | Native ID Source | Title Discovery Source | Focus Capability | Verification Level | Restoration Mechanism & Fallback |
|---|---|---|---|---|---|
| **Google Antigravity** | `conversation_id` (hook payload & brain directory) | Extracted from session transcript (`<USER_REQUEST>` / `### USER Objective:`) | `windowOnly` | **Integration-Tested** (Mocks & Transcripts) | Activates Antigravity window & workspace (`.workspaceActivatedOnly` / `.windowActivatedOnly`). |
| **Antigravity CLI (`agy`)** | `conversationId` (native CLI hook & session storage) | Read-only SQLite query to `conversation_summaries.db` (`summary` column) or transcript first line | `workspaceAndConversation` | **Integration-Tested** (Native Hooks & Storage) | Focuses Terminal window, navigates to workspace, and presents resume command hint `agy --conversation <id>` (`.resumeHintPresented`). |
| **Cursor Background Agent** | Cloud agent `id` (`bc-...`) | `summary` field from Cloud API / Pull Request title | `externalURL` | **Integration-Tested** (Injectable Transport & Mock API) | Directly opens verified PR URL or `https://cursor.com/agents/<id>` in default browser (`.providerURLOpened`). Never claims local conversation restoration. |
| **Claude Code** | Session ID from prompt hooks / transcripts | Hook `title` or first line of prompt | `workspaceAndConversation` | **Integration-Tested** | Focuses Terminal workspace; presents `claude resume <id>` hint (`.resumeHintPresented`). |
| **Windsurf** | `trajectory_id` / `session_id` in Cascade hooks | Initial prompt / Cascade user objective | `windowOnly` | **Integration-Tested** (Mock Cascade Hooks) | Activates Windsurf editor window (`.windowActivatedOnly`). Cascade exposes no public deep-linking URL scheme. |
| **OpenCode** | `sessionID` from Plugin API | Plugin payload `title` or task prompt | `windowOnly` | **Integration-Tested** (Mock Context & Socket IPC) | Activates OpenCode application window and workspace (`.workspaceActivatedOnly` / `.windowActivatedOnly`). |
| **OpenAI Codex** | Thread / Session ID | User prompt first line | `windowOnly` | **Integration-Tested** (Lifecycles & Hooks) | Activates containing application or terminal window (`.windowActivatedOnly`). Does not fabricate unsupported CLI resume commands. |
| **Aider** | Git branch / session ID | Git branch description or initial instruction | `windowOnly` | **Integration-Tested** (Lifecycles & Adapters) | Activates terminal window (`.windowActivatedOnly`). Normalizes recognized lifecycle events; unknown events default to running rather than completion. |
| **Generic Hook** | `conversation_id` in socket payload | `conversation_title` or `task_id` in JSON | `windowOnly` / Dynamic | **Integration-Tested** | Dynamic: opens `conversation_url` if present, otherwise activates registered window/workspace. |

> **Capability Legend:**
> - `exactConversation`: Documented and implemented ability to directly focus the specific conversation.
> - `workspaceAndConversation`: Able to focus the workspace and resume the conversation via documented command.
> - `externalURL`: Direct web browser navigation to provider dashboard, session view, or pull request.
> - `windowOnly`: Activates the correct application/window, but cannot select the individual conversation within the GUI.
> - `unavailable`: Insufficient identity or restoration data to guarantee a safe target.

---

## The `AgentProvider` Protocol

All providers conform to `AgentProvider` defined in `FlowbackCore`:

```swift
public protocol AgentProvider: Sendable {
    var providerID: AgentProviderID { get }
    var displayName: String { get }
    var isSupported: Bool { get }
    var supportLevel: ProviderSupportLevel { get }
    
    func checkHealth() async -> ProviderHealth
    func parseLifecyclePayload(data: Data) throws -> AgentEvent?
    func installIntegration() async throws
    func uninstallIntegration() async throws
    func discoverActiveSessions() async -> [AgentSession]
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

## 4. Antigravity CLI Provider (`AntigravityCLIProvider`)

> **Note:** Formerly known as *Gemini CLI* (`gemini`). Rebranded to Google's official *Antigravity CLI* (`agy`) while preserving backwards compatibility aliases (`gemini-cli`, `gemini`, `agy`).

* **Integration Mechanism:** Detects `agy` binary (`/opt/homebrew/bin/agy`, `/usr/local/bin/agy`, or in PATH) and hooks configured in `~/.gemini/config/hooks.json` (as well as `~/.gemini/antigravity-cli`).
* **Supported Lifecycle Events:**
  * `PreInvocation` (turn 1): Normalizes to `.agentStarted`.
  * `PreInvocation` (subsequent turns): Normalizes to `.agentRunning`.
  * `PostInvocation`: Normalizes to `.agentProgress`.
  * `Stop` (`fullyIdle: true`): Normalizes to `.agentCompleted`.
  * `Stop` (`fullyIdle: false`): Normalizes to `.agentRunning`.
  * Error status / process failure: Normalizes to `.agentFailed`.
  * Tool confirmation prompts: Normalizes to `.agentPermissionRequired`.
* **Proactive Discovery:** Scans `~/.gemini/antigravity-cli/brain/` for active transcripts and `presence/*.lock` for active terminal session tracking with `history.jsonl` workspace correlation.
* **Window Restoration:** Restores focus directly to the terminal emulator running `agy` (Ghostty, Apple Terminal, iTerm2, Warp, Hyper, etc.) matching the workspace directory.

---

## 5. Aider Provider (`AiderProvider`)

* **Integration Mechanism:** Git repository change watcher and terminal session tracker.

---

## 6. Windsurf Provider (`WindsurfProvider`)

* **Integration Mechanism:** Official Cascade JSON lifecycle hooks configured in `~/.codeium/windsurf/hooks.json` (with proactive transcript scanning in `~/.codeium/windsurf/transcripts/`).
* **Supported Lifecycle Events:**
  * `pre_user_prompt`: Agent turn launched; normalized to `.agentStarted` or `.agentRunning`.
  * `pre_run_command`, `pre_write_code`, `pre_mcp_tool_use`: Normalizes to `.agentRunning` (or `.agentPermissionRequired` when `requires_confirmation: true`).
  * `post_run_command`, `post_write_code`, `post_mcp_tool_use`: Normalizes to `.agentProgress`.
  * `post_cascade_response`, `post_cascade_response_with_transcript`: Agent completed turn; normalized to `.agentCompleted`.
* **Identity Correlation:** Preserves Cascade `trajectory_id` as the primary session ID, along with `execution_id` and action metadata.
* **Safe Installation:** Creates a timestamped backup before idempotently inserting Flowback hook entries without overwriting existing user scripts. On uninstall, only Flowback hook entries are removed.
* **Window Restoration:** Paired with dedicated `WindsurfAdapter` in `FlowbackFocus` targeting `com.codeium.windsurf` using exact window ID or workspace folder name matching (`[Workspace] — Windsurf`).

---

## 7. OpenCode Provider (`OpenCodeProvider`)

* **Integration Mechanism:** Official OpenCode plugin architecture (`~/.config/opencode/plugins/flowback.js`).
* **Supported Events:**
  * `session.created` → `.agentStarted`
  * `session.running` / `session.status` (busy) → `.agentRunning`
  * `tool.execute.before` (with permission flag) → `.agentPermissionRequired`
  * `tool.execute.after` → `.agentProgress`
  * `session.idle` / `session.completed` → `.agentCompleted`
  * `session.deleted` → `.agentCancelled`
  * `session.error` → `.agentFailed`
* **Transport:** Emits normalized events over authenticated local Unix Domain Socket (`~/.flowback/flowback.sock`).
* **Reload & Lifecycle Resilience:** Implements standard plugin teardown via `AbortController` to handle live plugin reload and daemon reconnections without duplicate event loops.

---

## 8. Cursor Background Agent (`CursorBackgroundProvider` & `CursorAdapter`)

Flowback strictly decouples local Cursor editor focus from remote Cloud Background Agents:

* **Local Editor Focus (`CursorAdapter`):**
  * Supports `co.anysphere.cursor`, `com.todesktop.230313mzl4w4u92`, and `com.cursor.Cursor`.
  * Multi-tier restoration: Exact window ID → Workspace folder match → Window title match → Safe frontmost activation.
  * Handles stale PIDs and closed windows gracefully without failing silently.
* **Remote Cloud Agent Tracking (`CursorBackgroundProvider`):**
  * Connects to official Cursor Cloud Agents API (`https://api.cursor.com/v1/agents`).
  * **Authentication:** Uses secure `CURSOR_API_KEY` (from environment or `~/.flowback/cursor_api_key`). Credentials are encrypted/isolated and **never** printed in logs or diagnostic events.
  * **Lifecycle Coverage:** Translates cloud statuses (`RUNNING`, `WAITING`, `CONFIRMATION_REQUIRED`, `COMPLETED`, `FAILED`, `CANCELLED`).
  * **Metadata & Subagents:** Tracks repository URLs, branch names, PR URLs (`prUrl`), latest run IDs, and hierarchical subagents (`parentAgentId` → `parentSessionId`).
  * **Context Restoration:** Resolves whether a matching local repository clone exists on disk:
    * If local clone found: Restores workspace in Cursor (`.workspaceWindow`).
    * If remote cloud-only: Offers browser/navigation fallback directly to the Pull Request or task run dashboard (`.notificationFallbackOnly`).

---

## 9. Generic Hook Provider (`GenericHookProvider`)

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
       AntigravityCLIProvider(),
       AiderProvider(),
       WindsurfProvider(),
       OpenCodeProvider(),
       CursorBackgroundProvider(),
       NewAgentProvider(),
       GenericHookProvider()
   ]
   ```
Core focus decision and UI logic remain untouched.
