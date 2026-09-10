import XCTest
@testable import FlowbackCore
@testable import FlowbackProviders

final class GenericHookProviderTests: XCTestCase {
    let provider = GenericHookProvider()
    
    func testValidSchemaVersion1Payload() throws {
        let json = """
        {
            "schemaVersion": 1,
            "event": "agent.completed",
            "provider": "custom-agent",
            "sessionId": "sess-xyz",
            "workspace": "/path/to/repo",
            "metadata": {
                "branch": "feature-x"
            }
        }
        """
        guard let data = json.data(using: .utf8) else { return XCTFail() }
        
        let event = try provider.parseLifecyclePayload(data: data)
        XCTAssertNotNil(event)
        XCTAssertEqual(event?.providerID.rawValue, "custom-agent")
        XCTAssertEqual(event?.sessionID.rawValue, "sess-xyz")
        XCTAssertEqual(event?.type, .agentCompleted)
        XCTAssertEqual(event?.workspace, "/path/to/repo")
        XCTAssertEqual(event?.metadata["branch"], "feature-x")
    }
    
    func testRejectsMalformedPayload() throws {
        let malformed = "{\"something\": \"else\"}".data(using: .utf8)!
        let event = try provider.parseLifecyclePayload(data: malformed)
        XCTAssertNil(event)
    }
}
