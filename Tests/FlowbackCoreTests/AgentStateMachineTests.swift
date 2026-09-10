import XCTest
@testable import FlowbackCore

final class AgentStateMachineTests: XCTestCase {
    let stateMachine = AgentStateMachine()
    
    func testValidTransitions() throws {
        XCTAssertTrue(stateMachine.canTransition(from: .starting, to: .running))
        XCTAssertTrue(stateMachine.canTransition(from: .running, to: .waiting))
        XCTAssertTrue(stateMachine.canTransition(from: .waiting, to: .running))
        XCTAssertTrue(stateMachine.canTransition(from: .running, to: .permissionRequired))
        XCTAssertTrue(stateMachine.canTransition(from: .permissionRequired, to: .running))
        XCTAssertTrue(stateMachine.canTransition(from: .running, to: .completed))
        XCTAssertTrue(stateMachine.canTransition(from: .running, to: .failed))
        XCTAssertTrue(stateMachine.canTransition(from: .running, to: .cancelled))
    }
    
    func testTerminalStateImmutability() {
        XCTAssertFalse(stateMachine.canTransition(from: .completed, to: .running))
        XCTAssertFalse(stateMachine.canTransition(from: .failed, to: .starting))
        XCTAssertFalse(stateMachine.canTransition(from: .cancelled, to: .running))
        
        XCTAssertThrowsError(try stateMachine.transition(from: .completed, to: .running)) { error in
            guard let smError = error as? StateMachineError else {
                return XCTFail("Expected StateMachineError")
            }
            XCTAssertEqual(smError, .terminalStateLocked(state: .completed))
        }
    }
    
    func testIllegalTransition() {
        XCTAssertFalse(stateMachine.canTransition(from: .running, to: .starting))
        XCTAssertThrowsError(try stateMachine.transition(from: .running, to: .starting))
    }
}
