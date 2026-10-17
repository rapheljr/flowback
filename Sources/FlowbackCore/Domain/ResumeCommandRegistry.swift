import Foundation

/// Protocol that integrations implement to provide actionable CLI resume command hints
public protocol ResumeHintProviding: Sendable {
    func resumeCommand(for session: AgentSession) -> String?
}

/// Thread-safe registry coordinating CLI resume command formatting across terminal-based providers
public final class ResumeCommandRegistry: @unchecked Sendable {
    public static let shared = ResumeCommandRegistry()
    
    private let lock = NSLock()
    private var formatters: [AgentProviderID: @Sendable (AgentSession) -> String?] = [:]
    
    public init() {
        registerDefaultFormatters()
    }
    
    public func register(providerID: AgentProviderID, formatter: @escaping @Sendable (AgentSession) -> String?) {
        lock.withLock {
            formatters[providerID] = formatter
        }
    }
    
    public func resumeCommand(for session: AgentSession) -> String? {
        let formatter = lock.withLock { formatters[session.providerID] }
        return formatter?(session)
    }
    
    private func registerDefaultFormatters() {
        // Built-in safe formatters with input validation
        register(providerID: .antigravityCLI) { session in
            guard let convID = session.conversationID ?? session.providerSessionID, !convID.isEmpty else {
                return nil
            }
            let formattedID = convID.contains(" ") ? "\"\(convID)\"" : convID
            return "agy --conversation \(formattedID)"
        }
        
        register(providerID: .claudeCode) { session in
            guard let convID = session.conversationID ?? session.providerSessionID, !convID.isEmpty else {
                return nil
            }
            let formattedID = convID.contains(" ") ? "\"\(convID)\"" : convID
            return "claude resume \(formattedID)"
        }
    }
}
