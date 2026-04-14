import Foundation
import Testing
@testable import ForgeFlow

@Suite("PostingService Unit Tests")
struct PostingServiceTests {

    @Test("validateTitle rejects empty title")
    func titleRejectsEmpty() {
        #expect(throws: PostingError.self) { try PostingService.validateTitle("") }
        #expect(throws: PostingError.self) { try PostingService.validateTitle("   ") }
    }

    @Test("validateTitle accepts non-empty title")
    func titleAcceptsValid() throws {
        try PostingService.validateTitle("Fix HVAC Unit")
        try PostingService.validateTitle("A")
    }

    @Test("validateSiteAddress rejects empty")
    func addressRejectsEmpty() {
        #expect(throws: PostingError.self) { try PostingService.validateSiteAddress("") }
        #expect(throws: PostingError.self) { try PostingService.validateSiteAddress("  ") }
    }

    @Test("validateSiteAddress accepts non-empty")
    func addressAcceptsValid() throws {
        try PostingService.validateSiteAddress("123 Main St")
    }

    @Test("validateDueDate rejects past date")
    func dueDateRejectsPast() {
        let past = Date().addingTimeInterval(-86400)
        #expect(throws: PostingError.self) { try PostingService.validateDueDate(past) }
    }

    @Test("validateDueDate accepts future date")
    func dueDateAcceptsFuture() throws {
        let future = Date().addingTimeInterval(86400)
        try PostingService.validateDueDate(future)
    }

    @Test("validateBudget rejects zero")
    func budgetRejectsZero() {
        #expect(throws: PostingError.self) { try PostingService.validateBudget(0) }
    }

    @Test("validateBudget rejects negative")
    func budgetRejectsNegative() {
        #expect(throws: PostingError.self) { try PostingService.validateBudget(-100) }
    }

    @Test("validateBudget accepts positive")
    func budgetAcceptsPositive() throws {
        try PostingService.validateBudget(1)
        try PostingService.validateBudget(250000)
    }

    @Test("PostingFormViewModel budgetCents conversion")
    func budgetCentsConversion() async {
        let dbManager = try! DatabaseManager(inMemory: true)
        let postingService = PostingService(
            dbPool: dbManager.dbPool,
            postingRepository: PostingRepository(dbPool: dbManager.dbPool),
            taskRepository: TaskRepository(dbPool: dbManager.dbPool),
            userRepository: UserRepository(dbPool: dbManager.dbPool),
            auditService: AuditService(dbPool: dbManager.dbPool)
        )
        let appState = AppState()
        let vm = await PostingFormViewModel(postingService: postingService, appState: appState)

        await MainActor.run {
            vm.budgetDollars = "250.50"
            #expect(vm.budgetCents == 25050)

            vm.budgetDollars = "2,500.00"
            #expect(vm.budgetCents == 250000)

            vm.budgetDollars = ""
            #expect(vm.budgetCents == 0)
        }
    }
}
