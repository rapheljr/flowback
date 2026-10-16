import Foundation
import SQLite3
import FlowbackCore
import OSLog

private let logger = Logger(subsystem: "com.flowback.app", category: "SessionRepository")

public actor SessionRepository: SessionStorageDelegate {
    private let db: SQLiteDatabase
    private let jsonEncoder = JSONEncoder()
    private let jsonDecoder = JSONDecoder()
    
    public init(db: SQLiteDatabase) {
        self.db = db
    }
    
    public func saveSession(_ session: AgentSession) async throws {
        let originJson = session.originContext != nil ? try String(data: jsonEncoder.encode(session.originContext), encoding: .utf8) : nil
        let metadataJson = try String(data: jsonEncoder.encode(session.metadata), encoding: .utf8)
        
        let sql = """
        INSERT INTO sessions (
            id, provider_id, provider_session_id, state, task_id, workspace,
            origin_context_json, started_at, updated_at, completed_at, error_description, metadata_json
        ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
        ON CONFLICT(id) DO UPDATE SET
            state = excluded.state,
            task_id = excluded.task_id,
            workspace = excluded.workspace,
            origin_context_json = excluded.origin_context_json,
            updated_at = excluded.updated_at,
            completed_at = excluded.completed_at,
            error_description = excluded.error_description,
            metadata_json = excluded.metadata_json;
        """
        
        try await db.execute(sql: sql, bindings: [
            session.id.rawValue,
            session.providerID.rawValue,
            session.providerSessionID,
            session.state.rawValue,
            session.taskID?.rawValue,
            session.workspace,
            originJson,
            session.startedAt,
            session.updatedAt,
            session.completedAt,
            session.errorDescription,
            metadataJson
        ])
    }
    
    public func fetchSession(id: AgentSessionID) async throws -> AgentSession? {
        let sql = "SELECT * FROM sessions WHERE id = ? LIMIT 1;"
        let rows = try await db.query(sql: sql, bindings: [id.rawValue]) { stmt -> AgentSession in
            try Self.mapRowToSession(stmt)
        }
        return rows.first
    }
    
    public func fetchActiveSessions() async throws -> [AgentSession] {
        let sql = "SELECT * FROM sessions WHERE state IN ('starting', 'running', 'waiting', 'permissionRequired', 'paused') ORDER BY started_at DESC;"
        return try await db.query(sql: sql, bindings: []) { stmt -> AgentSession in
            try Self.mapRowToSession(stmt)
        }
    }
    
    public func fetchRecentSessions(limit: Int = 20) async throws -> [AgentSession] {
        let sql = "SELECT * FROM sessions ORDER BY started_at DESC LIMIT ?;"
        return try await db.query(sql: sql, bindings: [limit]) { stmt -> AgentSession in
            try Self.mapRowToSession(stmt)
        }
    }
    
    /// Prunes finished sessions older than given days while keeping at least `keepMinCount` most recent sessions.
    /// Also cleans up orphaned events associated with pruned sessions.
    @discardableResult
    public func pruneCompletedSessions(olderThanDays days: Int = 30, keepMinCount: Int = 50) async throws -> Int {
        let countSql = "SELECT COUNT(*) FROM sessions;"
        let totalCount = try await db.query(sql: countSql, bindings: []) { stmt in
            Int(sqlite3_column_int(stmt, 0))
        }.first ?? 0
        
        guard totalCount > keepMinCount else { return 0 }
        
        let cutoff = Date().addingTimeInterval(-Double(days * 86400)).timeIntervalSince1970
        let deleteSql = """
        DELETE FROM sessions 
        WHERE state IN ('completed', 'failed', 'stopped', 'cancelled')
          AND updated_at < ?
          AND id NOT IN (
              SELECT id FROM sessions ORDER BY updated_at DESC LIMIT ?
          );
        """
        try await db.execute(sql: deleteSql, bindings: [cutoff, keepMinCount])
        
        // Clean up orphaned events
        let pruneEventsSql = "DELETE FROM events WHERE session_id NOT IN (SELECT id FROM sessions);"
        try await db.execute(sql: pruneEventsSql, bindings: [])
        
        let afterCount = try await db.query(sql: countSql, bindings: []) { stmt in
            Int(sqlite3_column_int(stmt, 0))
        }.first ?? 0
        return max(0, totalCount - afterCount)
    }
    
    private static func mapRowToSession(_ stmt: OpaquePointer) throws -> AgentSession {
        let idStr = String(cString: sqlite3_column_text(stmt, 0))
        let providerStr = String(cString: sqlite3_column_text(stmt, 1))
        
        let providerSessionId: String? = sqlite3_column_type(stmt, 2) != SQLITE_NULL ? String(cString: sqlite3_column_text(stmt, 2)) : nil
        let stateStr = String(cString: sqlite3_column_text(stmt, 3))
        let taskIdStr: String? = sqlite3_column_type(stmt, 4) != SQLITE_NULL ? String(cString: sqlite3_column_text(stmt, 4)) : nil
        let workspace: String? = sqlite3_column_type(stmt, 5) != SQLITE_NULL ? String(cString: sqlite3_column_text(stmt, 5)) : nil
        
        var origin: OriginContext? = nil
        if sqlite3_column_type(stmt, 6) != SQLITE_NULL, let originStr = sqlite3_column_text(stmt, 6) {
            let data = Data(String(cString: originStr).utf8)
            origin = try? JSONDecoder().decode(OriginContext.self, from: data)
        }
        
        let startedAt = Date(timeIntervalSince1970: sqlite3_column_double(stmt, 7))
        let updatedAt = Date(timeIntervalSince1970: sqlite3_column_double(stmt, 8))
        let completedAt: Date? = sqlite3_column_type(stmt, 9) != SQLITE_NULL ? Date(timeIntervalSince1970: sqlite3_column_double(stmt, 9)) : nil
        let errorDesc: String? = sqlite3_column_type(stmt, 10) != SQLITE_NULL ? String(cString: sqlite3_column_text(stmt, 10)) : nil
        
        var metadata: [String: String] = [:]
        if sqlite3_column_type(stmt, 11) != SQLITE_NULL, let metaStr = sqlite3_column_text(stmt, 11) {
            let data = Data(String(cString: metaStr).utf8)
            metadata = (try? JSONDecoder().decode([String: String].self, from: data)) ?? [:]
        }
        
        let state = AgentState(rawValue: stateStr) ?? .unknown
        
        return AgentSession(
            id: AgentSessionID(idStr),
            providerID: AgentProviderID(providerStr),
            providerSessionID: providerSessionId,
            state: state,
            taskID: taskIdStr.map { AgentTaskID($0) },
            workspace: workspace,
            originContext: origin,
            startedAt: startedAt,
            updatedAt: updatedAt,
            completedAt: completedAt,
            errorDescription: errorDesc,
            metadata: metadata
        )
    }
}
