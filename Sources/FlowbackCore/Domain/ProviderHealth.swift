import Foundation

/// Health and integration status of a specific agent provider
public struct ProviderHealth: Identifiable, Codable, Hashable, Sendable {
    public var id: String { providerID.rawValue }
    public let providerID: AgentProviderID
    public let displayName: String
    public var isInstalled: Bool
    public var version: String?
    public var hookInstalled: Bool
    public var hookExecutable: Bool
    public var configurationPath: String?
    public var lastEventReceivedAt: Date?
    public var totalEventsReceived: Int
    public var statusMessage: String
    public var isSupported: Bool
    
    public init(
        providerID: AgentProviderID,
        displayName: String,
        isInstalled: Bool = false,
        version: String? = nil,
        hookInstalled: Bool = false,
        hookExecutable: Bool = false,
        configurationPath: String? = nil,
        lastEventReceivedAt: Date? = nil,
        totalEventsReceived: Int = 0,
        statusMessage: String = "Not detected",
        isSupported: Bool = true
    ) {
        self.providerID = providerID
        self.displayName = displayName
        self.isInstalled = isInstalled
        self.version = version
        self.hookInstalled = hookInstalled
        self.hookExecutable = hookExecutable
        self.configurationPath = configurationPath
        self.lastEventReceivedAt = lastEventReceivedAt
        self.totalEventsReceived = totalEventsReceived
        self.statusMessage = statusMessage
        self.isSupported = isSupported
    }
    
    public var isHealthy: Bool {
        isInstalled && hookInstalled && hookExecutable
    }
}
