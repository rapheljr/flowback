import Foundation

/// A discrete step or decision recorded in a session's history
public struct TimelineEntry: Identifiable, Codable, Hashable, Sendable {
    public let id: String
    public let sessionID: AgentSessionID
    public let timestamp: Date
    public let category: String
    public let summary: String
    public let details: String?
    public let decisionExplanation: String?
    
    public init(
        id: String = UUID().uuidString,
        sessionID: AgentSessionID,
        timestamp: Date = Date(),
        category: String,
        summary: String,
        details: String? = nil,
        decisionExplanation: String? = nil
    ) {
        self.id = id
        self.sessionID = sessionID
        self.timestamp = timestamp
        self.category = category
        self.summary = summary
        self.details = details
        self.decisionExplanation = decisionExplanation
    }
    
    public var formattedTime: String {
        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm:ss"
        return formatter.string(from: timestamp)
    }
}

/// In-memory timeline tracker actor coordinating session event histories
public actor TimelineTracker {
    public static let shared = TimelineTracker()
    
    private var entriesBySession: [AgentSessionID: [TimelineEntry]] = [:]
    
    public init() {}
    
    public func record(
        sessionID: AgentSessionID,
        category: String,
        summary: String,
        details: String? = nil,
        explanation: String? = nil
    ) {
        let entry = TimelineEntry(
            sessionID: sessionID,
            category: category,
            summary: summary,
            details: details,
            decisionExplanation: explanation
        )
        var list = entriesBySession[sessionID] ?? []
        list.append(entry)
        entriesBySession[sessionID] = list
    }
    
    public func entries(for sessionID: AgentSessionID) -> [TimelineEntry] {
        entriesBySession[sessionID] ?? []
    }
    
    public func allRecentEntries(limit: Int = 100) -> [TimelineEntry] {
        let all = entriesBySession.values.flatMap { $0 }
        return all.sorted { $0.timestamp > $1.timestamp }.prefix(limit).map { $0 }
    }
    
    public func clear(for sessionID: AgentSessionID) {
        entriesBySession.removeValue(forKey: sessionID)
    }
}
