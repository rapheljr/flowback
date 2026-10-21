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

    public let maxEntriesPerSession: Int
    public let maxTrackedSessions: Int
    private var entriesBySession: [AgentSessionID: [TimelineEntry]] = [:]

    public init(maxEntriesPerSession: Int = 50, maxTrackedSessions: Int = 100) {
        self.maxEntriesPerSession = maxEntriesPerSession
        self.maxTrackedSessions = maxTrackedSessions
    }

    public func record(
        sessionID: AgentSessionID,
        category: String,
        summary: String,
        details: String? = nil,
        explanation: String? = nil
    ) {
        let cleanSummary = SecretSanitizer.sanitizeText(summary)
        let cleanDetails = details.map { SecretSanitizer.sanitizeText($0) }
        let cleanExplanation = explanation.map { SecretSanitizer.sanitizeText($0) }
        let entry = TimelineEntry(
            sessionID: sessionID,
            category: category,
            summary: cleanSummary,
            details: cleanDetails,
            decisionExplanation: cleanExplanation
        )
        var list = entriesBySession[sessionID] ?? []
        list.append(entry)
        if list.count > maxEntriesPerSession {
            list.removeFirst(list.count - maxEntriesPerSession)
        }
        entriesBySession[sessionID] = list

        // Evict oldest session history if total sessions exceed bound
        if entriesBySession.count > maxTrackedSessions {
            let sortedByLatest = entriesBySession.compactMap { (sessID, entries) -> (AgentSessionID, Date)? in
                guard let lastDate = entries.last?.timestamp else { return nil }
                return (sessID, lastDate)
            }.sorted { $0.1 < $1.1 }

            let excess = entriesBySession.count - maxTrackedSessions
            for i in 0..<min(excess, sortedByLatest.count) {
                entriesBySession.removeValue(forKey: sortedByLatest[i].0)
            }
        }
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
