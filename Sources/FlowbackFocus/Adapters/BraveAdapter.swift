import Foundation
import AppKit
import FlowbackCore
import OSLog

private let logger = Logger(subsystem: "com.flowback.app", category: "BraveAdapter")

public struct BraveAdapter: ApplicationAdapter {
    public let adapterName = "Web Browser Adapter"

    private let supportedBundles: Set<String> = [
        "com.brave.Browser",
        "com.google.Chrome",
        "company.thebrowser.Browser",
        "com.apple.Safari",
        "org.mozilla.firefox"
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
        if let urlStr = context.workspacePath ?? context.workspaceIdentifier,
           let url = URL(string: urlStr),
           let scheme = url.scheme?.lowercased(),
           scheme == "http" || scheme == "https" {
            let opened = NSWorkspace.shared.open(url)
            if opened { return true }
        }

        var targetApp = appController.runningApplication(forProcessIdentifier: context.processIdentifier)
        if targetApp == nil {
            targetApp = appController.runningApplications(withBundleIdentifier: context.bundleIdentifier).first
        }

        guard let app = targetApp else { return false }

        if let winID = context.windowIdentifier {
            _ = windowController.raiseWindow(windowID: winID, pid: app.processIdentifier)
        }

        return appController.activate(application: app)
    }
}
