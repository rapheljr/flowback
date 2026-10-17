import XCTest
@testable import FlowbackCore
@testable import FlowbackProviders

final class CursorBackgroundProviderTests: XCTestCase {
    
    func testCloudAgentRunningEmitsAgentRunning() throws {
        let provider = CursorBackgroundProvider(apiKeyProvider: { "crs_test_token" })
        let json = """
        {
            "id": "agent-cloud-001",
            "status": "RUNNING",
            "repository": "https://github.com/rapheljr/flowback.git",
            "branchName": "cursor/refactor-auth",
            "latestRunId": "run-999"
        }
        """
        guard let data = json.data(using: .utf8) else { return XCTFail("Failed to encode UTF8 data") }
        
        let event = try provider.parseLifecyclePayload(data: data)
        XCTAssertNotNil(event)
        XCTAssertEqual(event?.providerID, .cursorBackground)
        XCTAssertEqual(event?.sessionID.rawValue, "agent-cloud-001")
        XCTAssertEqual(event?.type, .agentRunning)
        XCTAssertEqual(event?.metadata["repositoryUrl"], "https://github.com/rapheljr/flowback.git")
        XCTAssertEqual(event?.metadata["branch"], "cursor/refactor-auth")
        XCTAssertEqual(event?.metadata["latestRunId"], "run-999")
        XCTAssertNil(event?.metadata["parentSessionId"], "Not a subagent")
    }
    
    func testCloudAgentCompletedEmitsCompletedWithPRUrl() throws {
        let provider = CursorBackgroundProvider(apiKeyProvider: { "crs_test_token" })
        let json = """
        {
            "id": "agent-cloud-002",
            "status": "COMPLETED",
            "repository": "https://github.com/rapheljr/flowback.git",
            "prUrl": "https://github.com/rapheljr/flowback/pull/42",
            "latestRunId": "run-1000"
        }
        """
        guard let data = json.data(using: .utf8) else { return XCTFail("Failed to encode UTF8 data") }
        
        let event = try provider.parseLifecyclePayload(data: data)
        XCTAssertNotNil(event)
        XCTAssertEqual(event?.type, .agentCompleted)
        XCTAssertEqual(event?.metadata["prUrl"], "https://github.com/rapheljr/flowback/pull/42")
    }
    
    func testCloudAgentSubagentHierarchyTracking() throws {
        let provider = CursorBackgroundProvider(apiKeyProvider: { "crs_test_token" })
        let json = """
        {
            "id": "agent-cloud-child",
            "parentAgentId": "agent-cloud-parent-001",
            "status": "RUNNING",
            "repository": "https://github.com/rapheljr/flowback.git",
            "latestRunId": "sub-run-55"
        }
        """
        guard let data = json.data(using: .utf8) else { return XCTFail("Failed to encode UTF8 data") }
        
        let event = try provider.parseLifecyclePayload(data: data)
        XCTAssertNotNil(event)
        XCTAssertEqual(event?.metadata["parentSessionId"], "agent-cloud-parent-001")
        XCTAssertEqual(event?.metadata["isSubagent"], "true")
    }
    
    func testUnconfiguredApiKeyYieldsPartialHealthWithDiagnostics() async {
        let provider = CursorBackgroundProvider(apiKeyProvider: { nil })
        let health = await provider.checkHealth()
        XCTAssertFalse(health.isInstalled)
        XCTAssertEqual(health.supportLevel, .partial)
        XCTAssertTrue(health.statusMessage.contains("CURSOR_API_KEY"))
    }
    
    func testConfiguredApiKeyYieldsNativeLifecycleHealth() async {
        let provider = CursorBackgroundProvider(apiKeyProvider: { "secret_valid_key" })
        let health = await provider.checkHealth()
        XCTAssertTrue(health.isInstalled)
        XCTAssertEqual(health.supportLevel, .nativeLifecycle)
        XCTAssertFalse(health.statusMessage.contains("secret_valid_key"), "Credentials must never leak into status messages")
    }
}
