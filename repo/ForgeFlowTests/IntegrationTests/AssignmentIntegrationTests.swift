import Foundation
import Testing
import GRDB
@testable import ForgeFlow

@Suite("Assignment Integration Tests")
struct AssignmentIntegrationTests {
    private func makeServices() throws -> (PostingService, AssignmentService, DatabasePool) {
        let dbManager = try DatabaseManager(inMemory: true)
        let dbPool = dbManager.dbPool
        let userRepo = UserRepository(dbPool: dbPool)
        let auditService = AuditService(dbPool: dbPool)
        let postingRepo = PostingRepository(dbPool: dbPool)
        let assignmentRepo = AssignmentRepository(dbPool: dbPool)
        let taskRepo = TaskRepository(dbPool: dbPool)

        let postingService = PostingService(dbPool: dbPool, postingRepository: postingRepo,
                                            taskRepository: taskRepo, userRepository: userRepo, auditService: auditService)
        let assignmentService = AssignmentService(dbPool: dbPool, assignmentRepository: assignmentRepo,
                                                   postingRepository: postingRepo, userRepository: userRepo, auditService: auditService)

        return (postingService, assignmentService, dbPool)
    }

    private func seedUsers(dbPool: DatabasePool) async throws -> (coord: User, tech1: User, tech2: User, tech3: User) {
        let now = Date()
        func user(name: String, role: Role) -> User {
            User(id: UUID(), username: name, role: role, status: .active, failedLoginCount: 0,
                 lockedUntil: nil, biometricEnabled: false, dndStartTime: nil, dndEndTime: nil,
                 storageQuotaBytes: 2_147_483_648, version: 1, createdAt: now, updatedAt: now)
        }
        let coord = user(name: "coord", role: .coordinator)
        let t1 = user(name: "tech1", role: .technician)
        let t2 = user(name: "tech2", role: .technician)
        let t3 = user(name: "tech3", role: .technician)
        try await dbPool.write { db in
            try coord.insert(db); try t1.insert(db); try t2.insert(db); try t3.insert(db)
        }
        return (coord, t1, t2, t3)
    }

    private func createAndPublish(_ ps: PostingService, actorId: UUID, mode: AcceptanceMode) async throws -> ServicePosting {
        let posting = try await ps.create(
            actorId: actorId, title: "Test Posting", siteAddress: "123 Main",
            dueDate: Date().addingTimeInterval(86400 * 7), budgetCents: 100000,
            acceptanceMode: mode, watermarkEnabled: false
        )
        return try await ps.publish(actorId: actorId, postingId: posting.id)
    }

    @Test("Invite creates INVITED assignments")
    func inviteCreatesInvited() async throws {
        let (ps, as_, dbPool) = try makeServices()
        let users = try await seedUsers(dbPool: dbPool)
        let posting = try await createAndPublish(ps, actorId: users.coord.id, mode: .inviteOnly)

        let assignments = try await as_.invite(actorId: users.coord.id, postingId: posting.id,
                                                technicianIds: [users.tech1.id, users.tech2.id])

        #expect(assignments.count == 2)
        #expect(assignments.allSatisfy { $0.status == .invited })
    }

    @Test("Accept transitions INVITED to ACCEPTED for INVITE_ONLY")
    func acceptInviteOnly() async throws {
        let (ps, as_, dbPool) = try makeServices()
        let users = try await seedUsers(dbPool: dbPool)
        let posting = try await createAndPublish(ps, actorId: users.coord.id, mode: .inviteOnly)

        _ = try await as_.invite(actorId: users.coord.id, postingId: posting.id, technicianIds: [users.tech1.id])
        let accepted = try await as_.accept(actorId: users.tech1.id, postingId: posting.id, technicianId: users.tech1.id)

        #expect(accepted.status == .accepted)
        #expect(accepted.acceptedAt != nil)
    }

    @Test("INVITE_ONLY: multiple technicians can independently accept")
    func inviteOnlyMultiAccept() async throws {
        let (ps, as_, dbPool) = try makeServices()
        let users = try await seedUsers(dbPool: dbPool)
        let posting = try await createAndPublish(ps, actorId: users.coord.id, mode: .inviteOnly)

        _ = try await as_.invite(actorId: users.coord.id, postingId: posting.id,
                                  technicianIds: [users.tech1.id, users.tech2.id, users.tech3.id])

        let a1 = try await as_.accept(actorId: users.tech1.id, postingId: posting.id, technicianId: users.tech1.id)
        let a2 = try await as_.accept(actorId: users.tech2.id, postingId: posting.id, technicianId: users.tech2.id)
        let a3 = try await as_.accept(actorId: users.tech3.id, postingId: posting.id, technicianId: users.tech3.id)

        #expect(a1.status == .accepted)
        #expect(a2.status == .accepted)
        #expect(a3.status == .accepted)
    }

    @Test("OPEN: first-accepted-wins rejects second technician")
    func firstAcceptedWins() async throws {
        let (ps, as_, dbPool) = try makeServices()
        let users = try await seedUsers(dbPool: dbPool)
        let posting = try await createAndPublish(ps, actorId: users.coord.id, mode: .open)

        // Tech1 accepts first
        let accepted = try await as_.accept(actorId: users.tech1.id, postingId: posting.id, technicianId: users.tech1.id)
        #expect(accepted.status == .accepted)

        // Tech2 tries to accept — should be rejected
        do {
            _ = try await as_.accept(actorId: users.tech2.id, postingId: posting.id, technicianId: users.tech2.id)
            Issue.record("Should have thrown alreadyAssigned")
        } catch let error as AssignmentError {
            if case .alreadyAssigned(let name, _) = error {
                #expect(name == "tech1")
            } else {
                Issue.record("Expected alreadyAssigned, got \(error)")
            }
        }

        // Verify audit has the blocked attempt
        let auditService = AuditService(dbPool: dbPool)
        let entries = try await auditService.entries(for: "ServicePosting", entityId: posting.id)
        let blocked = entries.first { $0.action == "ASSIGNMENT_ACCEPT_BLOCKED" }
        #expect(blocked != nil)
    }

    @Test("INVITE_ONLY: accept is idempotent for same technician")
    func acceptIdempotent() async throws {
        let (ps, as_, dbPool) = try makeServices()
        let users = try await seedUsers(dbPool: dbPool)
        let posting = try await createAndPublish(ps, actorId: users.coord.id, mode: .inviteOnly)

        _ = try await as_.invite(actorId: users.coord.id, postingId: posting.id, technicianIds: [users.tech1.id])

        let first = try await as_.accept(actorId: users.tech1.id, postingId: posting.id, technicianId: users.tech1.id)
        let second = try await as_.accept(actorId: users.tech1.id, postingId: posting.id, technicianId: users.tech1.id)

        #expect(first.status == .accepted)
        #expect(second.status == .accepted)
        #expect(first.id == second.id) // Same assignment returned
    }

    @Test("Decline transitions INVITED to DECLINED")
    func declineInvited() async throws {
        let (ps, as_, dbPool) = try makeServices()
        let users = try await seedUsers(dbPool: dbPool)
        let posting = try await createAndPublish(ps, actorId: users.coord.id, mode: .inviteOnly)

        _ = try await as_.invite(actorId: users.coord.id, postingId: posting.id, technicianIds: [users.tech1.id])
        let declined = try await as_.decline(actorId: users.tech1.id, postingId: posting.id, technicianId: users.tech1.id)

        #expect(declined.status == .declined)
    }

    @Test("Decline rejects non-INVITED assignment")
    func declineRejectsNonInvited() async throws {
        let (ps, as_, dbPool) = try makeServices()
        let users = try await seedUsers(dbPool: dbPool)
        let posting = try await createAndPublish(ps, actorId: users.coord.id, mode: .inviteOnly)

        _ = try await as_.invite(actorId: users.coord.id, postingId: posting.id, technicianIds: [users.tech1.id])
        _ = try await as_.accept(actorId: users.tech1.id, postingId: posting.id, technicianId: users.tech1.id)

        await #expect(throws: AssignmentError.self) {
            try await as_.decline(actorId: users.tech1.id, postingId: posting.id, technicianId: users.tech1.id)
        }
    }

    @Test("Invite is idempotent for same technician")
    func inviteIdempotent() async throws {
        let (ps, as_, dbPool) = try makeServices()
        let users = try await seedUsers(dbPool: dbPool)
        let posting = try await createAndPublish(ps, actorId: users.coord.id, mode: .inviteOnly)

        let first = try await as_.invite(actorId: users.coord.id, postingId: posting.id, technicianIds: [users.tech1.id])
        let second = try await as_.invite(actorId: users.coord.id, postingId: posting.id, technicianIds: [users.tech1.id])

        #expect(first.count == 1)
        #expect(second.count == 0) // No new assignments created

        let all = try await as_.listAssignments(postingId: posting.id, actorId: users.coord.id)
        #expect(all.count == 1) // Only one assignment exists
    }

    @Test("Accept transitions posting from OPEN to IN_PROGRESS")
    func acceptTransitionsPostingStatus() async throws {
        let (ps, as_, dbPool) = try makeServices()
        let users = try await seedUsers(dbPool: dbPool)
        let posting = try await createAndPublish(ps, actorId: users.coord.id, mode: .open)

        #expect(posting.status == .open)

        _ = try await as_.accept(actorId: users.tech1.id, postingId: posting.id, technicianId: users.tech1.id)

        let updated = try await ps.getPosting(id: posting.id, actorId: users.coord.id)
        #expect(updated.status == .inProgress)
    }

    @Test("Audit entries for invite, accept, decline")
    func auditEntries() async throws {
        let (ps, as_, dbPool) = try makeServices()
        let users = try await seedUsers(dbPool: dbPool)
        let posting = try await createAndPublish(ps, actorId: users.coord.id, mode: .inviteOnly)

        let invited = try await as_.invite(actorId: users.coord.id, postingId: posting.id,
                                            technicianIds: [users.tech1.id, users.tech2.id])
        _ = try await as_.accept(actorId: users.tech1.id, postingId: posting.id, technicianId: users.tech1.id)
        _ = try await as_.decline(actorId: users.tech2.id, postingId: posting.id, technicianId: users.tech2.id)

        let auditService = AuditService(dbPool: dbPool)

        let a1Entries = try await auditService.entries(for: "Assignment", entityId: invited[0].id)
        #expect(a1Entries.contains { $0.action == "ASSIGNMENT_INVITED" })

        let tech1Assignment = try await dbPool.read { db in
            try Assignment.filter(Assignment.Columns.technicianId == users.tech1.id).fetchOne(db)
        }
        if let id = tech1Assignment?.id {
            let acceptEntries = try await auditService.entries(for: "Assignment", entityId: id)
            #expect(acceptEntries.contains { $0.action == "ASSIGNMENT_ACCEPTED" })
        }
    }
}
