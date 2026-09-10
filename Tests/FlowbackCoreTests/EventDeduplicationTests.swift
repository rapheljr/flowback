import XCTest
@testable import FlowbackCore

final class EventDeduplicationTests: XCTestCase {
    func testDeduplicationDropsDuplicatesWithinWindow() async {
        let deduplicator = EventDeduplicator(window: 1.0)
        let sessionID = AgentSessionID("test-sess-1")
        
        let event1 = AgentEvent(
            providerID: .antigravity,
            sessionID: sessionID,
            type: .agentCompleted,
            workspace: "/projects/test"
        )
        
        let event2 = AgentEvent(
            providerID: .antigravity,
            sessionID: sessionID,
            type: .agentCompleted,
            workspace: "/projects/test"
        )
        
        let firstProcessed = await deduplicator.shouldProcess(event: event1)
        XCTAssertTrue(firstProcessed)
        
        // Immediate duplicate should be dropped
        let secondProcessed = await deduplicator.shouldProcess(event: event2)
        XCTAssertFalse(secondProcessed)
        
        // Different event type should be processed
        let event3 = AgentEvent(
            providerID: .antigravity,
            sessionID: sessionID,
            type: .agentFailed,
            workspace: "/projects/test"
        )
        let thirdProcessed = await deduplicator.shouldProcess(event: event3)
        XCTAssertTrue(thirdProcessed)
    }
}
