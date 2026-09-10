import XCTest
@testable import FlowbackCore
@testable import FlowbackFocus

final class AttentionArbiterTests: XCTestCase {
    func testPriorityOrdering() async {
        let arbiter = AttentionArbiter(aggregationWindow: 1.5, cooldownDuration: 1.0)
        
        let reqCompleted = AttentionRequest(
            sessionID: AgentSessionID("sess-1"),
            providerID: .antigravity,
            priority: .completed,
            title: "Completed",
            message: "Finished build"
        )
        
        let reqPermission = AttentionRequest(
            sessionID: AgentSessionID("sess-2"),
            providerID: .geminiCLI,
            priority: .permissionRequired,
            title: "Permission Needed",
            message: "Execute rm -rf?"
        )
        
        let reqFailure = AttentionRequest(
            sessionID: AgentSessionID("sess-3"),
            providerID: .codex,
            priority: .failure,
            title: "Build Failed",
            message: "Compiler error"
        )
        
        await arbiter.enqueue(reqCompleted)
        await arbiter.enqueue(reqPermission)
        await arbiter.enqueue(reqFailure)
        
        // Priority 1: permissionRequired
        let first = await arbiter.dequeueHighestPriority()
        XCTAssertEqual(first?.priority, .permissionRequired)
        XCTAssertEqual(first?.providerID, .geminiCLI)
        
        // Priority 2: failure
        let second = await arbiter.dequeueHighestPriority()
        XCTAssertEqual(second?.priority, .failure)
        XCTAssertEqual(second?.providerID, .codex)
        
        // Priority 3: completed
        let third = await arbiter.dequeueHighestPriority()
        XCTAssertEqual(third?.priority, .completed)
        XCTAssertEqual(third?.providerID, .antigravity)
    }
    
    func testAggregatedSummaryForMultipleAgents() async {
        let arbiter = AttentionArbiter()
        
        let req1 = AttentionRequest(
            sessionID: AgentSessionID("s1"),
            providerID: .antigravity,
            priority: .completed,
            title: "Done",
            message: "MatchDay done",
            workspace: "/projects/MatchDay"
        )
        let req2 = AttentionRequest(
            sessionID: AgentSessionID("s2"),
            providerID: .codex,
            priority: .completed,
            title: "Done",
            message: "API done",
            workspace: "/projects/API"
        )
        
        await arbiter.enqueue(req1)
        await arbiter.enqueue(req2)
        
        let summary = await arbiter.aggregatedSummary()
        XCTAssertNotNil(summary)
        XCTAssertEqual(summary?.title, "2 agents need attention")
        XCTAssertTrue(summary?.message.contains("antigravity — MatchDay") ?? false)
        XCTAssertTrue(summary?.message.contains("codex — API") ?? false)
    }
}
