import Foundation
import AppKit
import FlowbackCore
import OSLog

private let logger = Logger(subsystem: "com.flowback.app", category: "CursorAdapter")

public struct CursorAdapter: ApplicationAdapter {
    public let adapterName = "Cursor Editor Adapter"
    
    private let supportedBundles: Set<String> = [
        "com.todesktop.230313mzl4w4u92",
        "co.anysphere.cursor",
        "com.cursor.Cursor"
    ]
    
    public init() {}
    
    public func canHandle(bundleIdentifier: String) -> Bool {
        supportedBundles.contains(bundleIdentifier)
    }
    
    public func restoreContext(
        context: OriginContext,
        appController: ApplicationControlling,
        windowController: WindowControlling
    ) async -> Bool {
        // Step 1: Locate running process
        var targetApp = appController.runningApplication(forProcessIdentifier: context.processIdentifier)
        if targetApp == nil {
            // Process might have restarted or changed PID; look up by bundle
            targetApp = appController.runningApplications(withBundleIdentifier: context.bundleIdentifier).first
            if targetApp == nil {
                for b in supportedBundles {
                    if let found = appController.runningApplications(withBundleIdentifier: b).first {
                        targetApp = found
                        break
                    }
                }
            }
        }
        
        guard let app = targetApp else {
            logger.warning("No running Cursor instance found for bundle \(context.bundleIdentifier) or PID \(context.processIdentifier)")
            return false
        }
        
        // Priority 1: Exact window ID
        if let winID = context.windowIdentifier {
            let raised = windowController.raiseWindow(windowID: winID, pid: app.processIdentifier)
            if raised {
                _ = appController.activate(application: app)
                return true
            }
            logger.info("Exact window #\(winID) not found or cannot be raised; evaluating title/workspace heuristics")
        }
        
        // Priority 2: Workspace folder name title matching
        if let ws = context.workspacePath, !ws.isEmpty {
            let folderName = (ws as NSString).lastPathComponent
            if let matched = windowController.findWindow(matching: folderName, pid: app.processIdentifier) {
                let raised = windowController.raiseWindow(windowID: matched.windowID, pid: app.processIdentifier)
                if raised {
                    _ = appController.activate(application: app)
                    return true
                }
            }
        }
        
        // Priority 3: Captured window title matching
        if let title = context.windowTitle, !title.isEmpty {
            if let matched = windowController.findWindow(matching: title, pid: app.processIdentifier) {
                let raised = windowController.raiseWindow(windowID: matched.windowID, pid: app.processIdentifier)
                if raised {
                    _ = appController.activate(application: app)
                    return true
                }
            }
        }
        
        // Priority 4: Frontmost application activation fallback
        logger.info("Falling back to activating Cursor frontmost application window")
        return appController.activate(application: app)
    }
}
