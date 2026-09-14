import Foundation
import AppKit
import FlowbackCore
import OSLog

private let logger = Logger(subsystem: "com.flowback.app", category: "VSCodeAdapter")

public struct VSCodeAdapter: ApplicationAdapter {
    public let adapterName = "Visual Studio Code Adapter"
    
    private let supportedBundles: Set<String> = [
        "com.microsoft.VSCode",
        "com.microsoft.VSCodeInsiders",
        "com.visualstudio.code.oss",
        "com.google.antigravity-ide",
        "com.google.antigravity",
        "com.codeium.windsurf",
        "com.vscodium",
        "com.vscodium.codium",
        "co.posit.positron",
        "com.rstudio.positron",
        "com.byteplus.trae"
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
            logger.warning("VS Code instance not found for bundle \(context.bundleIdentifier)")
            return false
        }
        
        // Priority 1: Exact window ID
        if let winID = context.windowIdentifier {
            let raised = windowController.raiseWindow(windowID: winID, pid: app.processIdentifier)
            if raised {
                _ = appController.activate(application: app)
                return true
            }
        }
        
        // Priority 2: Same workspace window matching
        if let ws = context.workspacePath, !ws.isEmpty {
            let folderName = (ws as NSString).lastPathComponent
            if let matched = windowController.findWindow(matching: folderName, pid: app.processIdentifier) {
                _ = windowController.raiseWindow(windowID: matched.windowID, pid: app.processIdentifier)
                _ = appController.activate(application: app)
                logger.info("Restored VS Code window matching workspace '\(folderName)'")
                return true
            }
        }
        
        // Priority 3: General app activation
        return appController.activate(application: app)
    }
}
