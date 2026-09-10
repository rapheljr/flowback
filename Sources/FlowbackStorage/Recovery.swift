import Foundation
import FlowbackCore
import OSLog

private let logger = Logger(subsystem: "com.flowback.app", category: "RecoveryManager")

public final class RecoveryManager: Sendable {
    public static let shared = RecoveryManager()
    
    public init() {}
    
    /// Initializes database with automatic corruption recovery and migrations
    public func initializeStorage(path: String) async -> SQLiteDatabase {
        let db = SQLiteDatabase(path: path)
        do {
            try await db.open()
            try await Migrations.apply(db: db)
            logger.info("Storage initialized successfully at \(path)")
            return db
        } catch {
            logger.fault("Database opening or migration failed: \(error.localizedDescription). Initiating recovery...")
            await db.close()
            
            // Rename corrupt database to backup
            let backupPath = "\(path).corrupt.\(Int(Date().timeIntervalSince1970))"
            try? FileManager.default.moveItem(atPath: path, toPath: backupPath)
            try? FileManager.default.removeItem(atPath: "\(path)-wal")
            try? FileManager.default.removeItem(atPath: "\(path)-shm")
            
            // Re-instantiate clean database
            let freshDb = SQLiteDatabase(path: path)
            do {
                try await freshDb.open()
                try await Migrations.apply(db: freshDb)
                logger.info("Fresh database reconstructed successfully at \(path)")
                return freshDb
            } catch {
                fatalError("Critical storage recovery failure: \(error.localizedDescription)")
            }
        }
    }
}
