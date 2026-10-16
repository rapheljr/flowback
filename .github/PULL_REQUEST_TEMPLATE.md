## Summary

<!-- Brief 1-2 sentence description of what this PR does and why. -->

## Motivation & Issue Reference

<!-- Closes #123 / Fixes #456 / Addresses proposal at ... -->

## Change Category

- [ ] New Agent Provider (e.g., Windsurf, OpenCode)
- [ ] Application / Window Adapter (e.g., new IDE, Terminal, Browser)
- [ ] Focus Policy or Attention Arbitration
- [ ] Bug Fix (State machine, IPC, SQLite, Window raising)
- [ ] Performance / Memory Optimization
- [ ] Documentation / Website
- [ ] CI / Release Infrastructure
- [ ] Other

## Implementation Details

<!-- Describe key technical changes, design choices, and architectural considerations. -->

## Testing Performed

<!-- Detail the automated or manual tests executed. -->
- [ ] Verification Suite: `swift run FlowbackTestRunner` (all 61 tests passed)
- [ ] Manual verification with live agent / editor
- [ ] Other:

## macOS Versions & Architectures Tested

- [ ] macOS 14 Sonoma
- [ ] macOS 15 Sequoia
- [ ] Apple Silicon (arm64)
- [ ] Intel (x86_64)

## Provider Integrations Affected

- [ ] Antigravity
- [ ] Claude Code
- [ ] OpenAI Codex
- [ ] Gemini CLI / Aider
- [ ] Generic Hook Protocol
- [ ] None / Not Provider-Specific

## Permissions & Privacy Implications

<!-- Explain if this change modifies Accessibility (AXUIElement), AppleEvents, or notifications usage. -->
* **Permissions Changed?** No / Yes:
* **Privacy Impact:** Confirmed zero telemetry, zero keystroke logging, and zero secret capture.

## Screenshots / Video (For UI or Menu Bar Changes)

<!-- Attach screenshot or GIF if modifying SwiftUI Dashboard or AppKit Menu Bar. -->

## Documentation Changes

<!-- List any updated docs, README sections, or website pages. -->

## Migration & Backward Compatibility Concerns

<!-- Does this change affect SQLite schema or IPC protocol version? -->

---

## Contributor Checklist

- [ ] Tests added or updated for new logic
- [ ] Relevant tests pass (`swift run FlowbackTestRunner`)
- [ ] Build succeeds in debug and release modes (`make release`)
- [ ] SwiftLint checks pass without errors
- [ ] Documentation updated
- [ ] No secrets, tokens, or sensitive test paths added
- [ ] Permissions and privacy implications reviewed
- [ ] Unsupported behavior is clearly documented
