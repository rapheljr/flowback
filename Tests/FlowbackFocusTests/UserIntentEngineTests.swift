import XCTest
import AppKit
@testable import FlowbackCore
@testable import FlowbackFocus
@testable import FlowbackTestHarness

final class UserIntentEngineTests: XCTestCase {
    var mockIdleTracker: MockIdleTracker!
    var mockWindowController: MockWindowController!
    var mockSpaceController: MockSpaceController!
    var mockAppController: MockApplicationController!
    var intentEngine: UserIntentEngine!
    
    override func setUp() {
        super.setUp()
        mockIdleTracker = MockIdleTracker(idleSeconds: 30.0) // user idle by default
        mockWindowController = MockWindowController()
        mockSpaceController = MockSpaceController()
        mockAppController = MockApplicationController()
        intentEngine = UserIntentEngine(
            idleTracker: mockIdleTracker,
            windowController: mockWindowController,
            spaceController: mockSpaceController,
            appController: mockAppController
        )
    }
    
    func testFocusLockSuppressesFocus() {
        let origin = OriginContext(bundleIdentifier: "com.microsoft.VSCode", processIdentifier: 100)
        let session = AgentSession(providerID: .antigravity, state: .completed, originContext: origin)
        let config = PolicyConfiguration.default
        let lock = FocusLockState(isActive: true, expiresAt: Date().addingTimeInterval(600), label: "10 min")
        
        let decision = intentEngine.evaluate(session: session, config: config, focusLock: lock, frontmostApp: nil)
        
        guard case .notifyOnly(let reason) = decision else {
            return XCTFail("Expected .notifyOnly due to Focus Lock")
        }
        XCTAssertTrue(reason.contains("Focus Lock is active"))
    }
    
    func testActiveUserTypingDoesNotStealFocus() {
        let origin = OriginContext(bundleIdentifier: "com.microsoft.VSCode", processIdentifier: 100)
        let session = AgentSession(providerID: .antigravity, state: .completed, originContext: origin)
        let config = PolicyConfiguration.default
        let lock = FocusLockState(isActive: false)
        
        // Mock that user is in Brave Browser and typed 0.5 seconds ago (idle < threshold)
        mockIdleTracker.idleSecondsMock = 0.5
        
        // Mock frontmost app is Brave Browser
        let frontApp = NSRunningApplication.current // Use current test app as surrogate frontmost
        
        let decision = intentEngine.evaluate(session: session, config: config, focusLock: lock, frontmostApp: frontApp)
        
        guard case .notifyOnly(let reason) = decision else {
            return XCTFail("Expected .notifyOnly because user is actively typing")
        }
        XCTAssertTrue(reason.contains("User is actively interacting"))
    }
    
    func testIdleUserRestoresOrigin() {
        let origin = OriginContext(bundleIdentifier: "com.microsoft.VSCode", processIdentifier: 100)
        let session = AgentSession(providerID: .antigravity, state: .completed, originContext: origin)
        let config = PolicyConfiguration.default
        let lock = FocusLockState(isActive: false)
        
        // User has been idle for 20 seconds
        mockIdleTracker.idleSecondsMock = 20.0
        
        let decision = intentEngine.evaluate(session: session, config: config, focusLock: lock, frontmostApp: nil)
        
        guard case .restoreOrigin(let ctx, _) = decision else {
            return XCTFail("Expected .restoreOrigin for idle user")
        }
        XCTAssertEqual(ctx.bundleIdentifier, "com.microsoft.VSCode")
    }
    
    func testFullscreenPresentationSuppressesFocus() {
        let origin = OriginContext(bundleIdentifier: "com.microsoft.VSCode", processIdentifier: 100)
        let session = AgentSession(providerID: .antigravity, state: .completed, originContext: origin)
        let config = PolicyConfiguration.default
        let lock = FocusLockState(isActive: false)
        
        mockIdleTracker.idleSecondsMock = 20.0
        mockWindowController.isFullscreenMock = true
        
        let decision = intentEngine.evaluate(session: session, config: config, focusLock: lock, frontmostApp: nil)
        
        guard case .notifyOnly(let reason) = decision else {
            return XCTFail("Expected .notifyOnly during fullscreen")
        }
        XCTAssertTrue(reason.contains("Fullscreen"))
    }
}
