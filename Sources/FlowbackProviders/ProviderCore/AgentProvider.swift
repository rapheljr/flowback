import Foundation
import FlowbackCore
import OSLog

/// Protocol implemented by all agent integrations
public protocol AgentProvider: Sendable {
    var providerID: AgentProviderID { get }
    var displayName: String { get }
    var isSupported: Bool { get }
    
    func checkHealth() async -> ProviderHealth
    func parseLifecyclePayload(data: Data) throws -> AgentEvent?
    func installIntegration() async throws
    func uninstallIntegration() async throws
}

/// Registry coordinating agent providers
public actor ProviderRegistry {
    public static let shared = ProviderRegistry()
    
    private var providers: [AgentProviderID: AgentProvider] = [:]
    
    public init() {}
    
    public func register(provider: AgentProvider) {
        providers[provider.providerID] = provider
    }
    
    public func getProvider(_ id: AgentProviderID) -> AgentProvider? {
        providers[id]
    }
    
    public func allProviders() -> [AgentProvider] {
        Array(providers.values)
    }
    
    public func checkAllHealth() async -> [ProviderHealth] {
        var healths: [ProviderHealth] = []
        for provider in providers.values {
            let h = await provider.checkHealth()
            healths.append(h)
        }
        return healths.sorted { $0.displayName < $1.displayName }
    }
}
