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

        // Step 3: Activate application
        let activated = await appController.activateApplication(app)
        
        guard !Task.isCancelled else { return false }

        // Step 4: If exact window exists, raise it
        if let winID = context.windowIdentifier {
            _ = windowController.raiseWindow(windowID: winID, pid: app.processIdentifier)
        }
        
        return activated
    }
}
