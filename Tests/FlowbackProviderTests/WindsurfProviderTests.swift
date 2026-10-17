import XCTest
@testable import FlowbackCore
@testable import FlowbackProviders

final class WindsurfProviderTests: XCTestCase {
    
    func testPreUserPromptEmitsStartedOrRunning() throws {
        let provider = WindsurfProvider()
        let json = """
        {
            "agent_action_name": "pre_user_prompt",
            "trajectory_id": "traj-unit-1",
            "execution_id": "exec-100",
            "step_index": 1,
            "workspace_root": "/Users/abin/workspace/projects/flowback",
            "model_name": "cascade-v1",
            "tool_info": {
                "prompt": "Refactor codebase"
            }
        }
        """
        guard let data = json.data(using: .utf8) else { return XCTFail("Failed to encode UTF8 data") }
        
        let event = try provider.parseLifecyclePayload(data: data)
        XCTAssertNotNil(event)
        XCTAssertEqual(event?.providerID, .windsurf)
        XCTAssertEqual(event?.sessionID.rawValue, "traj-unit-1")
        XCTAssertEqual(event?.type, .agentStarted)
        XCTAssertEqual(event?.workspace, "/Users/abin/workspace/projects/flowback")
        XCTAssertEqual(event?.metadata["actionName"], "pre_user_prompt")
        XCTAssertEqual(event?.metadata["executionId"], "exec-100")
        XCTAssertEqual(event?.metadata["deduplicationKey"], "windsurf:traj-unit-1:pre_user_prompt:exec-100")
    }
    
    func testPostCascadeResponseEmitsCompleted() throws {
        let provider = WindsurfProvider()
        let json = """
        {
            "agent_action_name": "post_cascade_response",
            "trajectory_id": "traj-unit-1",
            "execution_id": "exec-101",
            "workspace_root": "/Users/abin/workspace/projects/flowback",
            "tool_info": {
                "response": "Done! Refactored the module successfully."
            }
        }
        """
        guard let data = json.data(using: .utf8) else { return XCTFail("Failed to encode UTF8 data") }
        
        let event = try provider.parseLifecyclePayload(data: data)
        XCTAssertNotNil(event)
        XCTAssertEqual(event?.type, .agentCompleted)
        XCTAssertEqual(event?.metadata["actionName"], "post_cascade_response")
    }
    
    func testPreRunCommandWithConfirmationEmitsPermissionRequired() throws {
        let provider = WindsurfProvider()
        let json = """
        {
            "agent_action_name": "pre_run_command",
            "trajectory_id": "traj-unit-2",
            "execution_id": "exec-200",
            "workspace_root": "/Users/abin/workspace/projects/flowback",
            "tool_info": {
                "command": "rm -rf .build",
                "requires_confirmation": true
            }
        }
        """
        guard let data = json.data(using: .utf8) else { return XCTFail("Failed to encode UTF8 data") }
        
        let event = try provider.parseLifecyclePayload(data: data)
        XCTAssertNotNil(event)
        XCTAssertEqual(event?.type, .agentPermissionRequired)
        XCTAssertEqual(event?.metadata["command"], "rm -rf .build")
    }
    
    func testErrorInCascadePayloadEmitsFailed() throws {
        let provider = WindsurfProvider()
        let json = """
        {
            "agent_action_name": "post_run_command",
            "trajectory_id": "traj-unit-3",
            "error": "Command failed with exit code 127"
        }
        """
        guard let data = json.data(using: .utf8) else { return XCTFail("Failed to encode UTF8 data") }
        
        let event = try provider.parseLifecyclePayload(data: data)
        XCTAssertNotNil(event)
        XCTAssertEqual(event?.type, .agentFailed)
        XCTAssertEqual(event?.metadata["error"], "Command failed with exit code 127")
    }
    
    func testIdempotentInstallAndPreservationOfExistingHooks() async throws {
        let tempDir = NSTemporaryDirectory() + "windsurf_test_\(UUID().uuidString)"
        try FileManager.default.createDirectory(atPath: tempDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(atPath: tempDir) }
        
        let hooksFile = (tempDir as NSString).appendingPathComponent("hooks.json")
        let existingUserConfig = """
        {
            "hooks": {
                "pre_write_code": [
                    {
                        "command": "prettier --check",
                        "show_output": true
                    }
                ]
            }
        }
        """
        try existingUserConfig.write(toFile: hooksFile, atomically: true, encoding: .utf8)
        
        let provider = WindsurfProvider(globalConfigDir: tempDir)
        try await provider.installIntegration()
        
        // Read back
        let data = try Data(contentsOf: URL(fileURLWithPath: hooksFile))
        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let hooks = json["hooks"] as? [String: Any] else {
            return XCTFail("Invalid hooks.json structure")
        }
        
        // 1. Existing user hook is preserved
        guard let preWriteList = hooks["pre_write_code"] as? [[String: Any]] else {
            return XCTFail("Missing pre_write_code")
        }
        XCTAssertTrue(preWriteList.contains(where: { ($0["command"] as? String) == "prettier --check" }))
        XCTAssertTrue(preWriteList.contains(where: { ($0["command"] as? String)?.contains("flowback hook windsurf") == true }))
        
        // 2. Lifecycle hooks installed
        XCTAssertNotNil(hooks["pre_user_prompt"])
        XCTAssertNotNil(hooks["post_cascade_response"])
        
        // 3. Uninstall cleans up only Flowback hook
        try await provider.uninstallIntegration()
        let uninstalledData = try Data(contentsOf: URL(fileURLWithPath: hooksFile))
        guard let uninstalledJson = try JSONSerialization.jsonObject(with: uninstalledData) as? [String: Any],
              let uninstalledHooks = uninstalledJson["hooks"] as? [String: Any] else {
            return XCTFail("Invalid uninstalled hooks.json structure")
        }
        
        let cleanedPreWrite = uninstalledHooks["pre_write_code"] as? [[String: Any]]
        XCTAssertTrue(cleanedPreWrite?.contains(where: { ($0["command"] as? String) == "prettier --check" }) ?? false)
        XCTAssertFalse(cleanedPreWrite?.contains(where: { ($0["command"] as? String)?.contains("flowback hook windsurf") == true }) ?? true)
    }
}
