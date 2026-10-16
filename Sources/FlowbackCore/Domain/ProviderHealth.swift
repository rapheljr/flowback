import Foundation

/// Explicit tier of integration support for an agent provider
public enum ProviderSupportLevel: String, Codable, Sendable {
    case nativeLifecycle = "native-lifecycle"
    case adapter = "adapter"
    case genericProtocol = "generic-protocol"
    case contextOnly = "context-only"
    case partial = "partial"
    case planned = "planned"
}

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
    public var supportLevel: ProviderSupportLevel
    
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
        isSupported: Bool = true,
        supportLevel: ProviderSupportLevel = .adapter
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
        self.supportLevel = supportLevel
    }
    
    public var isHealthy: Bool {
        isInstalled && hookInstalled && hookExecutable
    }
}
