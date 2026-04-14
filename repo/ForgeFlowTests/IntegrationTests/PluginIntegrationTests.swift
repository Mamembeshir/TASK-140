import Testing
import Foundation
import GRDB
@testable import ForgeFlow

struct PluginIntegrationTests {

    // MARK: - Helpers

    private func makeDB() throws -> (DatabaseManager, PluginService, PostingService, UserRepository) {
        let db = try DatabaseManager(inMemory: true)
        let userRepo = UserRepository(dbPool: db.dbPool)
        let auditService = AuditService(dbPool: db.dbPool)
        let pluginRepo = PluginRepository(dbPool: db.dbPool)
        let postingRepo = PostingRepository(dbPool: db.dbPool)
        let taskRepo = TaskRepository(dbPool: db.dbPool)
        let notifRepo = NotificationRepository(dbPool: db.dbPool)
        let notifService = NotificationService(dbPool: db.dbPool, notificationRepository: notifRepo, userRepository: userRepo)
        let postingService = PostingService(
            dbPool: db.dbPool, postingRepository: postingRepo,
            taskRepository: taskRepo, userRepository: userRepo, auditService: auditService
        )
        let pluginService = PluginService(
            dbPool: db.dbPool, pluginRepository: pluginRepo,
            postingRepository: postingRepo, auditService: auditService,
            notificationService: notifService,
            userRepository: userRepo
        )
        return (db, pluginService, postingService, userRepo)
    }

    private func makeAdmin(userRepo: UserRepository, suffix: String = "") async throws -> User {
        let now = Date()
        let user = User(
            id: UUID(), username: "admin\(suffix)_\(UUID().uuidString.prefix(6))",
            role: .admin, status: .active,
            failedLoginCount: 0, lockedUntil: nil, biometricEnabled: false,
            dndStartTime: nil, dndEndTime: nil,
            storageQuotaBytes: 2_147_483_648,
            version: 1, createdAt: now, updatedAt: now
        )
        try await userRepo.insert(user)
        return user
    }

    // MARK: - Full Plugin Lifecycle

    @Test("Plugin: create → test → submit → 2 admins approve → activate")
    func fullLifecycle() async throws {
        let (db, pluginService, postingService, userRepo) = try makeDB()
        let admin1 = try await makeAdmin(userRepo: userRepo, suffix: "1")
        let admin2 = try await makeAdmin(userRepo: userRepo, suffix: "2")

        // Create plugin
        let plugin = try await pluginService.create(
            name: "PCIe Checker",
            description: "Validates PCIe gen compatibility",
            category: "Hardware",
            createdBy: admin1.id
        )
        #expect(plugin.status == .draft)

        // Add fields
        _ = try await pluginService.addField(
            pluginId: plugin.id, fieldName: "PCIe Gen", fieldType: .number,
            unit: nil, validationRules: nil, actorId: admin1.id
        )

        // Create a sample posting for testing
        let posting = try await postingService.create(
            actorId: admin1.id, title: "Test Posting",
            siteAddress: "123 Test St", dueDate: Date().addingTimeInterval(86400),
            budgetCents: 10000, acceptanceMode: .open, watermarkEnabled: false
        )

        // Test plugin
        let results = try await pluginService.testPlugin(pluginId: plugin.id, samplePostingIds: [posting.id], actorId: admin1.id)
        #expect(results.count == 1)
        #expect(results.first?.status == .pass)

        // Verify status transitioned to TESTING
        let afterTest = try await pluginService.getPlugin(plugin.id)
        #expect(afterTest?.status == .testing)

        // Submit for approval
        try await pluginService.submitForApproval(pluginId: plugin.id, actorId: admin1.id)
        let afterSubmit = try await pluginService.getPlugin(plugin.id)
        #expect(afterSubmit?.status == .pendingApproval)

        // Admin 1 approves step 1
        try await pluginService.approveStep(
            pluginId: plugin.id, approverId: admin1.id,
            step: 1, decision: .approved, notes: "Looks good"
        )
        let afterStep1 = try await pluginService.getPlugin(plugin.id)
        #expect(afterStep1?.status == .pendingApproval) // Still pending — need step 2

        // Admin 2 approves step 2
        try await pluginService.approveStep(
            pluginId: plugin.id, approverId: admin2.id,
            step: 2, decision: .approved, notes: "Confirmed"
        )
        let afterStep2 = try await pluginService.getPlugin(plugin.id)
        #expect(afterStep2?.status == .approved)

        // Activate
        try await pluginService.activate(pluginId: plugin.id, actorId: admin1.id)
        let activated = try await pluginService.getPlugin(plugin.id)
        #expect(activated?.status == .active)
    }

    // MARK: - Same Admin Both Steps → Rejected

    @Test("Plugin: same admin tries both approval steps → rejected")
    func sameAdminBothSteps() async throws {
        let (db, pluginService, postingService, userRepo) = try makeDB()
        let admin = try await makeAdmin(userRepo: userRepo)

        let plugin = try await pluginService.create(
            name: "Test Plugin", description: "Desc", category: "Cat", createdBy: admin.id
        )
        _ = try await pluginService.addField(
            pluginId: plugin.id, fieldName: "Field1", fieldType: .text,
            unit: nil, validationRules: nil, actorId: admin.id
        )
        let posting = try await postingService.create(
            actorId: admin.id, title: "P1", siteAddress: "A",
            dueDate: Date().addingTimeInterval(86400), budgetCents: 100,
            acceptanceMode: .open, watermarkEnabled: false
        )
        _ = try await pluginService.testPlugin(pluginId: plugin.id, samplePostingIds: [posting.id], actorId: admin.id)
        try await pluginService.submitForApproval(pluginId: plugin.id, actorId: admin.id)

        // Step 1
        try await pluginService.approveStep(
            pluginId: plugin.id, approverId: admin.id,
            step: 1, decision: .approved, notes: nil
        )

        // Step 2 by SAME admin → should throw
        do {
            try await pluginService.approveStep(
                pluginId: plugin.id, approverId: admin.id,
                step: 2, decision: .approved, notes: nil
            )
            throw TestError("Expected sameApproverBothSteps error")
        } catch is PluginError {
            // Expected
        }
    }

    struct TestError: Error {
        let message: String
        init(_ message: String) { self.message = message }
    }
}
