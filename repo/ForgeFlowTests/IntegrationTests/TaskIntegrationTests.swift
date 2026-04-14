import Foundation
import Testing
import GRDB
@testable import ForgeFlow

@Suite("Task Integration Tests")
struct TaskIntegrationTests {
    private func makeServices() throws -> (TaskService, PostingService, AssignmentService, AuditService, DatabasePool) {
        let dbManager = try DatabaseManager(inMemory: true)
        let dbPool = dbManager.dbPool
        let userRepo = UserRepository(dbPool: dbPool)
        let auditService = AuditService(dbPool: dbPool)
        let postingRepo = PostingRepository(dbPool: dbPool)
        let assignmentRepo = AssignmentRepository(dbPool: dbPool)
        let taskRepo = TaskRepository(dbPool: dbPool)
        let depRepo = DependencyRepository(dbPool: dbPool)

        let postingService = PostingService(dbPool: dbPool, postingRepository: postingRepo,
                                            taskRepository: taskRepo, userRepository: userRepo, auditService: auditService)
        let assignmentService = AssignmentService(dbPool: dbPool, assignmentRepository: assignmentRepo,
                                                   postingRepository: postingRepo, userRepository: userRepo, auditService: auditService)
        let taskService = TaskService(dbPool: dbPool, taskRepository: taskRepo,
                                      dependencyRepository: depRepo, postingRepository: postingRepo, auditService: auditService,
                                      userRepository: userRepo)

        return (taskService, postingService, assignmentService, auditService, dbPool)
    }

    private func seedCoord(dbPool: DatabasePool) async throws -> User {
        let now = Date()
        let coord = User(id: UUID(), username: "coord", role: .coordinator, status: .active, failedLoginCount: 0,
                         lockedUntil: nil, biometricEnabled: false, dndStartTime: nil, dndEndTime: nil,
                         storageQuotaBytes: 2_147_483_648, version: 1, createdAt: now, updatedAt: now)
        try await dbPool.write { db in try coord.insert(db) }
        return coord
    }

    private func createPosting(_ ps: PostingService, actorId: UUID) async throws -> ServicePosting {
        try await ps.create(
            actorId: actorId, title: "Test Posting", siteAddress: "123 Main",
            dueDate: Date().addingTimeInterval(86400 * 7), budgetCents: 100000,
            acceptanceMode: .inviteOnly, watermarkEnabled: false
        )
    }

    // MARK: - Create Subtask

    @Test("Create subtask linked to parent")
    func createSubtask() async throws {
        let (ts, ps, _, _, dbPool) = try makeServices()
        let coord = try await seedCoord(dbPool: dbPool)
        let posting = try await createPosting(ps, actorId: coord.id)
        let tasks = try await ts.listTasks(postingId: posting.id, actorId: coord.id)
        let parent = tasks.first { $0.parentTaskId == nil }!

        let subtask = try await ts.createSubtask(
            actorId: coord.id, parentTaskId: parent.id,
            title: "Subtask A", priority: .p1, assignedTo: nil
        )

        #expect(subtask.parentTaskId == parent.id)
        #expect(subtask.title == "Subtask A")
        #expect(subtask.priority == .p1)
        #expect(subtask.postingId == posting.id)
    }

    // MARK: - Status Transitions

    @Test("NOT_STARTED → IN_PROGRESS → DONE")
    func normalStatusFlow() async throws {
        let (ts, ps, _, _, dbPool) = try makeServices()
        let coord = try await seedCoord(dbPool: dbPool)
        let posting = try await createPosting(ps, actorId: coord.id)
        let tasks = try await ts.listTasks(postingId: posting.id, actorId: coord.id)
        // Use a leaf subtask (no children) for clean status transitions
        let leaf = tasks.first { $0.parentTaskId != nil }!

        let started = try await ts.updateStatus(actorId: coord.id, taskId: leaf.id, newStatus: .inProgress)
        #expect(started.status == .inProgress)

        let done = try await ts.updateStatus(actorId: coord.id, taskId: leaf.id, newStatus: .done)
        #expect(done.status == .done)
    }

    @Test("BLOCKED without comment fails (TASK-04)")
    func blockedWithoutComment() async throws {
        let (ts, ps, _, _, dbPool) = try makeServices()
        let coord = try await seedCoord(dbPool: dbPool)
        let posting = try await createPosting(ps, actorId: coord.id)
        let tasks = try await ts.listTasks(postingId: posting.id, actorId: coord.id)

        do {
            _ = try await ts.updateStatus(actorId: coord.id, taskId: tasks.first { $0.parentTaskId != nil }!.id, newStatus: .blocked)
            Issue.record("Should require blocked comment")
        } catch let error as TaskError {
            if case .blockedCommentRequired = error { /* expected */ }
            else { Issue.record("Expected blockedCommentRequired, got \(error)") }
        }
    }

    @Test("BLOCKED with short comment fails (< 10 chars)")
    func blockedShortComment() async throws {
        let (ts, ps, _, _, dbPool) = try makeServices()
        let coord = try await seedCoord(dbPool: dbPool)
        let posting = try await createPosting(ps, actorId: coord.id)
        let tasks = try await ts.listTasks(postingId: posting.id, actorId: coord.id)

        do {
            _ = try await ts.updateStatus(actorId: coord.id, taskId: tasks.first { $0.parentTaskId != nil }!.id,
                                          newStatus: .blocked, blockedComment: "short")
            Issue.record("Should reject short comment")
        } catch let error as TaskError {
            if case .blockedCommentTooShort = error { /* expected */ }
            else { Issue.record("Expected blockedCommentTooShort, got \(error)") }
        }
    }

    @Test("BLOCKED with valid comment succeeds")
    func blockedValidComment() async throws {
        let (ts, ps, _, _, dbPool) = try makeServices()
        let coord = try await seedCoord(dbPool: dbPool)
        let posting = try await createPosting(ps, actorId: coord.id)
        let tasks = try await ts.listTasks(postingId: posting.id, actorId: coord.id)

        let blocked = try await ts.updateStatus(
            actorId: coord.id, taskId: tasks.first { $0.parentTaskId != nil }!.id,
            newStatus: .blocked, blockedComment: "Waiting for parts to arrive from supplier"
        )
        #expect(blocked.status == .blocked)
        #expect(blocked.blockedComment == "Waiting for parts to arrive from supplier")
    }

    // MARK: - Dependencies (TASK-05)

    @Test("Cannot start task with unmet dependency")
    func dependencyEnforcement() async throws {
        let (ts, ps, _, _, dbPool) = try makeServices()
        let coord = try await seedCoord(dbPool: dbPool)
        let posting = try await createPosting(ps, actorId: coord.id)
        let tasks = try await ts.listTasks(postingId: posting.id, actorId: coord.id)
        let parent = tasks.first { $0.parentTaskId == nil }!

        let taskA = try await ts.createSubtask(actorId: coord.id, parentTaskId: parent.id,
                                                title: "Task A", priority: .p2, assignedTo: nil)
        let taskB = try await ts.createSubtask(actorId: coord.id, parentTaskId: parent.id,
                                                title: "Task B", priority: .p2, assignedTo: nil)

        _ = try await ts.addDependency(actorId: coord.id, taskId: taskB.id, dependsOnTaskId: taskA.id)

        // Try to start B while A is NOT_STARTED
        do {
            _ = try await ts.updateStatus(actorId: coord.id, taskId: taskB.id, newStatus: .inProgress)
            Issue.record("Should fail due to unmet dependency")
        } catch let error as TaskError {
            if case .unmetDependencies = error { /* expected */ }
            else { Issue.record("Expected unmetDependencies, got \(error)") }
        }

        // Complete A, then B can start
        _ = try await ts.updateStatus(actorId: coord.id, taskId: taskA.id, newStatus: .inProgress)
        _ = try await ts.updateStatus(actorId: coord.id, taskId: taskA.id, newStatus: .done)
        let startedB = try await ts.updateStatus(actorId: coord.id, taskId: taskB.id, newStatus: .inProgress)
        #expect(startedB.status == .inProgress)
    }

    // MARK: - Parent Complete (TASK-06)

    @Test("Parent DONE requires all subtasks DONE")
    func parentRequiresSubtasksDone() async throws {
        let (ts, ps, _, _, dbPool) = try makeServices()
        let coord = try await seedCoord(dbPool: dbPool)
        let posting = try await createPosting(ps, actorId: coord.id)
        let tasks = try await ts.listTasks(postingId: posting.id, actorId: coord.id)
        let parent = tasks.first { $0.parentTaskId == nil }!

        // Complete all auto-generated subtasks first
        let autoSubs = tasks.filter { $0.parentTaskId == parent.id }.sorted { $0.sortOrder < $1.sortOrder }
        for sub in autoSubs {
            _ = try await ts.updateStatus(actorId: coord.id, taskId: sub.id, newStatus: .inProgress)
            _ = try await ts.updateStatus(actorId: coord.id, taskId: sub.id, newStatus: .done)
        }

        // Create new subtasks (these are NOT done)
        let sub1 = try await ts.createSubtask(actorId: coord.id, parentTaskId: parent.id,
                                               title: "Sub 1", priority: .p2, assignedTo: nil)
        let sub2 = try await ts.createSubtask(actorId: coord.id, parentTaskId: parent.id,
                                               title: "Sub 2", priority: .p2, assignedTo: nil)

        // Start parent
        _ = try await ts.updateStatus(actorId: coord.id, taskId: parent.id, newStatus: .inProgress)

        // Try to complete parent while new subtasks not done
        do {
            _ = try await ts.updateStatus(actorId: coord.id, taskId: parent.id, newStatus: .done)
            Issue.record("Should fail — subtasks not done")
        } catch let error as TaskError {
            if case .subtasksNotComplete = error { /* expected */ }
            else { Issue.record("Expected subtasksNotComplete, got \(error)") }
        }

        // Complete both subtasks
        _ = try await ts.updateStatus(actorId: coord.id, taskId: sub1.id, newStatus: .inProgress)
        _ = try await ts.updateStatus(actorId: coord.id, taskId: sub1.id, newStatus: .done)
        _ = try await ts.updateStatus(actorId: coord.id, taskId: sub2.id, newStatus: .inProgress)
        _ = try await ts.updateStatus(actorId: coord.id, taskId: sub2.id, newStatus: .done)

        // Now parent can complete
        let parentDone = try await ts.updateStatus(actorId: coord.id, taskId: parent.id, newStatus: .done)
        #expect(parentDone.status == .done)
    }

    // MARK: - Auto-Complete Posting (TASK-07)

    @Test("Completing all tasks auto-completes posting")
    func postingAutoComplete() async throws {
        let (ts, ps, as_, _, dbPool) = try makeServices()
        let coord = try await seedCoord(dbPool: dbPool)

        // Create and publish posting, make it IN_PROGRESS via assignment accept
        let posting = try await createPosting(ps, actorId: coord.id)
        let published = try await ps.publish(actorId: coord.id, postingId: posting.id)

        // Create a technician and accept to move posting to IN_PROGRESS
        let now = Date()
        let tech = User(id: UUID(), username: "tech", role: .technician, status: .active, failedLoginCount: 0,
                        lockedUntil: nil, biometricEnabled: false, dndStartTime: nil, dndEndTime: nil,
                        storageQuotaBytes: 2_147_483_648, version: 1, createdAt: now, updatedAt: now)
        try await dbPool.write { db in try tech.insert(db) }
        _ = try await as_.invite(actorId: coord.id, postingId: published.id, technicianIds: [tech.id])
        _ = try await as_.accept(actorId: tech.id, postingId: published.id, technicianId: tech.id)

        // Verify posting is IN_PROGRESS
        let inProgress = try await ps.getPosting(id: posting.id, actorId: coord.id)
        #expect(inProgress.status == .inProgress)

        // Complete all auto-generated tasks (subtasks first, then root)
        let tasks = try await ts.listTasks(postingId: posting.id, actorId: coord.id)
        let rootTask = tasks.first { $0.parentTaskId == nil }!
        let subtasks = tasks.filter { $0.parentTaskId == rootTask.id }.sorted { $0.sortOrder < $1.sortOrder }
        for sub in subtasks {
            _ = try await ts.updateStatus(actorId: coord.id, taskId: sub.id, newStatus: .inProgress)
            _ = try await ts.updateStatus(actorId: coord.id, taskId: sub.id, newStatus: .done)
        }
        _ = try await ts.updateStatus(actorId: coord.id, taskId: rootTask.id, newStatus: .inProgress)
        _ = try await ts.updateStatus(actorId: coord.id, taskId: rootTask.id, newStatus: .done)

        // Posting should now be COMPLETED
        let completed = try await ps.getPosting(id: posting.id, actorId: coord.id)
        #expect(completed.status == .completed)
    }

    // MARK: - Audit

    @Test("Audit entries for task status changes")
    func auditEntries() async throws {
        let (ts, ps, _, auditService, dbPool) = try makeServices()
        let coord = try await seedCoord(dbPool: dbPool)
        let posting = try await createPosting(ps, actorId: coord.id)
        let tasks = try await ts.listTasks(postingId: posting.id, actorId: coord.id)

        _ = try await ts.updateStatus(actorId: coord.id, taskId: tasks.first { $0.parentTaskId != nil }!.id, newStatus: .inProgress)

        let entries = try await auditService.entries(for: "Task", entityId: tasks.first { $0.parentTaskId != nil }!.id)
        let actions = entries.map { $0.action }
        #expect(actions.contains("TASK_STATUS_CHANGED"))
    }
}
