import Foundation
import AppKit
import FlowbackCore
import OSLog

private let logger = Logger(subsystem: "com.flowback.app", category: "CursorAdapter")

public struct CursorAdapter: ApplicationAdapter {
    public let adapterName = "Cursor Editor Adapter"
    
    private let supportedBundles: Set<String> = [
        "com.todesktop.230313mzl4w4u92",
        "co.anysphere.cursor"
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
        
        guard let app = targetApp else { return false }
        
        if let winID = context.windowIdentifier {
            let raised = windowController.raiseWindow(windowID: winID, pid: app.processIdentifier)
            if raised {
                _ = appController.activate(application: app)
                return true
            }
        }
        
        if let ws = context.workspacePath, !ws.isEmpty {
            let folderName = (ws as NSString).lastPathComponent
            if let matched = windowController.findWindow(matching: folderName, pid: app.processIdentifier) {
                _ = windowController.raiseWindow(windowID: matched.windowID, pid: app.processIdentifier)
                _ = appController.activate(application: app)
                return true
            }
        }
        
        return appController.activate(application: app)
    }
}
