import XCTest
@testable import FlowbackCore

final class PolicyConfigurationTests: XCTestCase {
    func testOverridePrecedence() {
        var config = PolicyConfiguration.default
        config.focusPolicy = .smart
        config.providerOverrides["antigravity"] = .alwaysRestore
        config.applicationOverrides["com.microsoft.VSCode"] = .notificationOnly
        config.workspaceOverrides["/projects/critical"] = .neverInterrupt
        
        // 1. Workspace override wins first
        let res1 = config.resolvePolicy(
            provider: .antigravity,
            appBundleID: "com.microsoft.VSCode",
            workspace: "/projects/critical"
        )
        XCTAssertEqual(res1, .neverInterrupt)
        
        // 2. Application override wins over provider
        let res2 = config.resolvePolicy(
            provider: .antigravity,
            appBundleID: "com.microsoft.VSCode",
            workspace: "/projects/other"
        )
        XCTAssertEqual(res2, .notificationOnly)
        
        // 3. Provider override wins over global default
        let res3 = config.resolvePolicy(
            provider: .antigravity,
            appBundleID: "com.brave.Browser",
            workspace: "/projects/other"
        )
        XCTAssertEqual(res3, .alwaysRestore)
        
        // 4. Global default applied if no overrides match
        let res4 = config.resolvePolicy(
            provider: .claudeCode,
            appBundleID: "com.brave.Browser",
            workspace: "/projects/other"
        )
        XCTAssertEqual(res4, .smart)
    }
}
