import Foundation

/// Snapshot of an application window state at a specific point in time
public struct FocusSnapshot: Codable, Hashable, Sendable {
    public let id: String
    public let bundleIdentifier: String
    public let processIdentifier: Int32
    public let windowIdentifier: UInt32?
    public let windowTitle: String?
    public let windowFrame: CGRect?
    public let isMinimized: Bool
    public let isFullscreen: Bool
    public let capturedAt: Date
    
    public init(
        id: String = UUID().uuidString,
        bundleIdentifier: String,
        processIdentifier: Int32,
        windowIdentifier: UInt32? = nil,
        windowTitle: String? = nil,
        windowFrame: CGRect? = nil,
        isMinimized: Bool = false,
        isFullscreen: Bool = false,
        capturedAt: Date = Date()
    ) {
        self.id = id
        self.bundleIdentifier = bundleIdentifier
        self.processIdentifier = processIdentifier
        self.windowIdentifier = windowIdentifier
        self.windowTitle = windowTitle
        self.windowFrame = windowFrame
        self.isMinimized = isMinimized
        self.isFullscreen = isFullscreen
        self.capturedAt = capturedAt
    }
}
