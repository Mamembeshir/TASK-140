import Foundation
import Testing
import GRDB
@testable import ForgeFlow

/// Verification tests matching the STEP 2 checklist items exactly.
@Suite("Posting Verification Checklist")
struct PostingVerificationTests {
    private func makeServices() throws -> (PostingService, AssignmentService, AuditService, DatabasePool) {
        let dbManager = try DatabaseManager(inMemory: true)
        let dbPool = dbManager.dbPool
        let userRepo = UserRepository(dbPool: dbPool)
        let auditService = AuditService(dbPool: dbPool)
        let postingRepo = PostingRepository(dbPool: dbPool)
        let assignmentRepo = AssignmentRepository(dbPool: dbPool)
        let taskRepo = TaskRepository(dbPool: dbPool)

        let postingService = PostingService(
            dbPool: dbPool, postingRepository: postingRepo,
            taskRepository: taskRepo, userRepository: userRepo, auditService: auditService
        )
        let assignmentService = AssignmentService(
            dbPool: dbPool, assignmentRepository: assignmentRepo,
            postingRepository: postingRepo, userRepository: userRepo, auditService: auditService
        )
        return (postingService, assignmentService, auditService, dbPool)
    }

    private func seedUsers(dbPool: DatabasePool) async throws -> (coord: User, tech1: User, tech2: User, tech3: User) {
        let now = Date()
        func user(name: String, role: Role) -> User {
            User(id: UUID(), username: name, role: role, status: .active, failedLoginCount: 0,
                 lockedUntil: nil, biometricEnabled: false, dndStartTime: nil, dndEndTime: nil,
                 storageQuotaBytes: 2_147_483_648, version: 1, createdAt: now, updatedAt: now)
        }
        let c = user(name: "coord", role: .coordinator)
        let t1 = user(name: "tech1", role: .technician)
        let t2 = user(name: "tech2", role: .technician)
        let t3 = user(name: "tech3", role: .technician)
        try await dbPool.write { db in
            try c.insert(db); try t1.insert(db); try t2.insert(db); try t3.insert(db)
        }
        return (c, t1, t2, t3)
    }

    // ── Checklist 1: Coordinator creates posting with formatted budget "$2,500.00" ──

    @Test("Checklist: Budget stored as cents, formatted as $2,500.00")
    func budgetCentsAndFormat() async throws {
        let (ps2, _, _, dbPool) = try makeServices()
        let u = try await seedUsers(dbPool: dbPool)

        let posting = try await ps2.create(
            actorId: u.coord.id, title: "HVAC Repair", siteAddress: "123 Main St",
            dueDate: Date().addingTimeInterval(86400 * 7), budgetCents: 250000,
            acceptanceMode: .inviteOnly, watermarkEnabled: false
        )

        // Stored as integer cents
        #expect(posting.budgetCapCents == 250000)

        // Formatted correctly
        let formatted = CurrencyFormatter.format(cents: posting.budgetCapCents)
        #expect(formatted == "$2,500.00")

        // Edge cases
        #expect(CurrencyFormatter.format(cents: 99) == "$0.99")
        #expect(CurrencyFormatter.format(cents: 0) == "$0.00")
        #expect(CurrencyFormatter.format(cents: 1000000) == "$10,000.00")
    }

    // ── Checklist 2: Date picker uses MM/DD/YYYY 12-hour format ──

    @Test("Checklist: DateFormatters produce MM/DD/YYYY 12-hour format")
    func dateFormatVerification() {
        // Create a known date: January 15, 2026, 2:30 PM
        var components = DateComponents()
        components.year = 2026
        components.month = 1
        components.day = 15
        components.hour = 14
        components.minute = 30
        let date = Calendar.current.date(from: components)!

        let displayString = DateFormatters.display.string(from: date)
        #expect(displayString.contains("01/15/2026"))
        #expect(displayString.contains("2:30 PM"))

        let dateOnlyString = DateFormatters.dateOnly.string(from: date)
        #expect(dateOnlyString == "01/15/2026")
    }

    // ── Checklist 3: Publish transitions DRAFT → OPEN ──

    @Test("Checklist: Publish transitions DRAFT to OPEN")
    func publishDraftToOpen() async throws {
        let (ps, _, _, dbPool) = try makeServices()
        let users = try await seedUsers(dbPool: dbPool)

        let posting = try await ps.create(
            actorId: users.coord.id, title: "Publish Test", siteAddress: "456 Oak Ave",
            dueDate: Date().addingTimeInterval(86400 * 14), budgetCents: 500000,
            acceptanceMode: .open, watermarkEnabled: false
        )
        #expect(posting.status == .draft)

        let published = try await ps.publish(actorId: users.coord.id, postingId: posting.id)
        #expect(published.status == .open)

        // Verify in DB
        let fromDb = try await ps.getPosting(id: posting.id, actorId: users.coord.id)
        #expect(fromDb.status == .open)

        // Cannot publish again
        do {
            _ = try await ps.publish(actorId: users.coord.id, postingId: posting.id)
            Issue.record("Should reject re-publish")
        } catch let error as PostingError {
            if case .invalidStatusTransition(let from, let to) = error {
                #expect(from == .open)
                #expect(to == .open)
            } else {
                Issue.record("Expected invalidStatusTransition, got \(error)")
            }
        }
    }

    // ── Checklist 4: Technician accepts OPEN posting → ACCEPTED ──

    @Test("Checklist: Technician accepts OPEN posting")
    func technicianAcceptsOpen() async throws {
        let (ps, as_, _, dbPool) = try makeServices()
        let users = try await seedUsers(dbPool: dbPool)

        let posting = try await ps.create(
            actorId: users.coord.id, title: "Accept Test", siteAddress: "Addr",
            dueDate: Date().addingTimeInterval(86400), budgetCents: 100000,
            acceptanceMode: .open, watermarkEnabled: false
        )
        _ = try await ps.publish(actorId: users.coord.id, postingId: posting.id)

        let assignment = try await as_.accept(
            actorId: users.tech1.id, postingId: posting.id, technicianId: users.tech1.id
        )
        #expect(assignment.status == .accepted)
        #expect(assignment.acceptedAt != nil)
        #expect(assignment.technicianId == users.tech1.id)

        // Posting transitions to IN_PROGRESS
        let updatedPosting = try await ps.getPosting(id: posting.id, actorId: users.coord.id)
        #expect(updatedPosting.status == .inProgress)
    }

    // ── Checklist 5: Double-tap accept → idempotent, no duplicate ──

    @Test("Checklist: Double accept is idempotent (INVITE_ONLY)")
    func doubleAcceptIdempotent() async throws {
        let (ps, as_, _, dbPool) = try makeServices()
        let users = try await seedUsers(dbPool: dbPool)

        let posting = try await ps.create(
            actorId: users.coord.id, title: "Idempotent Test", siteAddress: "Addr",
            dueDate: Date().addingTimeInterval(86400), budgetCents: 50000,
            acceptanceMode: .inviteOnly, watermarkEnabled: false
        )
        _ = try await ps.publish(actorId: users.coord.id, postingId: posting.id)
        _ = try await as_.invite(actorId: users.coord.id, postingId: posting.id, technicianIds: [users.tech1.id])

        // First accept
        let first = try await as_.accept(actorId: users.tech1.id, postingId: posting.id, technicianId: users.tech1.id)
        #expect(first.status == .accepted)

        // Second accept — same result, no error
        let second = try await as_.accept(actorId: users.tech1.id, postingId: posting.id, technicianId: users.tech1.id)
        #expect(second.status == .accepted)
        #expect(second.id == first.id) // Same assignment

        // Only one assignment exists
        let all = try await as_.listAssignments(postingId: posting.id, actorId: users.coord.id)
        #expect(all.count == 1)
    }

    // ── Checklist 6: Second technician on OPEN posting → "Already assigned" with audit note ──

    @Test("Checklist: First-accepted-wins with audit note")
    func firstAcceptedWinsAudit() async throws {
        let (ps, as_, auditService, dbPool) = try makeServices()
        let users = try await seedUsers(dbPool: dbPool)

        let posting = try await ps.create(
            actorId: users.coord.id, title: "First Wins Test", siteAddress: "Addr",
            dueDate: Date().addingTimeInterval(86400), budgetCents: 75000,
            acceptanceMode: .open, watermarkEnabled: false
        )
        _ = try await ps.publish(actorId: users.coord.id, postingId: posting.id)

        // Tech1 accepts first — succeeds
        let winner = try await as_.accept(actorId: users.tech1.id, postingId: posting.id, technicianId: users.tech1.id)
        #expect(winner.status == .accepted)

        // Tech2 tries to accept — rejected with "Already assigned"
        do {
            _ = try await as_.accept(actorId: users.tech2.id, postingId: posting.id, technicianId: users.tech2.id)
            Issue.record("Should have thrown alreadyAssigned")
        } catch let error as AssignmentError {
            if case .alreadyAssigned(let name, let at) = error {
                #expect(name == "tech1") // Winner's name
                #expect(at.timeIntervalSince(winner.acceptedAt!) < 1) // Correct timestamp
            } else {
                Issue.record("Expected alreadyAssigned, got \(error)")
            }
        }

        // Verify audit note for blocked attempt
        let entries = try await auditService.entries(for: "ServicePosting", entityId: posting.id)
        let blocked = entries.first { $0.action == "ASSIGNMENT_ACCEPT_BLOCKED" }
        #expect(blocked != nil)
        #expect(blocked?.actorId == users.tech2.id)
        #expect(blocked?.afterData?.contains("tech1") == true)
    }

    // ── Checklist 7: INVITE_ONLY allows multiple accepted technicians ──

    @Test("Checklist: INVITE_ONLY multiple technicians independently accept")
    func inviteOnlyMultipleAccepts() async throws {
        let (ps, as_, _, dbPool) = try makeServices()
        let users = try await seedUsers(dbPool: dbPool)

        let posting = try await ps.create(
            actorId: users.coord.id, title: "Multi Accept Test", siteAddress: "Addr",
            dueDate: Date().addingTimeInterval(86400), budgetCents: 300000,
            acceptanceMode: .inviteOnly, watermarkEnabled: false
        )
        _ = try await ps.publish(actorId: users.coord.id, postingId: posting.id)

        // Invite 3 technicians
        _ = try await as_.invite(
            actorId: users.coord.id, postingId: posting.id,
            technicianIds: [users.tech1.id, users.tech2.id, users.tech3.id]
        )

        // All 3 accept independently — all should succeed
        let a1 = try await as_.accept(actorId: users.tech1.id, postingId: posting.id, technicianId: users.tech1.id)
        let a2 = try await as_.accept(actorId: users.tech2.id, postingId: posting.id, technicianId: users.tech2.id)
        let a3 = try await as_.accept(actorId: users.tech3.id, postingId: posting.id, technicianId: users.tech3.id)

        #expect(a1.status == .accepted)
        #expect(a2.status == .accepted)
        #expect(a3.status == .accepted)

        // All 3 are distinct assignments
        let all = try await as_.listAssignments(postingId: posting.id, actorId: users.coord.id)
        let acceptedCount = all.filter { $0.status == .accepted }.count
        #expect(acceptedCount == 3)
    }

    // ── Checklist 8: Auto-generated parent task exists on new posting ──

    @Test("Checklist: Auto-generated parent task matches posting title, P2, NOT_STARTED")
    func autoGeneratedParentTask() async throws {
        let (ps, _, _, dbPool) = try makeServices()
        let users = try await seedUsers(dbPool: dbPool)

        let posting = try await ps.create(
            actorId: users.coord.id, title: "Install Solar Panels", siteAddress: "789 Elm Rd",
            dueDate: Date().addingTimeInterval(86400 * 30), budgetCents: 1500000,
            acceptanceMode: .inviteOnly, watermarkEnabled: true
        )

        let tasks = try await ps.listTasks(postingId: posting.id, actorId: users.coord.id)

        // Exactly one task auto-generated
        #expect(tasks.count == 5) // 1 root + 4 template subtasks

        let rootTask = tasks.first { $0.parentTaskId == nil }!
        #expect(rootTask.title == "Install Solar Panels") // Same as posting title
        #expect(rootTask.priority == .p2) // P2 Medium
        #expect(rootTask.status == .notStarted) // NOT_STARTED
        #expect(rootTask.parentTaskId == nil) // Root task (no parent)
        #expect(rootTask.postingId == posting.id) // Linked to posting
        #expect(rootTask.assignedTo == nil) // Not assigned yet
        #expect(rootTask.sortOrder == 0) // First task
    }

    // ── Checklist 9: Audit entries for all operations ──

    @Test("Checklist: Audit entries for create, publish, cancel, invite, accept, decline")
    func auditEntriesAllOperations() async throws {
        let (ps, as_, auditService, dbPool) = try makeServices()
        let users = try await seedUsers(dbPool: dbPool)

        // 1. CREATE → POSTING_CREATED
        let posting = try await ps.create(
            actorId: users.coord.id, title: "Audit All Ops", siteAddress: "Addr",
            dueDate: Date().addingTimeInterval(86400), budgetCents: 100000,
            acceptanceMode: .inviteOnly, watermarkEnabled: false
        )

        // 2. PUBLISH → POSTING_PUBLISHED
        _ = try await ps.publish(actorId: users.coord.id, postingId: posting.id)

        // 3. INVITE → ASSIGNMENT_INVITED
        let invited = try await as_.invite(
            actorId: users.coord.id, postingId: posting.id,
            technicianIds: [users.tech1.id, users.tech2.id]
        )

        // 4. ACCEPT → ASSIGNMENT_ACCEPTED
        _ = try await as_.accept(actorId: users.tech1.id, postingId: posting.id, technicianId: users.tech1.id)

        // 5. DECLINE → ASSIGNMENT_DECLINED
        _ = try await as_.decline(actorId: users.tech2.id, postingId: posting.id, technicianId: users.tech2.id)

        // Create another posting to test CANCEL
        let posting2 = try await ps.create(
            actorId: users.coord.id, title: "Cancel Audit", siteAddress: "Addr",
            dueDate: Date().addingTimeInterval(86400), budgetCents: 50000,
            acceptanceMode: .open, watermarkEnabled: false
        )
        _ = try await ps.publish(actorId: users.coord.id, postingId: posting2.id)

        // 6. CANCEL → POSTING_CANCELLED
        _ = try await ps.cancel(actorId: users.coord.id, postingId: posting2.id)

        // Verify posting audit entries
        let postingEntries = try await auditService.entries(for: "ServicePosting", entityId: posting.id)
        let postingActions = Set(postingEntries.map { $0.action })
        #expect(postingActions.contains("POSTING_CREATED"))
        #expect(postingActions.contains("POSTING_PUBLISHED"))

        // Verify cancel audit
        let cancelEntries = try await auditService.entries(for: "ServicePosting", entityId: posting2.id)
        let cancelActions = Set(cancelEntries.map { $0.action })
        #expect(cancelActions.contains("POSTING_CANCELLED"))

        // Verify assignment audit entries
        for inv in invited {
            let entries = try await auditService.entries(for: "Assignment", entityId: inv.id)
            #expect(entries.contains { $0.action == "ASSIGNMENT_INVITED" })
        }

        // Verify accept audit (find tech1's assignment)
        let allAssignments = try await as_.listAssignments(postingId: posting.id, actorId: users.coord.id)
        let tech1Assignment = allAssignments.first { $0.technicianId == users.tech1.id }
        if let a = tech1Assignment {
            let entries = try await auditService.entries(for: "Assignment", entityId: a.id)
            #expect(entries.contains { $0.action == "ASSIGNMENT_ACCEPTED" })
        }

        // Verify decline audit
        let tech2Assignment = allAssignments.first { $0.technicianId == users.tech2.id }
        if let a = tech2Assignment {
            let entries = try await auditService.entries(for: "Assignment", entityId: a.id)
            #expect(entries.contains { $0.action == "ASSIGNMENT_DECLINED" })
        }

        // Verify all entries have required fields
        let recentEntries = try await auditService.recentEntries(limit: 100)
        for entry in recentEntries {
            #expect(!entry.action.isEmpty)
            #expect(!entry.entityType.isEmpty)
        }
    }
}
