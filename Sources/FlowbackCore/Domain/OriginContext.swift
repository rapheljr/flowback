import Foundation

/// Origin context provenance indicating how the context was observed
public enum ContextProvenance: String, Codable, Sendable {
    case nativeHook = "native_hook"
    case providerTranscript = "provider_transcript"
    case systemFrontmost = "system_frontmost"
    case ipcExplicit = "ipc_explicit"
    case inferred = "inferred"
}

/// Restoration capabilities indicating what level of context restoration can be executed
public enum RestorationCapability: String, Codable, Sendable {
    case exactWindowAndWorkspace = "exact_window_and_workspace"
    case workspaceWindow = "workspace_window"
    case applicationActivationOnly = "app_activation_only"
    case notificationFallbackOnly = "notification_fallback_only"
    case unsupported = "unsupported"
}

/// Captures where the user was when an agent session originated
public struct OriginContext: Codable, Hashable, Sendable {
    public let bundleIdentifier: String
    public let applicationPath: String?
    public let processIdentifier: Int32
    public let windowIdentifier: UInt32?
    public let windowTitle: String?
    public let workspacePath: String?
    public let workspaceIdentifier: String?
    public let terminalIdentifier: String?
    public let spaceIdentifier: String?
    public let provenance: ContextProvenance
    public let confidence: Double
    public let restorationCapability: RestorationCapability
    public let capturedAt: Date
    
    public init(
        bundleIdentifier: String,
        applicationPath: String? = nil,
        processIdentifier: Int32,
        windowIdentifier: UInt32? = nil,
        windowTitle: String? = nil,
        workspacePath: String? = nil,
        workspaceIdentifier: String? = nil,
        terminalIdentifier: String? = nil,
        spaceIdentifier: String? = nil,
        provenance: ContextProvenance = .nativeHook,
        confidence: Double = 1.0,
        restorationCapability: RestorationCapability = .exactWindowAndWorkspace,
        capturedAt: Date = Date()
    ) {
        self.bundleIdentifier = bundleIdentifier
        self.applicationPath = applicationPath
        self.processIdentifier = processIdentifier
        self.windowIdentifier = windowIdentifier
        self.windowTitle = windowTitle
        self.workspacePath = workspacePath
        self.workspaceIdentifier = workspaceIdentifier
        self.terminalIdentifier = terminalIdentifier
        self.spaceIdentifier = spaceIdentifier
        self.provenance = provenance
        self.confidence = min(max(confidence, 0.0), 1.0)
        self.restorationCapability = restorationCapability
        self.capturedAt = capturedAt
    }
    
    /// Checks if the captured context was recorded within the given freshness window
    public func isFresh(within seconds: Double) -> Bool {
        Date().timeIntervalSince(capturedAt) <= seconds
    }
    
    /// Returns a copy of this context with `windowIdentifier` cleared for application-level fallback
    public func withoutWindowIdentifier() -> OriginContext {
        OriginContext(
            bundleIdentifier: bundleIdentifier,
            applicationPath: applicationPath,
            processIdentifier: processIdentifier,
            windowIdentifier: nil,
            windowTitle: windowTitle,
            workspacePath: workspacePath,
            workspaceIdentifier: workspaceIdentifier,
            terminalIdentifier: terminalIdentifier,
            spaceIdentifier: spaceIdentifier,
            provenance: provenance,
            confidence: confidence,
            restorationCapability: .applicationActivationOnly,
            capturedAt: capturedAt
        )
    }
    
    /// User-friendly label for display
    public var displayLabel: String {
        if let workspace = workspacePath, !workspace.isEmpty {
            let lastComponent = (workspace as NSString).lastPathComponent
            return "\(bundleName) — \(lastComponent)"
        } else if let title = windowTitle, !title.isEmpty {
            return "\(bundleName) — \(title)"
        } else {
            return bundleName
        }
    }
    
    public var bundleName: String {
        if let path = applicationPath {
            return ((path as NSString).lastPathComponent as NSString).deletingPathExtension
        }
        let parts = bundleIdentifier.split(separator: ".")
        return parts.last.map(String.init) ?? bundleIdentifier
    }
}
