import Foundation

/// Central asynchronous event distribution bus for Flowback
public actor EventBus {
    public static let shared = EventBus()
    
    private var agentContinuations: [UUID: AsyncStream<AgentEvent>.Continuation] = [:]
    private var focusContinuations: [UUID: AsyncStream<FocusEvent>.Continuation] = [:]
    private var attentionContinuations: [UUID: AsyncStream<AttentionRequest>.Continuation] = [:]
    
    private let deduplicator: EventDeduplicator
    
    public init(deduplicationWindow: TimeInterval = 1.5) {
        self.deduplicator = EventDeduplicator(window: deduplicationWindow)
    }
    
    // MARK: - Publishing
    
    /// Publish an agent event; drops duplicates if within the deduplication window
    public func publish(agentEvent: AgentEvent) async {
        let isNew = await deduplicator.shouldProcess(event: agentEvent)
        guard isNew else { return }
        
        for continuation in agentContinuations.values {
            continuation.yield(agentEvent)
        }
    }
    
    /// Publish a system focus event
    public func publish(focusEvent: FocusEvent) {
        for continuation in focusContinuations.values {
            continuation.yield(focusEvent)
        }
    }
    
    /// Publish an attention request
    public func publish(attentionRequest: AttentionRequest) {
        for continuation in attentionContinuations.values {
            continuation.yield(attentionRequest)
        }
    }
    
    // MARK: - Subscriptions
    
    /// Subscribes to the stream of AgentEvents
    public func agentEvents() -> AsyncStream<AgentEvent> {
        let id = UUID()
        return AsyncStream { continuation in
            agentContinuations[id] = continuation
            continuation.onTermination = { [weak self] _ in
                Task { [weak self] in
                    await self?.removeAgentSubscription(id: id)
                }
            }
        }
    }
    
    /// Subscribes to the stream of FocusEvents
    public func focusEvents() -> AsyncStream<FocusEvent> {
        let id = UUID()
        return AsyncStream { continuation in
            focusContinuations[id] = continuation
            continuation.onTermination = { [weak self] _ in
                Task { [weak self] in
                    await self?.removeFocusSubscription(id: id)
                }
            }
        }
    }
    
    /// Subscribes to the stream of AttentionRequests
    public func attentionRequests() -> AsyncStream<AttentionRequest> {
        let id = UUID()
        return AsyncStream { continuation in
            attentionContinuations[id] = continuation
            continuation.onTermination = { [weak self] _ in
                Task { [weak self] in
                    await self?.removeAttentionSubscription(id: id)
                }
            }
        }
    }
    
    private func removeAgentSubscription(id: UUID) {
        agentContinuations.removeValue(forKey: id)
    }
    
    private func removeFocusSubscription(id: UUID) {
        focusContinuations.removeValue(forKey: id)
    }
    
    private func removeAttentionSubscription(id: UUID) {
        attentionContinuations.removeValue(forKey: id)
    }
}
