import XCTest
@testable import FlowbackCore
@testable import FlowbackProviders

final class AntigravityProviderTests: XCTestCase {
    let provider = AntigravityProvider()
    
    func testFullyIdleTrueEmitsCompleted() throws {
        let json = """
        {
            "conversationId": "conv-12345",
            "workspacePaths": ["/Users/abin/workspace/projects/focus-switcher"],
            "executionNum": 1,
            "terminationReason": "model_stop",
            "error": "",
            "fullyIdle": true
        }
        """
        guard let data = json.data(using: .utf8) else { return XCTFail() }
        
        let event = try provider.parseLifecyclePayload(data: data)
        XCTAssertNotNil(event)
        XCTAssertEqual(event?.providerID, .antigravity)
        XCTAssertEqual(event?.sessionID.rawValue, "conv-12345")
        XCTAssertEqual(event?.type, .agentCompleted)
        XCTAssertEqual(event?.workspace, "/Users/abin/workspace/projects/focus-switcher")
        XCTAssertEqual(event?.metadata["fullyIdle"], "true")
    }
    
    func testFullyIdleFalseEmitsRunningNotCompleted() throws {
        let json = """
        {
            "conversationId": "conv-running-bg",
            "workspacePaths": ["/Users/abin/workspace/projects/focus-switcher"],
            "executionNum": 1,
            "terminationReason": "model_stop",
            "error": "",
            "fullyIdle": false
        }
        """
        guard let data = json.data(using: .utf8) else { return XCTFail() }
        
        let event = try provider.parseLifecyclePayload(data: data)
        XCTAssertNotNil(event)
        // Since background tasks are still running, should NOT be completed
        XCTAssertEqual(event?.type, .agentRunning)
    }
    
    func testErrorEmitsFailed() throws {
        let json = """
        {
            "conversationId": "conv-error",
            "workspacePaths": ["/Users/abin/workspace/projects/focus-switcher"],
            "executionNum": 2,
            "terminationReason": "error",
            "error": "Task execution timed out",
            "fullyIdle": true
        }
        """
        guard let data = json.data(using: .utf8) else { return XCTFail() }
        
        let event = try provider.parseLifecyclePayload(data: data)
        XCTAssertNotNil(event)
        XCTAssertEqual(event?.type, .agentFailed)
        XCTAssertEqual(event?.metadata["error"], "Task execution timed out")
    }
}
