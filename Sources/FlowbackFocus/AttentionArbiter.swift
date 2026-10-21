import Foundation
import FlowbackCore
import OSLog

private let logger = Logger(subsystem: "com.flowback.app", category: "AttentionArbiter")

/// Manages multi-agent attention requests, aggregation windows, priority queues, and focus cooldowns
public actor AttentionArbiter {
    private var pendingQueue: [AttentionRequest] = []
    private var lastFocusRestorationTime: Date = .distantPast
    private(set) public var aggregationWindow: TimeInterval
    private(set) public var cooldownDuration: TimeInterval
    
    public init(
        aggregationWindow: TimeInterval = 1.5,
        cooldownDuration: TimeInterval = 1.0
    ) {
        self.aggregationWindow = aggregationWindow
        self.cooldownDuration = cooldownDuration
    }

    /// Dynamically updates arbitration timing parameters when configuration changes
    public func updateTiming(aggregationWindow: TimeInterval, cooldownDuration: TimeInterval) {
        self.aggregationWindow = max(0, aggregationWindow)
        self.cooldownDuration = max(0, cooldownDuration)
    }
    
    /// Enqueues an attention request, sorted by priority (highest first) and then timestamp
    public func enqueue(_ request: AttentionRequest) {
        // Remove existing request for the same session if new one has equal or higher priority
        pendingQueue.removeAll { $0.sessionID == request.sessionID && $0.priority <= request.priority }
        
        pendingQueue.append(request)
        pendingQueue.sort {
            if $0.priority != $1.priority {
                return $0.priority > $1.priority
            }
            return $0.requestedAt < $1.requestedAt
        }
        
        logger.info("Enqueued attention request for \(request.providerID.rawValue), queue size: \(self.pendingQueue.count)")
    }
    
    /// Checks if a focus action can be taken right now, respecting cooldown
    public func canRestoreFocusNow() -> Bool {
        Date().timeIntervalSince(lastFocusRestorationTime) >= cooldownDuration
    }
    
    /// Records that focus was just changed
    public func recordFocusRestoration() {
        lastFocusRestorationTime = Date()
    }
    
    /// Returns the highest priority pending attention request
    public func dequeueHighestPriority() -> AttentionRequest? {
        guard !pendingQueue.isEmpty else { return nil }
        return pendingQueue.removeFirst()
    }
    
    /// Peeks at all currently pending requests
    public func pendingRequests() -> [AttentionRequest] {
        pendingQueue
    }
    
    /// Generates a merged summary title and message if multiple requests are waiting
    public func aggregatedSummary() -> (title: String, message: String)? {
        guard !pendingQueue.isEmpty else { return nil }
        
        if pendingQueue.count == 1 {
            let single = pendingQueue[0]
            return (single.title, single.message)
        }
        
        let count = pendingQueue.count
        let title = "\(count) agents need attention"
        let items = pendingQueue.prefix(3).map {
            let ws = $0.workspace.map { ($0 as NSString).lastPathComponent } ?? "Session"
            return "\($0.providerID.rawValue) — \(ws)"
        }
        let message = items.joined(separator: "\n")
        return (title, message)
    }
    
    public func remove(sessionID: AgentSessionID) {
        pendingQueue.removeAll { $0.sessionID == sessionID }
    }
    
    public func clear() {
        pendingQueue.removeAll()
    }
}
