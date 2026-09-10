import Foundation
import SQLite3
import FlowbackCore
import OSLog

private let logger = Logger(subsystem: "com.flowback.app", category: "SettingsRepository")

public actor SettingsRepository {
    private let db: SQLiteDatabase
    private let jsonEncoder = JSONEncoder()
    private let jsonDecoder = JSONDecoder()
    
    public init(db: SQLiteDatabase) {
        self.db = db
    }
    
    public func saveConfiguration(_ config: PolicyConfiguration) async throws {
        let data = try jsonEncoder.encode(config)
        guard let jsonString = String(data: data, encoding: .utf8) else { return }
        
        let sql = """
        INSERT INTO settings (key, value_json) VALUES ('policy_configuration', ?)
        ON CONFLICT(key) DO UPDATE SET value_json = excluded.value_json;
        """
        try await db.execute(sql: sql, bindings: [jsonString])
    }
    
    public func loadConfiguration() async -> PolicyConfiguration {
        let sql = "SELECT value_json FROM settings WHERE key = 'policy_configuration' LIMIT 1;"
        do {
            let rows: [String] = try await db.query(sql: sql, bindings: []) { stmt in
                String(cString: sqlite3_column_text(stmt, 0))
            }
            if let first = rows.first, let data = first.data(using: .utf8) {
                return try jsonDecoder.decode(PolicyConfiguration.self, from: data)
            }
        } catch {
            logger.error("Failed to load settings from database: \(error.localizedDescription)")
        }
        return PolicyConfiguration.default
    }
}
