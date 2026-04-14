import Foundation
import Testing
import GRDB
@testable import ForgeFlow

@Suite("Posting Integration Tests")
struct PostingIntegrationTests {
    private func makeServices() throws -> (PostingService, AssignmentService, AuthService, DatabasePool) {
        let dbManager = try DatabaseManager(inMemory: true)
        let dbPool = dbManager.dbPool
        let userRepo = UserRepository(dbPool: dbPool)
        let auditService = AuditService(dbPool: dbPool)
        let postingRepo = PostingRepository(dbPool: dbPool)
        let assignmentRepo = AssignmentRepository(dbPool: dbPool)
        let taskRepo = TaskRepository(dbPool: dbPool)

        let authService = AuthService(dbPool: dbPool, userRepository: userRepo, auditService: auditService)
        let postingService = PostingService(dbPool: dbPool, postingRepository: postingRepo,
                                            taskRepository: taskRepo, userRepository: userRepo, auditService: auditService)
        let assignmentService = AssignmentService(dbPool: dbPool, assignmentRepository: assignmentRepo,
                                                   postingRepository: postingRepo, userRepository: userRepo, auditService: auditService)

        return (postingService, assignmentService, authService, dbPool)
    }

    private func seedUsers(authService: AuthService, dbPool: DatabasePool) async throws -> (admin: User, coord: User, tech1: User, tech2: User) {
        let now = Date()
        let admin = User(id: UUID(), username: "admin", role: .admin, status: .active, failedLoginCount: 0,
                         lockedUntil: nil, biometricEnabled: false, dndStartTime: nil, dndEndTime: nil,
                         storageQuotaBytes: 2_147_483_648, version: 1, createdAt: now, updatedAt: now)
        let coord = User(id: UUID(), username: "coord", role: .coordinator, status: .active, failedLoginCount: 0,
                         lockedUntil: nil, biometricEnabled: false, dndStartTime: nil, dndEndTime: nil,
                         storageQuotaBytes: 2_147_483_648, version: 1, createdAt: now, updatedAt: now)
        let tech1 = User(id: UUID(), username: "tech1", role: .technician, status: .active, failedLoginCount: 0,
                         lockedUntil: nil, biometricEnabled: false, dndStartTime: nil, dndEndTime: nil,
                         storageQuotaBytes: 2_147_483_648, version: 1, createdAt: now, updatedAt: now)
        let tech2 = User(id: UUID(), username: "tech2", role: .technician, status: .active, failedLoginCount: 0,
                         lockedUntil: nil, biometricEnabled: false, dndStartTime: nil, dndEndTime: nil,
                         storageQuotaBytes: 2_147_483_648, version: 1, createdAt: now, updatedAt: now)

        try await dbPool.write { db in
            try admin.insert(db); try coord.insert(db); try tech1.insert(db); try tech2.insert(db)
        }
        return (admin, coord, tech1, tech2)
    }

    @Test("Create posting produces DRAFT with root task")
    func createPostingDraftWithTask() async throws {
        let (postingService, _, _, dbPool) = try makeServices()
        let users = try await seedUsers(authService: AuthService(dbPool: dbPool, userRepository: UserRepository(dbPool: dbPool), auditService: AuditService(dbPool: dbPool)), dbPool: dbPool)

        let posting = try await postingService.create(
            actorId: users.coord.id, title: "Fix HVAC", siteAddress: "123 Main St",
            dueDate: Date().addingTimeInterval(86400 * 7), budgetCents: 250000,
            acceptanceMode: .inviteOnly, watermarkEnabled: false
        )

        #expect(posting.status == .draft)
        #expect(posting.title == "Fix HVAC")
        #expect(posting.budgetCapCents == 250000)

        let tasks = try await postingService.listTasks(postingId: posting.id, actorId: users.coord.id)
        #expect(tasks.count == 5) // 1 root + 4 template subtasks
        let root = tasks.first { $0.parentTaskId == nil }!
        #expect(root.title == "Fix HVAC")
        #expect(root.priority == .p2)
        #expect(root.status == .notStarted)
        #expect(root.parentTaskId == nil)
    }

    @Test("Publish transitions DRAFT to OPEN")
    func publishDraftToOpen() async throws {
        let (postingService, _, _, dbPool) = try makeServices()
        let users = try await seedUsers(authService: AuthService(dbPool: dbPool, userRepository: UserRepository(dbPool: dbPool), auditService: AuditService(dbPool: dbPool)), dbPool: dbPool)

        let posting = try await postingService.create(
            actorId: users.coord.id, title: "Install Panel", siteAddress: "456 Oak Ave",
            dueDate: Date().addingTimeInterval(86400 * 14), budgetCents: 500000,
            acceptanceMode: .open, watermarkEnabled: false
        )

        let published = try await postingService.publish(actorId: users.coord.id, postingId: posting.id)
        #expect(published.status == .open)
    }

    @Test("Publish rejects non-DRAFT posting")
    func publishRejectsNonDraft() async throws {
        let (postingService, _, _, dbPool) = try makeServices()
        let users = try await seedUsers(authService: AuthService(dbPool: dbPool, userRepository: UserRepository(dbPool: dbPool), auditService: AuditService(dbPool: dbPool)), dbPool: dbPool)

        let posting = try await postingService.create(
            actorId: users.coord.id, title: "Test", siteAddress: "Addr",
            dueDate: Date().addingTimeInterval(86400), budgetCents: 100, acceptanceMode: .open, watermarkEnabled: false
        )
        _ = try await postingService.publish(actorId: users.coord.id, postingId: posting.id)

        await #expect(throws: PostingError.self) {
            try await postingService.publish(actorId: users.coord.id, postingId: posting.id)
        }
    }

    @Test("Cancel transitions active posting to CANCELLED")
    func cancelPosting() async throws {
        let (postingService, _, _, dbPool) = try makeServices()
        let users = try await seedUsers(authService: AuthService(dbPool: dbPool, userRepository: UserRepository(dbPool: dbPool), auditService: AuditService(dbPool: dbPool)), dbPool: dbPool)

        let posting = try await postingService.create(
            actorId: users.coord.id, title: "Cancel Test", siteAddress: "Addr",
            dueDate: Date().addingTimeInterval(86400), budgetCents: 100, acceptanceMode: .open, watermarkEnabled: false
        )
        _ = try await postingService.publish(actorId: users.coord.id, postingId: posting.id)
        let cancelled = try await postingService.cancel(actorId: users.coord.id, postingId: posting.id)
        #expect(cancelled.status == .cancelled)
    }

    @Test("Role-based listing: admin sees all, coordinator sees own, technician sees open+assigned")
    func roleBasedListing() async throws {
        let (postingService, assignmentService, _, dbPool) = try makeServices()
        let users = try await seedUsers(authService: AuthService(dbPool: dbPool, userRepository: UserRepository(dbPool: dbPool), auditService: AuditService(dbPool: dbPool)), dbPool: dbPool)

        let posting = try await postingService.create(
            actorId: users.coord.id, title: "Role Test", siteAddress: "Addr",
            dueDate: Date().addingTimeInterval(86400), budgetCents: 100, acceptanceMode: .inviteOnly, watermarkEnabled: false
        )
        _ = try await postingService.publish(actorId: users.coord.id, postingId: posting.id)

        // Admin sees all
        let adminList = try await postingService.listPostings(role: .admin, userId: users.admin.id)
        #expect(adminList.count == 1)

        // Coordinator sees own
        let coordList = try await postingService.listPostings(role: .coordinator, userId: users.coord.id)
        #expect(coordList.count == 1)

        // Tech1 cannot see INVITE_ONLY posting before being invited
        let techList = try await postingService.listPostings(role: .technician, userId: users.tech1.id)
        #expect(techList.count == 0) // INVITE_ONLY posting not visible to uninvited tech

        // Invite tech1, tech2 should also see it after being invited
        _ = try await assignmentService.invite(actorId: users.coord.id, postingId: posting.id, technicianIds: [users.tech1.id])
        let tech1List = try await postingService.listPostings(role: .technician, userId: users.tech1.id)
        #expect(tech1List.count == 1)
    }

    @Test("Audit entries recorded for create and publish")
    func auditEntries() async throws {
        let (postingService, _, _, dbPool) = try makeServices()
        let users = try await seedUsers(authService: AuthService(dbPool: dbPool, userRepository: UserRepository(dbPool: dbPool), auditService: AuditService(dbPool: dbPool)), dbPool: dbPool)

        let posting = try await postingService.create(
            actorId: users.coord.id, title: "Audit Test", siteAddress: "Addr",
            dueDate: Date().addingTimeInterval(86400), budgetCents: 100, acceptanceMode: .open, watermarkEnabled: false
        )
        _ = try await postingService.publish(actorId: users.coord.id, postingId: posting.id)

        let auditService = AuditService(dbPool: dbPool)
        let entries = try await auditService.entries(for: "ServicePosting", entityId: posting.id)
        let actions = Set(entries.map { $0.action })
        #expect(actions.contains("POSTING_CREATED"))
        #expect(actions.contains("POSTING_PUBLISHED"))
    }
}
