import Foundation
import AppKit
import FlowbackCore
import OSLog

private let logger = Logger(subsystem: "com.flowback.app", category: "WindsurfAdapter")

public struct WindsurfAdapter: ApplicationAdapter {
    public let adapterName = "Windsurf Editor Adapter"
    
    private let supportedBundles: Set<String> = [
        "com.codeium.windsurf"
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
        var targetApp = appController.runningApplication(forProcessIdentifier: context.processIdentifier)
        if targetApp == nil {
            targetApp = appController.runningApplications(withBundleIdentifier: context.bundleIdentifier).first
        }
        
        guard let app = targetApp else {
            logger.warning("Windsurf instance not found for PID \(context.processIdentifier) or bundle \(context.bundleIdentifier)")
            return false
        }
        
        // Priority 1: Exact original window ID
        if let winID = context.windowIdentifier {
            let raised = windowController.raiseWindow(windowID: winID, pid: app.processIdentifier)
            if raised {
                _ = appController.activate(application: app)
                return true
            }
        }
        
        // Priority 2: Same workspace directory title match
        if let ws = context.workspacePath, !ws.isEmpty {
            let folderName = (ws as NSString).lastPathComponent
            if let matched = windowController.findWindow(matching: folderName, pid: app.processIdentifier) {
                _ = windowController.raiseWindow(windowID: matched.windowID, pid: app.processIdentifier)
                _ = appController.activate(application: app)
                return true
            }
        }
        
        // Priority 3: Fallback general app activation
        return appController.activate(application: app)
    }
}
