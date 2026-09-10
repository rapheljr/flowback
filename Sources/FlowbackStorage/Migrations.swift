import Foundation
import OSLog

private let logger = Logger(subsystem: "com.flowback.app", category: "Migrations")

public struct Migrations {
    public static let currentVersion: Int32 = 1
    
    public static func apply(db: SQLiteDatabase) async throws {
        let current = try await db.getUserVersion()
        logger.info("Current database version: \(current), target version: \(currentVersion)")
        
        if current < 1 {
            try await db.runInTransaction {
                try await applyMigrationV1(db: db)
            }
            try await db.setUserVersion(1)
            logger.info("Successfully applied Migration V1")
        }
    }
    
    private static func applyMigrationV1(db: SQLiteDatabase) async throws {
        let createSessionsTable = """
        CREATE TABLE IF NOT EXISTS sessions (
            id TEXT PRIMARY KEY,
            provider_id TEXT NOT NULL,
            provider_session_id TEXT,
            state TEXT NOT NULL,
            task_id TEXT,
            workspace TEXT,
            origin_context_json TEXT,
            started_at REAL NOT NULL,
            updated_at REAL NOT NULL,
            completed_at REAL,
            error_description TEXT,
            metadata_json TEXT
        );
        """
        
        let createEventsTable = """
        CREATE TABLE IF NOT EXISTS events (
            id TEXT PRIMARY KEY,
            timestamp REAL NOT NULL,
            provider_id TEXT NOT NULL,
            session_id TEXT NOT NULL,
            type TEXT NOT NULL,
            workspace TEXT,
            metadata_json TEXT,
            FOREIGN KEY(session_id) REFERENCES sessions(id) ON DELETE CASCADE
        );
        """
        
        let createSnapshotsTable = """
        CREATE TABLE IF NOT EXISTS focus_snapshots (
            id TEXT PRIMARY KEY,
            session_id TEXT NOT NULL,
            bundle_id TEXT NOT NULL,
            pid INTEGER NOT NULL,
            window_id INTEGER,
            window_title TEXT,
            is_fullscreen INTEGER DEFAULT 0,
            captured_at REAL NOT NULL,
            FOREIGN KEY(session_id) REFERENCES sessions(id) ON DELETE CASCADE
        );
        """
        
        let createSettingsTable = """
        CREATE TABLE IF NOT EXISTS settings (
            key TEXT PRIMARY KEY,
            value_json TEXT NOT NULL
        );
        """
        
        let createIndexes = """
        CREATE INDEX IF NOT EXISTS idx_sessions_state ON sessions(state);
        CREATE INDEX IF NOT EXISTS idx_sessions_started_at ON sessions(started_at);
        CREATE INDEX IF NOT EXISTS idx_events_session_id ON events(session_id);
        CREATE INDEX IF NOT EXISTS idx_events_timestamp ON events(timestamp);
        """
        
        try await db.execute(sql: createSessionsTable)
        try await db.execute(sql: createEventsTable)
        try await db.execute(sql: createSnapshotsTable)
        try await db.execute(sql: createSettingsTable)
        try await db.execute(sql: createIndexes)
    }
}
