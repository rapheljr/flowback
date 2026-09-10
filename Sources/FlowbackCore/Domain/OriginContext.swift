import Foundation

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
        self.capturedAt = capturedAt
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
