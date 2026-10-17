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

    public func exportConfigurationJSON() async throws -> String {
        let config = await loadConfiguration()
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let data = try encoder.encode(config)
        guard let string = String(data: data, encoding: .utf8) else {
            throw SettingsRepositoryError.encodingFailed
        }
        return string
    }

    @discardableResult
    public func importConfigurationJSON(_ jsonString: String) async throws -> PolicyConfiguration {
        guard let data = jsonString.data(using: .utf8) else {
            throw SettingsRepositoryError.invalidJSON
        }
        let config = try jsonDecoder.decode(PolicyConfiguration.self, from: data)
        try await saveConfiguration(config)
        return config
    }
}

public enum SettingsRepositoryError: Error, LocalizedError, Sendable {
    case encodingFailed
    case invalidJSON

    public var errorDescription: String? {
        switch self {
        case .encodingFailed:
            return "Failed to encode configuration to UTF-8 JSON"
        case .invalidJSON:
            return "Configuration JSON payload is malformed or invalid UTF-8"
        }
    }
}
