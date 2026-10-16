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
        guard let data = json.data(using: .utf8) else { return XCTFail("Failed to encode UTF8 data") }
        
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
        guard let data = json.data(using: .utf8) else { return XCTFail("Failed to encode UTF8 data") }
        
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
        guard let data = json.data(using: .utf8) else { return XCTFail("Failed to encode UTF8 data") }
        
        let event = try provider.parseLifecyclePayload(data: data)
        XCTAssertNotNil(event)
        XCTAssertEqual(event?.type, .agentFailed)
        XCTAssertEqual(event?.metadata["error"], "Task execution timed out")
    }
    
    func testDiscoverActiveSessionsWithBrainPath() async throws {
        let tempBrain = (NSTemporaryDirectory() as NSString).appendingPathComponent("flowback-xctest-brain-\(UUID().uuidString)")
        let convDir = (tempBrain as NSString).appendingPathComponent("conv-test-unit")
        let logsDir = (convDir as NSString).appendingPathComponent(".system_generated/logs")
        try FileManager.default.createDirectory(atPath: logsDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(atPath: tempBrain) }
        
        let sampleTranscript = """
        {"step_index":1,"source":"USER_EXPLICIT","type":"USER_INPUT","content":"test","Cwd":"/Users/test/workspace/projects/flowback"}
        {"step_index":2,"source":"MODEL","type":"PLANNER_RESPONSE","content":"working"}
        """
        let transcriptPath = (logsDir as NSString).appendingPathComponent("transcript.jsonl")
        try sampleTranscript.write(toFile: transcriptPath, atomically: true, encoding: .utf8)
        
        let customProvider = AntigravityProvider(brainPaths: [tempBrain])
        let discovered = await customProvider.discoverActiveSessions()
        XCTAssertEqual(discovered.count, 1)
        XCTAssertEqual(discovered.first?.id.rawValue, "conv-test-unit")
    }
}
