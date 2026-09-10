# Application Adapters & Window Discovery

Flowback decouples application-specific window management through an adapter architecture.

---

## Architectural Principle

Flowback does **not** hardcode editors or browsers into the core focus logic. Any application is represented generically:
```swift
public struct ApplicationInfo: Identifiable, Hashable, Sendable {
    public let bundleIdentifier: String
    public let processIdentifier: Int32
    public let path: String?
    public let displayName: String
    public let version: String?
}
```

Adapters are only invoked when an application requires specific matching heuristics (e.g. matching a window title to a project directory or raising a specific tab).

---

## The `ApplicationAdapter` Protocol

```swift
public protocol ApplicationAdapter: Sendable {
    var adapterName: String { get }
    func canHandle(bundleIdentifier: String) -> Bool
    func restoreContext(
        context: OriginContext,
        appController: ApplicationControlling,
        windowController: WindowControlling
    ) async -> Bool
}
```

---

## Section 14 Restoration Priority

Every adapter adheres to the Section 14 restoration hierarchy:
```text
1. Exact original window ID (via AXUIElement / CGWindowList)
2. Same application + workspace directory match (via window title matching)
3. Same process ID (PID)
4. Same application bundle (activate frontmost instance)
5. Fallback gracefully without opening unexpected new windows
```

---

## Built-In Adapters

### 1. `VSCodeAdapter`
* **Supported Bundle IDs:** `com.microsoft.VSCode`, `com.microsoft.VSCodeInsiders`, `com.visualstudio.code.oss`.
* **Behavior:**
  1. Checks for exact window matching `windowIdentifier`.
  2. If missing, extracts workspace directory name from `workspacePath` (e.g. `matchday`) and searches running VS Code window titles for `MatchDay — Visual Studio Code`.
  3. Uses Accessibility (`AXUIElement`) to bring the window to the front and activates the application.

### 2. `CursorAdapter`
* **Supported Bundle IDs:** `com.todesktop.230313mzl4w4u92`, `com.cursor.Cursor`.
* **Behavior:** Applies AI-editor window heuristics matching current workspace project folder.

### 3. `TerminalAdapter`
* **Supported Bundle IDs:** `com.apple.Terminal`, `com.googlecode.iterm2`, `com.mitchellh.ghostty`, `dev.warp.Warp-Stable`, `co.zeit.hyper`.
* **Behavior:** Targets the specific shell session tab or terminal window where the agent or CLI task originated.

### 4. `BraveAdapter`
* **Supported Bundle IDs:** `com.brave.Browser`, `com.brave.Browser.beta`.
* **Behavior:** Restores browser window context for web-based agents and debug sessions.

### 5. `GenericApplicationAdapter`
* **Supported Bundle IDs:** Any macOS application.
* **Behavior:** Performs generic window enumeration and AppKit `application.activate(options: [])`.

---

## Window Raising Implementation

Raising a specific background window on macOS without disturbing other spaces or windows requires low-level system coordination:

```swift
// 1. CoreGraphics window lookup
let windowList = CGWindowListCopyWindowInfo([.optionOnScreenOnly, .excludeDesktopElements], kCGNullWindowID)

// 2. Accessibility window raising
let appRef = AXUIElementCreateApplication(pid)
var windowsValue: AnyObject?
AXUIElementCopyAttributeValue(appRef, kAXWindowsAttribute as CFString, &windowsValue)
if let axWindows = windowsValue as? [AXUIElement] {
    for axWin in axWindows {
        var axWinID: CGWindowID = 0
        _AXUIElementGetWindow(axWin, &axWinID)
        if axWinID == targetWindowID {
            AXUIElementPerformAction(axWin, kAXRaiseAction as CFString)
            break
        }
    }
}
```

---

## Adding a New Application Adapter

1. Create `Sources/FlowbackFocus/Adapters/YourAppAdapter.swift`:
   ```swift
   import Foundation
   import FlowbackCore

   public struct YourAppAdapter: ApplicationAdapter {
       public let adapterName = "Your App Adapter"
       public init() {}

       public func canHandle(bundleIdentifier: String) -> Bool {
           bundleIdentifier == "com.example.yourapp"
       }

       public func restoreContext(
           context: OriginContext,
           appController: ApplicationControlling,
           windowController: WindowControlling
       ) async -> Bool {
           // Custom restoration logic
           return true
       }
   }
   ```
2. Register in `ApplicationAdapterRegistry`:
   ```swift
   ApplicationAdapterRegistry.shared.register(YourAppAdapter())
   ```
