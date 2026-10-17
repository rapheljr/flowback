import XCTest
@testable import FlowbackCore
@testable import FlowbackProviders

final class OpenCodeProviderTests: XCTestCase {
    
    func testSessionCreatedEmitsAgentStarted() throws {
        let provider = OpenCodeProvider()
        let json = """
        {
            "event": "session.created",
            "sessionId": "opencode-sess-1",
            "directory": "/Users/abin/workspace/projects/flowback",
            "projectId": "flowback-proj",
            "timestamp": "2026-10-17T11:45:00Z"
        }
        """
        guard let data = json.data(using: .utf8) else { return XCTFail("Failed to encode UTF8 data") }
        
        let event = try provider.parseLifecyclePayload(data: data)
        XCTAssertNotNil(event)
        XCTAssertEqual(event?.providerID, .openCode)
        XCTAssertEqual(event?.sessionID.rawValue, "opencode-sess-1")
        XCTAssertEqual(event?.type, .agentStarted)
        XCTAssertEqual(event?.workspace, "/Users/abin/workspace/projects/flowback")
        XCTAssertEqual(event?.metadata["projectId"], "flowback-proj")
    }
    
    func testSessionIdleEmitsAgentCompleted() throws {
        let provider = OpenCodeProvider()
        let json = """
        {
            "event": "session.idle",
            "sessionId": "opencode-sess-1",
            "directory": "/Users/abin/workspace/projects/flowback"
        }
        """
        guard let data = json.data(using: .utf8) else { return XCTFail("Failed to encode UTF8 data") }
        
        let event = try provider.parseLifecyclePayload(data: data)
        XCTAssertNotNil(event)
        XCTAssertEqual(event?.type, .agentCompleted)
    }
    
    func testToolExecutionWithPermissionEmitsPermissionRequired() throws {
        let provider = OpenCodeProvider()
        let json = """
        {
            "event": "tool.execute.before",
            "sessionId": "opencode-sess-1",
            "directory": "/Users/abin/workspace/projects/flowback",
            "tool": {
                "name": "bash",
                "callId": "call-1234",
                "requiresPermission": true
            }
        }
        """
        guard let data = json.data(using: .utf8) else { return XCTFail("Failed to encode UTF8 data") }
        
        let event = try provider.parseLifecyclePayload(data: data)
        XCTAssertNotNil(event)
        XCTAssertEqual(event?.type, .agentPermissionRequired)
        XCTAssertEqual(event?.metadata["toolName"], "bash")
        XCTAssertEqual(event?.metadata["callId"], "call-1234")
    }
    
    func testSessionErrorEmitsAgentFailed() throws {
        let provider = OpenCodeProvider()
        let json = """
        {
            "event": "session.error",
            "sessionId": "opencode-sess-2",
            "error": "SyntaxError: Unexpected token"
        }
        """
        guard let data = json.data(using: .utf8) else { return XCTFail("Failed to encode UTF8 data") }
        
        let event = try provider.parseLifecyclePayload(data: data)
        XCTAssertNotNil(event)
        XCTAssertEqual(event?.type, .agentFailed)
        XCTAssertEqual(event?.metadata["error"], "SyntaxError: Unexpected token")
    }
    
    func testPluginInstallationAndCleanRemoval() async throws {
        let tempConfig = NSTemporaryDirectory() + "opencode_cfg_\(UUID().uuidString)"
        let tempPlugins = (tempConfig as NSString).appendingPathComponent("plugins")
        try FileManager.default.createDirectory(atPath: tempPlugins, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(atPath: tempConfig) }
        
        let provider = OpenCodeProvider(
            configDir: tempConfig,
            pluginInstallDir: tempPlugins
        )
        
        try await provider.installIntegration()
        
        let pluginFile = (tempPlugins as NSString).appendingPathComponent("flowback.js")
        XCTAssertTrue(FileManager.default.fileExists(atPath: pluginFile), "flowback.js plugin created")
        
        let healthAfterInstall = await provider.checkHealth()
        XCTAssertTrue(healthAfterInstall.hookInstalled, "Hook detected after install")
        
        try await provider.uninstallIntegration()
        XCTAssertFalse(FileManager.default.fileExists(atPath: pluginFile), "flowback.js removed after uninstall")
    }
}
