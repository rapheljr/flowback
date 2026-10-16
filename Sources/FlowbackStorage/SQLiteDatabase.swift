import Foundation
import SQLite3
import OSLog

private let logger = Logger(subsystem: "com.flowback.app", category: "SQLiteDatabase")
private let SQLITE_TRANSIENT = unsafeBitCast(-1, to: sqlite3_destructor_type.self)

public enum SQLiteError: Error, LocalizedError {
    case connectionFailed(String)
    case executionFailed(String, code: Int32)
    case prepareFailed(String, code: Int32)
    case stepFailed(String, code: Int32)
    case migrationFailed(String)
    
    public var errorDescription: String? {
        switch self {
        case .connectionFailed(let msg): return "SQLite connection failed: \(msg)"
        case .executionFailed(let msg, let code): return "SQLite execution failed (\(code)): \(msg)"
        case .prepareFailed(let msg, let code): return "SQLite prepare failed (\(code)): \(msg)"
        case .stepFailed(let msg, let code): return "SQLite step failed (\(code)): \(msg)"
        case .migrationFailed(let msg): return "SQLite migration failed: \(msg)"
        }
    }
}

private final class ConnectionBox: @unchecked Sendable {
    var handle: OpaquePointer?
    
    init(handle: OpaquePointer?) {
        self.handle = handle
    }
    
    deinit {
        if let handle = handle {
            sqlite3_close(handle)
        }
    }
}

/// Robust SQLite3 database engine with WAL mode and schema versioning
public actor SQLiteDatabase {
    private var box: ConnectionBox?
    public let path: String
    
    private var db: OpaquePointer? {
        box?.handle
    }
    
    public init(path: String) {
        self.path = path
    }
    
    public func open() throws {
        guard box == nil else { return }
        
        // Ensure directory exists if path is a file
        if path != ":memory:" {
            let dir = (path as NSString).deletingLastPathComponent
            if !dir.isEmpty {
                try FileManager.default.createDirectory(atPath: dir, withIntermediateDirectories: true)
            }
        }
        
        var handle: OpaquePointer?
        let flags = SQLITE_OPEN_READWRITE | SQLITE_OPEN_CREATE | SQLITE_OPEN_FULLMUTEX
        if sqlite3_open_v2(path, &handle, flags, nil) != SQLITE_OK {
            let errmsg = String(cString: sqlite3_errmsg(handle))
            sqlite3_close(handle)
            throw SQLiteError.connectionFailed(errmsg)
        }
        
        self.box = ConnectionBox(handle: handle)
        
        // Configure WAL mode for high concurrency on file-backed databases
        if path != ":memory:" {
            try execute(sql: "PRAGMA journal_mode=WAL;")
            try execute(sql: "PRAGMA synchronous=NORMAL;")
        }
        try execute(sql: "PRAGMA foreign_keys=ON;")
    }
    
    public func close() {
        if let box = box, let handle = box.handle {
            sqlite3_close(handle)
            box.handle = nil
            self.box = nil
        }
    }
    
    @discardableResult
    public func execute(sql: String) throws -> Int32 {
        guard let db = db else { throw SQLiteError.connectionFailed("Database not open") }
        var errmsg: UnsafeMutablePointer<CChar>?
        let result = sqlite3_exec(db, sql, nil, nil, &errmsg)
        if result != SQLITE_OK {
            let msg = errmsg != nil ? String(cString: errmsg!) : "Unknown error"
            sqlite3_free(errmsg)
            throw SQLiteError.executionFailed(msg, code: result)
        }
        return result
    }
    
    public func getUserVersion() throws -> Int32 {
        guard let db = db else { throw SQLiteError.connectionFailed("Database not open") }
        var stmt: OpaquePointer?
        defer { sqlite3_finalize(stmt) }
        
        if sqlite3_prepare_v2(db, "PRAGMA user_version;", -1, &stmt, nil) != SQLITE_OK {
            let msg = String(cString: sqlite3_errmsg(db))
            throw SQLiteError.prepareFailed(msg, code: sqlite3_errcode(db))
        }
        
        if sqlite3_step(stmt) == SQLITE_ROW {
            return sqlite3_column_int(stmt, 0)
        }
        return 0
    }
    
    public func setUserVersion(_ version: Int32) throws {
        try execute(sql: "PRAGMA user_version = \(version);")
    }
    
    public func runInTransaction<T: Sendable>(_ block: @Sendable () async throws -> T) async throws -> T {
        try execute(sql: "BEGIN IMMEDIATE TRANSACTION;")
        do {
            let result = try await block()
            try execute(sql: "COMMIT;")
            return result
        } catch {
            _ = try? execute(sql: "ROLLBACK;")
            throw error
        }
    }
    
    /// Prepares and executes a statement with parameter binding
    public func execute(sql: String, bindings: [(any Sendable)?] = []) throws {
        guard let db = db else { throw SQLiteError.connectionFailed("Database not open") }
        var stmt: OpaquePointer?
        defer { sqlite3_finalize(stmt) }
        
        if sqlite3_prepare_v2(db, sql, -1, &stmt, nil) != SQLITE_OK {
            let msg = String(cString: sqlite3_errmsg(db))
            throw SQLiteError.prepareFailed(msg, code: sqlite3_errcode(db))
        }
        
        try bind(statement: stmt, values: bindings)
        
        let step = sqlite3_step(stmt)
        if step != SQLITE_DONE && step != SQLITE_ROW {
            let msg = String(cString: sqlite3_errmsg(db))
            throw SQLiteError.stepFailed(msg, code: step)
        }
    }
    
    /// Queries rows and maps them with a closure
    public func query<T: Sendable>(
        sql: String,
        bindings: [(any Sendable)?] = [],
        mapRow: @Sendable (OpaquePointer) throws -> T
    ) throws -> [T] {
        guard let db = db else { throw SQLiteError.connectionFailed("Database not open") }
        var stmt: OpaquePointer?
        defer { sqlite3_finalize(stmt) }
        
        if sqlite3_prepare_v2(db, sql, -1, &stmt, nil) != SQLITE_OK {
            let msg = String(cString: sqlite3_errmsg(db))
            throw SQLiteError.prepareFailed(msg, code: sqlite3_errcode(db))
        }
        
        try bind(statement: stmt, values: bindings)
        
        var results: [T] = []
        while sqlite3_step(stmt) == SQLITE_ROW {
            guard let validStmt = stmt else { break }
            let item = try mapRow(validStmt)
            results.append(item)
        }
        return results
    }
    private func bind(statement: OpaquePointer?, values: [(any Sendable)?]) throws {
        for (index, val) in values.enumerated() {
            let idx = Int32(index + 1)
            if val == nil {
                sqlite3_bind_null(statement, idx)
            } else if let stringVal = val as? String {
                sqlite3_bind_text(statement, idx, (stringVal as NSString).utf8String, -1, SQLITE_TRANSIENT)
            } else if let intVal = val as? Int {
                sqlite3_bind_int64(statement, idx, Int64(intVal))
            } else if let int32Val = val as? Int32 {
                sqlite3_bind_int(statement, idx, int32Val)
            } else if let doubleVal = val as? Double {
                sqlite3_bind_double(statement, idx, doubleVal)
            } else if let dateVal = val as? Date {
                sqlite3_bind_double(statement, idx, dateVal.timeIntervalSince1970)
            } else if let boolVal = val as? Bool {
                sqlite3_bind_int(statement, idx, boolVal ? 1 : 0)
            } else if let dataVal = val as? Data {
                _ = dataVal.withUnsafeBytes { rawBuffer in
                    sqlite3_bind_blob(statement, idx, rawBuffer.baseAddress, Int32(dataVal.count), SQLITE_TRANSIENT)
                }
            } else {
                sqlite3_bind_text(statement, idx, ("\(val!)" as NSString).utf8String, -1, SQLITE_TRANSIENT)
            }
        }
    }
}
