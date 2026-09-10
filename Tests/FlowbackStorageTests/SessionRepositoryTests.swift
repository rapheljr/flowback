import XCTest
@testable import FlowbackCore
@testable import FlowbackStorage

final class SessionRepositoryTests: XCTestCase {
    var tempDbPath: String!
    var db: SQLiteDatabase!
    var repository: SessionRepository!
    
    override func setUp() async throws {
        try await super.setUp()
        tempDbPath = NSTemporaryDirectory() + "flowback_sess_test_\(UUID().uuidString).sqlite"
        db = SQLiteDatabase(path: tempDbPath)
        try await db.open()
        try await Migrations.apply(db: db)
        repository = SessionRepository(db: db)
    }
    
    override func tearDown() async throws {
        await db.close()
        try? FileManager.default.removeItem(atPath: tempDbPath)
        try? FileManager.default.removeItem(atPath: "\(tempDbPath!)-wal")
        try? FileManager.default.removeItem(atPath: "\(tempDbPath!)-shm")
        try await super.tearDown()
    }
    
    func testSaveAndFetchSession() async throws {
        let origin = OriginContext(
            bundleIdentifier: "com.microsoft.VSCode",
            processIdentifier: 12345,
            windowIdentifier: 99,
            windowTitle: "MatchDay — index.ts",
            workspacePath: "/Users/test/matchday"
        )
        let sessionID = AgentSessionID("sess-abc-123")
        let session = AgentSession(
            id: sessionID,
            providerID: .antigravity,
            state: .running,
            workspace: "/Users/test/matchday",
            originContext: origin,
            metadata: ["key": "value"]
        )
        
        try await repository.saveSession(session)
        
        let fetched = try await repository.fetchSession(id: sessionID)
        XCTAssertNotNil(fetched)
        XCTAssertEqual(fetched?.id, sessionID)
        XCTAssertEqual(fetched?.providerID, .antigravity)
        XCTAssertEqual(fetched?.state, .running)
        XCTAssertEqual(fetched?.originContext?.bundleIdentifier, "com.microsoft.VSCode")
        XCTAssertEqual(fetched?.originContext?.windowIdentifier, 99)
        XCTAssertEqual(fetched?.metadata["key"], "value")
        
        // Test update
        var updated = session
        updated.state = .completed
        updated.completedAt = Date()
        try await repository.saveSession(updated)
        
        let fetchedUpdated = try await repository.fetchSession(id: sessionID)
        XCTAssertEqual(fetchedUpdated?.state, .completed)
        XCTAssertNotNil(fetchedUpdated?.completedAt)
    }
}
