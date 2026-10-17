# Application Adapters & Window Discovery

Flowback connects agent sessions to specific application windows using dedicated application adapters.

---

## Supported Editors & Applications

| Application | Bundle Identifiers | Strategy |
|---|---|---|
| **Visual Studio Code** | `com.microsoft.VSCode` | Window ID → Title Pattern (`[Folder] — Visual Studio Code`) |
| **VS Code Insiders** | `com.microsoft.VSCodeInsiders` | Window ID → Title Pattern |
| **Cursor** | `co.anysphere.cursor`, `com.todesktop.230313mzl4w4u92`, `com.cursor.Cursor` | Window ID → Title Pattern (`[Folder] — Cursor`) |
| **Google Antigravity IDE** | `com.google.antigravity-ide`, `com.google.antigravity` | Window ID → Title Pattern |
| **Windsurf** | `com.codeium.windsurf` | Window ID → Title Pattern (`[Folder] — Windsurf`) |
| **VSCodium** | `com.vscodium`, `com.vscodium.codium` | Window ID → Title Pattern |
| **Positron** | `co.posit.positron`, `com.rstudio.positron` | Window ID → Title Pattern |
| **Trae** | `com.byteplus.trae` | Window ID → Title Pattern |
| **Apple Terminal** | `com.apple.Terminal` | Window ID → TTY / Working Directory |
| **iTerm2** | `com.googlecode.iterm2` | Window ID → Tab / Title |
| **Kitty / Alacritty / Ghostty / Warp** | Respective bundle IDs | Process ID & Window Raising |
| **Browsers (Brave, Chrome, Safari, Edge, Arc)** | Standard web bundle IDs | Workspace URL / Tab matching |

---

## Window Discovery & Restoration Hierarchy

When restoring context, Flowback executes Section 14 restoration hierarchy:

1. **Exact Window Identifier (`windowID`):**
   * Uses `AXUIElement` to locate the exact window matching the numeric window ID recorded at session inception.
   * If found and valid, executes `kAXRaiseAction` directly.
2. **Workspace & Title Matching:**
   * If the window ID is invalid (e.g., window was closed or reloaded), inspects all windows belonging to the target process.
   * Compares the window title against the active workspace folder name (e.g. `matchday`).
3. **Same Process Identifier (`PID`):**
   * Activates the specific process that hosted the agent session.
4. **Application Bundle Activation:**
   * Brings the parent application into focus using `NSWorkspace.shared.openApplication`.
5. **Graceful Fallback:**
   * If all else fails, delivers an interactive macOS notification with a `[Review]` action button, preventing unexpected crashes or disorienting desktop jumping.
