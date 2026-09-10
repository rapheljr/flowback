import Foundation
import AppKit
import FlowbackCore
import OSLog

private let logger = Logger(subsystem: "com.flowback.app", category: "TerminalAdapter")

public struct TerminalAdapter: ApplicationAdapter {
    public let adapterName = "Terminal & Shell Adapter"
    
    private let supportedBundles: Set<String> = [
        "com.apple.Terminal",
        "com.googlecode.iterm2",
        "com.mitchellh.ghostty",
        "dev.warp.Warp-Stable",
        "co.zeit.hyper"
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
        
        // Try raising specific window ID
        if let winID = context.windowIdentifier {
            if windowController.raiseWindow(windowID: winID, pid: app.processIdentifier) {
                return appController.activate(application: app)
            }
        }
        
        // Try matching window by directory name
        if let ws = context.workspacePath, !ws.isEmpty {
            let dirName = (ws as NSString).lastPathComponent
            if let matched = windowController.findWindow(matching: dirName, pid: app.processIdentifier) {
                _ = windowController.raiseWindow(windowID: matched.windowID, pid: app.processIdentifier)
                return appController.activate(application: app)
            }
        }
        
        return appController.activate(application: app)
    }
}
