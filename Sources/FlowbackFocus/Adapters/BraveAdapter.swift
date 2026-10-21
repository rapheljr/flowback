import Foundation
import AppKit
import FlowbackCore
import OSLog

private let logger = Logger(subsystem: "com.flowback.app", category: "BraveAdapter")

public struct BraveAdapter: ApplicationAdapter {
    public let adapterName = "Web Browser Adapter"

    private let supportedBundles: Set<String> = [
        "com.brave.Browser",
        "com.brave.Browser.beta",
        "com.brave.Browser.nightly",
        "com.google.Chrome",
        "com.google.Chrome.canary",
        "company.thebrowser.Browser",
        "com.apple.Safari",
        "org.mozilla.firefox",
        "com.microsoft.edgemac",
        "com.operasoftware.Opera",
        "com.vivaldi.Vivaldi"
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

        guard !Task.isCancelled else { return false }

        if let winID = context.windowIdentifier {
            if windowController.raiseWindow(windowID: winID, pid: app.processIdentifier) {
                guard !Task.isCancelled else { return false }
                return await appController.activateApplication(app)
            }
        }

        guard !Task.isCancelled else { return false }

        if let title = context.windowTitle, !title.isEmpty,
           let matched = windowController.findWindow(matching: title, pid: app.processIdentifier),
           windowController.raiseWindow(windowID: matched.windowID, pid: app.processIdentifier) {
            guard !Task.isCancelled else { return false }
            return await appController.activateApplication(app)
        }

        guard !Task.isCancelled else { return false }

        return await appController.activateApplication(app)
    }
}
