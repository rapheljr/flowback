import Foundation

/// Protects against duplicate agent events within a configurable deduplication window
public actor EventDeduplicator {
    private var seenEvents: [String: Date] = [:]
    private let window: TimeInterval
    
    public init(window: TimeInterval = 1.5) {
        self.window = window
    }
    
    /// Returns true if the event is a new unique event, false if it is a duplicate within the time window
    public func shouldProcess(event: AgentEvent) -> Bool {
        let key = event.deduplicationKey
        let now = Date()
        
        // Clean up expired entries if dictionary grows large
        if seenEvents.count > 500 {
            prune(now: now)
        }
        
        if let lastSeen = seenEvents[key], now.timeIntervalSince(lastSeen) < window {
            return false
        }
        
        seenEvents[key] = now
        return true
    }
    
    private func prune(now: Date) {
        seenEvents = seenEvents.filter { now.timeIntervalSince($0.value) < window * 2 }
    }
    
    public func reset() {
        seenEvents.removeAll()
    }
}
