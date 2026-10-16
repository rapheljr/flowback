import Foundation
import FlowbackCore
import OSLog

private let logger = Logger(subsystem: "com.flowback.app", category: "RecoveryManager")

public struct StorageInitializationResult: Sendable {
    public let database: SQLiteDatabase
    public let isDurable: Bool
    public let isRecovered: Bool
    public let backupPath: String?
    public let recoveryNotice: String?
    
    public init(
        database: SQLiteDatabase,
        isDurable: Bool,
        isRecovered: Bool = false,
        backupPath: String? = nil,
        recoveryNotice: String? = nil
    ) {
        self.database = database
        self.isDurable = isDurable
        self.isRecovered = isRecovered
        self.backupPath = backupPath
        self.recoveryNotice = recoveryNotice
    }
}

public final class RecoveryManager: Sendable {
    public static let shared = RecoveryManager()
    
    public init() {}
    
    /// Initializes database with detailed diagnostic report, automatic recovery, and WAL preservation
    public func initializeStorageDetailed(path: String) async -> StorageInitializationResult {
        let db = SQLiteDatabase(path: path)
        do {
            try await db.open()
            try await Migrations.apply(db: db)
            logger.info("Storage initialized successfully at \(path)")
            return StorageInitializationResult(
                database: db,
                isDurable: path != ":memory:",
                isRecovered: false,
                backupPath: nil,
                recoveryNotice: nil
            )
        } catch {
            logger.fault("Database opening or migration failed: \(error.localizedDescription). Initiating recovery...")
            await db.close()
            
            var backupPath: String?
            // Safely preserve corrupt database AND journals without deleting user data
            if path != ":memory:" {
                let timestamp = Int(Date().timeIntervalSince1970)
                let bPath = "\(path).corrupt.\(timestamp)"
                backupPath = bPath
                
                try? FileManager.default.moveItem(atPath: path, toPath: bPath)
                if FileManager.default.fileExists(atPath: "\(path)-wal") {
                    try? FileManager.default.moveItem(atPath: "\(path)-wal", toPath: "\(bPath)-wal")
                }
                if FileManager.default.fileExists(atPath: "\(path)-shm") {
                    try? FileManager.default.moveItem(atPath: "\(path)-shm", toPath: "\(bPath)-shm")
                }
                logger.info("Preserved corrupt database and journal logs at \(bPath)")
            }
            
            // Re-instantiate clean database on disk
            let freshDb = SQLiteDatabase(path: path)
            do {
                try await freshDb.open()
                try await Migrations.apply(db: freshDb)
                logger.info("Fresh database reconstructed successfully at \(path)")
                return StorageInitializationResult(
                    database: freshDb,
                    isDurable: true,
                    isRecovered: true,
                    backupPath: backupPath,
                    recoveryNotice: "Database recovered: damaged database preserved at \(backupPath ?? "unknown"). Fresh schema applied on disk."
                )
            } catch {
                logger.fault("Critical storage recovery failure on disk (\(error.localizedDescription)). Falling back to in-memory database.")
                let memoryDb = SQLiteDatabase(path: ":memory:")
                do {
                    try await memoryDb.open()
                    try await Migrations.apply(db: memoryDb)
                    logger.warning("Operating in transient in-memory database fallback.")
                    return StorageInitializationResult(
                        database: memoryDb,
                        isDurable: false,
                        isRecovered: true,
                        backupPath: backupPath,
                        recoveryNotice: "Warning: Operating in transient in-memory storage fallback. Changes will NOT persist across restarts. Damaged database preserved at \(backupPath ?? "unknown")."
                    )
                } catch {
                    logger.fault("Fatal: even in-memory database fallback failed: \(error.localizedDescription)")
                    return StorageInitializationResult(
                        database: freshDb,
                        isDurable: false,
                        isRecovered: true,
                        backupPath: backupPath,
                        recoveryNotice: "Critical storage error: database unusable."
                    )
                }
            }
        }
    }
    
    /// Initializes database with automatic corruption recovery and migrations
    public func initializeStorage(path: String) async -> SQLiteDatabase {
        await initializeStorageDetailed(path: path).database
    }
}
