import Foundation
import AppKit
import FlowbackCore
import OSLog

private let logger = Logger(subsystem: "com.flowback.app", category: "GenericApplicationAdapter")

/// Universal fallback adapter that restores application focus and attempts window raising
public struct GenericApplicationAdapter: ApplicationAdapter {
    public let adapterName = "Generic Application Adapter"
    
    public init() {}
    
    public func canHandle(bundleIdentifier: String) -> Bool {
        true // Fallback handles any application
    }
    
    public func restoreContext(
        context: OriginContext,
        appController: ApplicationControlling,
        windowController: WindowControlling
    ) async -> Bool {
        // Step 1: Find by process ID
        var targetApp = appController.runningApplication(forProcessIdentifier: context.processIdentifier)
        
        // Step 2: Fallback to bundle identifier if process terminated or changed
        if targetApp == nil {
            let apps = appController.runningApplications(withBundleIdentifier: context.bundleIdentifier)
            targetApp = apps.first
        }
        
        guard let app = targetApp else {
            logger.warning("Could not find running instance of \(context.bundleIdentifier)")
            return false
        }
        
        guard !Task.isCancelled else { return false }

        // Priority 1: If exact window exists, raise it before activating the app
        if let winID = context.windowIdentifier {
            if windowController.raiseWindow(windowID: winID, pid: app.processIdentifier) {
                guard !Task.isCancelled else { return false }
                return await appController.activateApplication(app)
            }
        }

        guard !Task.isCancelled else { return false }

        // Priority 2: Match window by workspace folder name
        if let ws = context.workspacePath, !ws.isEmpty {
            let folderName = (ws as NSString).lastPathComponent
            if let matched = windowController.findWindow(matching: folderName, pid: app.processIdentifier),
               windowController.raiseWindow(windowID: matched.windowID, pid: app.processIdentifier) {
                guard !Task.isCancelled else { return false }
                return await appController.activateApplication(app)
            }
        }

        guard !Task.isCancelled else { return false }

        // Priority 3: Match window by captured window title
        if let title = context.windowTitle, !title.isEmpty {
            if let matched = windowController.findWindow(matching: title, pid: app.processIdentifier),
               windowController.raiseWindow(windowID: matched.windowID, pid: app.processIdentifier) {
                guard !Task.isCancelled else { return false }
                return await appController.activateApplication(app)
            }
        }

        guard !Task.isCancelled else { return false }

        // Priority 4: General application activation fallback
        return await appController.activateApplication(app)
    }
}
