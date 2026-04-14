import Foundation
import Testing
@testable import ForgeFlow

@Suite("Posting View Tests")
struct PostingViewTests {

    @Test("PostingFormViewModel isValid requires all fields")
    func formValidation() async throws {
        let dbManager = try DatabaseManager(inMemory: true)
        let dbPool = dbManager.dbPool
        let ps = PostingService(
            dbPool: dbPool, postingRepository: PostingRepository(dbPool: dbPool),
            taskRepository: TaskRepository(dbPool: dbPool), userRepository: UserRepository(dbPool: dbPool),
            auditService: AuditService(dbPool: dbPool)
        )
        let appState = AppState()
        let vm = await PostingFormViewModel(postingService: ps, appState: appState)

        await MainActor.run {
            #expect(vm.isValid == false) // All empty

            vm.title = "Test"
            #expect(vm.isValid == false) // Missing address, budget

            vm.siteAddress = "123 Main"
            #expect(vm.isValid == false) // Missing budget

            vm.budgetDollars = "100"
            #expect(vm.isValid == true) // All filled, dueDate defaults to future
        }
    }

    @Test("PostingFormViewModel budgetCents handles comma-separated input")
    func budgetCentsCommas() async throws {
        let dbManager = try DatabaseManager(inMemory: true)
        let ps = PostingService(
            dbPool: dbManager.dbPool, postingRepository: PostingRepository(dbPool: dbManager.dbPool),
            taskRepository: TaskRepository(dbPool: dbManager.dbPool), userRepository: UserRepository(dbPool: dbManager.dbPool),
            auditService: AuditService(dbPool: dbManager.dbPool)
        )
        let vm = await PostingFormViewModel(postingService: ps, appState: AppState())

        await MainActor.run {
            vm.budgetDollars = "1,250.75"
            #expect(vm.budgetCents == 125075)
        }
    }

    @Test("PostingDetailViewModel canPublish only for DRAFT + admin/coordinator")
    func canPublishLogic() async throws {
        let dbManager = try DatabaseManager(inMemory: true)
        let dbPool = dbManager.dbPool
        let ps = PostingService(
            dbPool: dbPool, postingRepository: PostingRepository(dbPool: dbPool),
            taskRepository: TaskRepository(dbPool: dbPool), userRepository: UserRepository(dbPool: dbPool),
            auditService: AuditService(dbPool: dbPool)
        )
        let as_ = AssignmentService(
            dbPool: dbPool, assignmentRepository: AssignmentRepository(dbPool: dbPool),
            postingRepository: PostingRepository(dbPool: dbPool), userRepository: UserRepository(dbPool: dbPool),
            auditService: AuditService(dbPool: dbPool)
        )
        let appState = AppState()
        appState.login(userId: UUID(), role: .coordinator)

        let vm = await PostingDetailViewModel(postingId: UUID(), postingService: ps, assignmentService: as_, appState: appState)

        await MainActor.run {
            // No posting loaded yet
            #expect(vm.canPublish == false)

            // Simulate a draft posting
            vm.posting = ServicePosting(
                id: UUID(), title: "Test", siteAddress: "Addr",
                dueDate: Date().addingTimeInterval(86400), budgetCapCents: 100,
                status: .draft, acceptanceMode: .open, createdBy: UUID(),
                watermarkEnabled: false, version: 1, createdAt: Date(), updatedAt: Date()
            )
            #expect(vm.canPublish == true)

            // Open posting — can't publish
            vm.posting?.status = .open
            #expect(vm.canPublish == false)
        }
    }
}
