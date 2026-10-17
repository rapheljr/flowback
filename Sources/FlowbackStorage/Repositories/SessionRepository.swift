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
        let colCount = sqlite3_column_count(stmt)

        let idStr = String(cString: sqlite3_column_text(stmt, 0))
        let providerStr = String(cString: sqlite3_column_text(stmt, 1))

        let providerSessionId: String? = sqlite3_column_type(stmt, 2) != SQLITE_NULL ? String(cString: sqlite3_column_text(stmt, 2)) : nil
        let stateStr = String(cString: sqlite3_column_text(stmt, 3))
        let taskIdStr: String? = sqlite3_column_type(stmt, 4) != SQLITE_NULL ? String(cString: sqlite3_column_text(stmt, 4)) : nil
        let workspace: String? = sqlite3_column_type(stmt, 5) != SQLITE_NULL ? String(cString: sqlite3_column_text(stmt, 5)) : nil

        var origin: OriginContext?
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

        // V2 Migration fields (nullable with backwards-compatible defaults)
        var convTitle: String?
        var convId: String?
        var taskSummary: String?
        var execId: String?
        var parentSessId: AgentSessionID?
        var convUrl: URL?
        var focusCap: ConversationFocusCapability?
        var isRemote = false

        if colCount > 12 && sqlite3_column_type(stmt, 12) != SQLITE_NULL {
            convTitle = String(cString: sqlite3_column_text(stmt, 12))
        }
        if colCount > 13 && sqlite3_column_type(stmt, 13) != SQLITE_NULL {
            convId = String(cString: sqlite3_column_text(stmt, 13))
        }
        if colCount > 14 && sqlite3_column_type(stmt, 14) != SQLITE_NULL {
            taskSummary = String(cString: sqlite3_column_text(stmt, 14))
        }
        if colCount > 15 && sqlite3_column_type(stmt, 15) != SQLITE_NULL {
            execId = String(cString: sqlite3_column_text(stmt, 15))
        }
        if colCount > 16 && sqlite3_column_type(stmt, 16) != SQLITE_NULL {
            parentSessId = AgentSessionID(String(cString: sqlite3_column_text(stmt, 16)))
        }
        if colCount > 17 && sqlite3_column_type(stmt, 17) != SQLITE_NULL {
            convUrl = URL(string: String(cString: sqlite3_column_text(stmt, 17)))
        }
        if colCount > 18 && sqlite3_column_type(stmt, 18) != SQLITE_NULL {
            focusCap = ConversationFocusCapability(rawValue: String(cString: sqlite3_column_text(stmt, 18)))
        }
        if colCount > 19 {
            isRemote = sqlite3_column_int(stmt, 19) != 0
        }

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
