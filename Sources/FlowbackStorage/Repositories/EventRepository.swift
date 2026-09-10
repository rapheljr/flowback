import Foundation
import SQLite3
import FlowbackCore
import OSLog

public actor EventRepository {
    private let db: SQLiteDatabase
    private let jsonEncoder = JSONEncoder()
    
    public init(db: SQLiteDatabase) {
        self.db = db
    }
    
    public func saveEvent(_ event: AgentEvent) async throws {
        let metadataJson = try String(data: jsonEncoder.encode(event.metadata), encoding: .utf8)
        let sql = """
        INSERT INTO events (id, timestamp, provider_id, session_id, type, workspace, metadata_json)
        VALUES (?, ?, ?, ?, ?, ?, ?);
        """
        try await db.execute(sql: sql, bindings: [
            event.id,
            event.timestamp,
            event.providerID.rawValue,
            event.sessionID.rawValue,
            event.type.rawValue,
            event.workspace,
            metadataJson
        ])
    }
    
    public func fetchEvents(for sessionID: AgentSessionID, limit: Int = 100) async throws -> [AgentEvent] {
        let sql = "SELECT * FROM events WHERE session_id = ? ORDER BY timestamp ASC LIMIT ?;"
        return try await db.query(sql: sql, bindings: [sessionID.rawValue, limit]) { stmt -> AgentEvent in
            let id = String(cString: sqlite3_column_text(stmt, 0))
            let timestamp = Date(timeIntervalSince1970: sqlite3_column_double(stmt, 1))
            let providerStr = String(cString: sqlite3_column_text(stmt, 2))
            let sessionStr = String(cString: sqlite3_column_text(stmt, 3))
            let typeStr = String(cString: sqlite3_column_text(stmt, 4))
            let workspace: String? = sqlite3_column_type(stmt, 5) != SQLITE_NULL ? String(cString: sqlite3_column_text(stmt, 5)) : nil
            
            var metadata: [String: String] = [:]
            if sqlite3_column_type(stmt, 6) != SQLITE_NULL, let metaStr = sqlite3_column_text(stmt, 6) {
                let data = Data(String(cString: metaStr).utf8)
                metadata = (try? JSONDecoder().decode([String: String].self, from: data)) ?? [:]
            }
            
            return AgentEvent(
                id: id,
                timestamp: timestamp,
                providerID: AgentProviderID(providerStr),
                sessionID: AgentSessionID(sessionStr),
                type: AgentEventType(rawValue: typeStr) ?? .agentRunning,
                workspace: workspace,
                metadata: metadata
            )
        }
    }
}
