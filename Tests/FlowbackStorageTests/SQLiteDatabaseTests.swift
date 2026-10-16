import XCTest
import SQLite3
@testable import FlowbackCore
@testable import FlowbackStorage

final class SQLiteDatabaseTests: XCTestCase {
    var tempDbPath: String!
    
    override func setUp() {
        super.setUp()
        tempDbPath = NSTemporaryDirectory() + "flowback_test_\(UUID().uuidString).sqlite"
    }
    
    override func tearDown() {
        try? FileManager.default.removeItem(atPath: tempDbPath)
        try? FileManager.default.removeItem(atPath: "\(tempDbPath!)-wal")
        try? FileManager.default.removeItem(atPath: "\(tempDbPath!)-shm")
        super.tearDown()
    }
    
    func testDatabaseCreationAndMigrations() async throws {
        let db = SQLiteDatabase(path: tempDbPath)
        try await db.open()
        
        let initialVersion = try await db.getUserVersion()
        XCTAssertEqual(initialVersion, 0)
        
        try await Migrations.apply(db: db)
        
        let versionAfterMigration = try await db.getUserVersion()
        XCTAssertEqual(versionAfterMigration, 1)
        
        // Test basic insert and query
        try await db.execute(sql: "INSERT INTO settings (key, value_json) VALUES ('test_key', '{\"val\": 123}');")
        
        let rows: [String] = try await db.query(sql: "SELECT value_json FROM settings WHERE key = 'test_key';") { stmt in
            String(cString: sqlite3_column_text(stmt, 0))
        }
        XCTAssertEqual(rows.count, 1)
        XCTAssertEqual(rows[0], "{\"val\": 123}")
        
        await db.close()
    }
}
