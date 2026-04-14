import Foundation
import Testing
@testable import ForgeFlow

@Suite("TaskService Unit Tests")
struct TaskServiceTests {

    // MARK: - State Machine (PRD 9.3)

    @Test("Valid transitions: NOT_STARTED → IN_PROGRESS")
    func notStartedToInProgress() {
        #expect(TaskService.isValidTransition(from: .notStarted, to: .inProgress) == true)
    }

    @Test("Valid transitions: NOT_STARTED → BLOCKED")
    func notStartedToBlocked() {
        #expect(TaskService.isValidTransition(from: .notStarted, to: .blocked) == true)
    }

    @Test("Valid transitions: IN_PROGRESS → DONE")
    func inProgressToDone() {
        #expect(TaskService.isValidTransition(from: .inProgress, to: .done) == true)
    }

    @Test("Valid transitions: IN_PROGRESS → BLOCKED")
    func inProgressToBlocked() {
        #expect(TaskService.isValidTransition(from: .inProgress, to: .blocked) == true)
    }

    @Test("Valid transitions: BLOCKED → IN_PROGRESS")
    func blockedToInProgress() {
        #expect(TaskService.isValidTransition(from: .blocked, to: .inProgress) == true)
    }

    @Test("Valid transitions: BLOCKED → NOT_STARTED")
    func blockedToNotStarted() {
        #expect(TaskService.isValidTransition(from: .blocked, to: .notStarted) == true)
    }

    @Test("Invalid transitions: NOT_STARTED → DONE (must go through IN_PROGRESS)")
    func notStartedToDone() {
        #expect(TaskService.isValidTransition(from: .notStarted, to: .done) == false)
    }

    @Test("Invalid transitions: DONE → anything (terminal)")
    func doneIsTerminal() {
        #expect(TaskService.isValidTransition(from: .done, to: .notStarted) == false)
        #expect(TaskService.isValidTransition(from: .done, to: .inProgress) == false)
        #expect(TaskService.isValidTransition(from: .done, to: .blocked) == false)
    }

    @Test("Invalid transitions: BLOCKED → DONE (must resume first)")
    func blockedToDone() {
        #expect(TaskService.isValidTransition(from: .blocked, to: .done) == false)
    }
}
