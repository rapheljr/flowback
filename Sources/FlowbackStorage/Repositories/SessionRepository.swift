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
            origin_context_json, started_at, updated_at, completed_at, error_description, metadata_json,
            conversation_title, conversation_id, task_summary, execution_id, parent_session_id, conversation_url, focus_capability, is_remote
        ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
        ON CONFLICT(id) DO UPDATE SET
            state = excluded.state,
            task_id = excluded.task_id,
            workspace = excluded.workspace,
            origin_context_json = excluded.origin_context_json,
            updated_at = excluded.updated_at,
            completed_at = excluded.completed_at,
            error_description = excluded.error_description,
            metadata_json = excluded.metadata_json,
            conversation_title = excluded.conversation_title,
            conversation_id = excluded.conversation_id,
            task_summary = excluded.task_summary,
            execution_id = excluded.execution_id,
            parent_session_id = excluded.parent_session_id,
            conversation_url = excluded.conversation_url,
            focus_capability = excluded.focus_capability,
            is_remote = excluded.is_remote;
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
            metadataJson,
            session.conversationTitle,
            session.conversationID,
            session.taskSummary,
            session.executionID,
            session.parentSessionID?.rawValue,
            session.conversationURL?.absoluteString,
            session.focusCapability.rawValue,
            session.isRemote ? 1 : 0
        ])
    }

    public static let sessionColumnsProjection = """
        id, provider_id, provider_session_id, state, task_id, workspace, \
        origin_context_json, started_at, updated_at, completed_at, error_description, metadata_json, \
        conversation_title, conversation_id, task_summary, execution_id, parent_session_id, \
        conversation_url, focus_capability, is_remote
        """

    public func fetchSession(id: AgentSessionID) async throws -> AgentSession? {
        let sql = "SELECT \(Self.sessionColumnsProjection) FROM sessions WHERE id = ? LIMIT 1;"
        let rows = try await db.query(sql: sql, bindings: [id.rawValue]) { stmt -> AgentSession in
            try Self.mapRowToSession(stmt)
        }
        return rows.first
    }

    public func fetchActiveSessions() async throws -> [AgentSession] {
        let sql = "SELECT \(Self.sessionColumnsProjection) FROM sessions WHERE state IN ('starting', 'running', 'waiting', 'permissionRequired', 'paused') ORDER BY started_at DESC;"
        return try await db.query(sql: sql, bindings: []) { stmt -> AgentSession in
            try Self.mapRowToSession(stmt)
        }
    }

    public func fetchRecentSessions(limit: Int = 20) async throws -> [AgentSession] {
        let sql = "SELECT \(Self.sessionColumnsProjection) FROM sessions ORDER BY started_at DESC LIMIT ?;"
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
        let colCount = sqlite3_column_count(stmt)
        var colMap: [String: Int32] = [:]
        for i in 0..<colCount {
            if let namePtr = sqlite3_column_name(stmt, i) {
                colMap[String(cString: namePtr)] = i
            }
        }

        func colIdx(_ name: String, fallback: Int32) -> Int32? {
            if let found = colMap[name] {
                return found
            }
            return fallback < colCount ? fallback : nil
        }

        func textVal(_ name: String, altName: String? = nil, fallback: Int32) -> String? {
            let idx = colIdx(name, fallback: fallback) ?? (altName.flatMap { colIdx($0, fallback: fallback) })
            guard let validIdx = idx,
                  sqlite3_column_type(stmt, validIdx) != SQLITE_NULL,
                  let ptr = sqlite3_column_text(stmt, validIdx) else {
                return nil
            }
            return String(cString: ptr)
        }

        func doubleVal(_ name: String, fallback: Int32) -> Double? {
            guard let idx = colIdx(name, fallback: fallback),
                  sqlite3_column_type(stmt, idx) != SQLITE_NULL else {
                return nil
            }
            return sqlite3_column_double(stmt, idx)
        }

        func intVal(_ name: String, fallback: Int32) -> Int32? {
            guard let idx = colIdx(name, fallback: fallback),
                  sqlite3_column_type(stmt, idx) != SQLITE_NULL else {
                return nil
            }
            return sqlite3_column_int(stmt, idx)
        }

        let idStr = textVal("id", fallback: 0) ?? ""
        let providerStr = textVal("provider_id", fallback: 1) ?? ""
        let providerSessionId = textVal("provider_session_id", fallback: 2)
        let stateStr = textVal("state", fallback: 3) ?? "unknown"
        let taskIdStr = textVal("task_id", fallback: 4)
        let workspace = textVal("workspace", fallback: 5)

        var origin: OriginContext?
        if let originStr = textVal("origin_context_json", altName: "origin_context", fallback: 6) {
            let data = Data(originStr.utf8)
            origin = try? JSONDecoder().decode(OriginContext.self, from: data)
        }

        let startedAt = Date(timeIntervalSince1970: doubleVal("started_at", fallback: 7) ?? 0)
        let updatedAt = Date(timeIntervalSince1970: doubleVal("updated_at", fallback: 8) ?? 0)
        let completedAt: Date? = doubleVal("completed_at", fallback: 9).map { Date(timeIntervalSince1970: $0) }
        let errorDesc = textVal("error_description", fallback: 10)

        var metadata: [String: String] = [:]
        if let metaStr = textVal("metadata_json", altName: "metadata", fallback: 11) {
            let data = Data(metaStr.utf8)
            metadata = (try? JSONDecoder().decode([String: String].self, from: data)) ?? [:]
        }

        let state = AgentState(rawValue: stateStr) ?? .unknown

        // V2 Migration fields (nullable with backwards-compatible defaults)
        var convTitle = textVal("conversation_title", fallback: 12)
        var convId = textVal("conversation_id", fallback: 13)
        var taskSummary = textVal("task_summary", fallback: 14)
        var execId = textVal("execution_id", fallback: 15)
        var parentSessId = textVal("parent_session_id", fallback: 16).map { AgentSessionID($0) }
        var convUrl = textVal("conversation_url", fallback: 17).flatMap { URL(string: $0) }
        let focusCap = textVal("focus_capability", fallback: 18).flatMap { ConversationFocusCapability(rawValue: $0) }
        let isRemote = (intVal("is_remote", fallback: 19) ?? 0) != 0

        // Fallbacks from metadata if V1 row
        if convTitle == nil { convTitle = metadata["title"] ?? metadata["conversation_title"] }
        if convId == nil { convId = providerSessionId ?? metadata["conversationId"] ?? metadata["sessionId"] }
        if taskSummary == nil { taskSummary = metadata["summary"] }
        if execId == nil { execId = metadata["executionId"] ?? metadata["latestRunId"] }
        if parentSessId == nil, let pStr = metadata["parentSessionId"] { parentSessId = AgentSessionID(pStr) }
        if convUrl == nil, let uStr = metadata["conversationUrl"] ?? metadata["prUrl"] { convUrl = URL(string: uStr) }

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
            metadata: metadata,
            conversationID: convId,
            conversationTitle: convTitle,
            taskSummary: taskSummary,
            executionID: execId,
            parentSessionID: parentSessId,
            conversationURL: convUrl,
            focusCapability: focusCap,
            isRemote: isRemote
        )
    }
}
