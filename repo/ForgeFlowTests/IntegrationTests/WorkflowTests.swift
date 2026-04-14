import Testing
import Foundation
import GRDB
@testable import ForgeFlow

struct WorkflowTests {

    private func makeDB() throws -> WorkflowContext {
        let db = try DatabaseManager(inMemory: true)
        let dbPool = db.dbPool
        let userRepo = UserRepository(dbPool: dbPool)
        let auditService = AuditService(dbPool: dbPool)
        let postingRepo = PostingRepository(dbPool: dbPool)
        let assignmentRepo = AssignmentRepository(dbPool: dbPool)
        let taskRepo = TaskRepository(dbPool: dbPool)
        let depRepo = DependencyRepository(dbPool: dbPool)
        let notifRepo = NotificationRepository(dbPool: dbPool)
        let notifService = NotificationService(dbPool: dbPool, notificationRepository: notifRepo, userRepository: userRepo)

        let postingService = PostingService(
            dbPool: dbPool, postingRepository: postingRepo,
            taskRepository: taskRepo, userRepository: userRepo, auditService: auditService,
            notificationService: notifService, assignmentRepository: assignmentRepo
        )
        let assignmentService = AssignmentService(
            dbPool: dbPool, assignmentRepository: assignmentRepo,
            postingRepository: postingRepo, userRepository: userRepo,
            auditService: auditService, notificationService: notifService
        )
        let taskService = TaskService(
            dbPool: dbPool, taskRepository: taskRepo, dependencyRepository: depRepo,
            postingRepository: postingRepo, auditService: auditService,
            notificationService: notifService, postingService: postingService,
            userRepository: userRepo
        )

        return WorkflowContext(
            db: db, userRepo: userRepo, postingService: postingService,
            assignmentService: assignmentService, taskService: taskService
        )
    }

    private func makeUser(_ ctx: WorkflowContext, role: Role) async throws -> User {
        let now = Date()
        let user = User(
            id: UUID(), username: "\(role.rawValue.lowercased())_\(UUID().uuidString.prefix(6))",
            role: role, status: .active,
            failedLoginCount: 0, lockedUntil: nil, biometricEnabled: false,
            dndStartTime: nil, dndEndTime: nil,
            storageQuotaBytes: 2_147_483_648,
            version: 1, createdAt: now, updatedAt: now
        )
        try await ctx.userRepo.insert(user)
        return user
    }

    struct WorkflowContext {
        let db: DatabaseManager
        let userRepo: UserRepository
        let postingService: PostingService
        let assignmentService: AssignmentService
        let taskService: TaskService
    }

    // MARK: - 1. Coordinator Lifecycle

    @Test("Workflow: create posting → publish → accept → complete tasks → auto-complete")
    func coordinatorLifecycle() async throws {
        let ctx = try makeDB()
        let coord = try await makeUser(ctx, role: .coordinator)
        let tech = try await makeUser(ctx, role: .technician)

        let posting = try await ctx.postingService.create(
            actorId: coord.id, title: "HVAC Install",
            siteAddress: "100 Main St", dueDate: Date().addingTimeInterval(86400),
            budgetCents: 250000, acceptanceMode: .open, watermarkEnabled: false
        )
        _ = try await ctx.postingService.publish(actorId: coord.id, postingId: posting.id)
        _ = try await ctx.assignmentService.accept(actorId: tech.id, postingId: posting.id, technicianId: tech.id)

        // Get the auto-created tasks (root + template subtasks)
        let allTasks = try await ctx.taskService.listTasks(postingId: posting.id, actorId: coord.id)
        let parent = allTasks.first { $0.parentTaskId == nil }!
        let subtasks = allTasks.filter { $0.parentTaskId == parent.id }

        // Complete all subtasks in dependency order
        for sub in subtasks.sorted(by: { $0.sortOrder < $1.sortOrder }) {
            _ = try await ctx.taskService.updateStatus(actorId: coord.id, taskId: sub.id, newStatus: .inProgress)
            _ = try await ctx.taskService.updateStatus(actorId: coord.id, taskId: sub.id, newStatus: .done)
        }

        // Complete parent
        _ = try await ctx.taskService.updateStatus(actorId: coord.id, taskId: parent.id, newStatus: .inProgress)
        _ = try await ctx.taskService.updateStatus(actorId: coord.id, taskId: parent.id, newStatus: .done)

        try await Task.sleep(for: .milliseconds(100))
        let finalPosting = try await ctx.postingService.getPosting(id: posting.id, actorId: coord.id)
        #expect(finalPosting.status == .completed)
    }

    // MARK: - 2. Task Dependencies

    @Test("Workflow: task B depends on A → cannot start B until A is DONE")
    func taskDependencies() async throws {
        let ctx = try makeDB()
        let coord = try await makeUser(ctx, role: .coordinator)

        let posting = try await ctx.postingService.create(
            actorId: coord.id, title: "Dep Test",
            siteAddress: "A", dueDate: Date().addingTimeInterval(86400),
            budgetCents: 100, acceptanceMode: .open, watermarkEnabled: false
        )
        _ = try await ctx.postingService.publish(actorId: coord.id, postingId: posting.id)

        let tasks = try await ctx.taskService.listTasks(postingId: posting.id, actorId: coord.id)
        let parent = tasks.first { $0.parentTaskId == nil }!

        let taskA = try await ctx.taskService.createSubtask(
            actorId: coord.id, parentTaskId: parent.id, title: "Task A", priority: .p1, assignedTo: nil
        )
        let taskB = try await ctx.taskService.createSubtask(
            actorId: coord.id, parentTaskId: parent.id, title: "Task B", priority: .p2, assignedTo: nil
        )
        _ = try await ctx.taskService.addDependency(actorId: coord.id, taskId: taskB.id, dependsOnTaskId: taskA.id)

        // Try to start B → should fail
        do {
            _ = try await ctx.taskService.updateStatus(actorId: coord.id, taskId: taskB.id, newStatus: .inProgress)
            throw WorkflowError("Expected unmetDependencies")
        } catch is TaskError {
            // Expected
        }

        // Complete A, then start B
        _ = try await ctx.taskService.updateStatus(actorId: coord.id, taskId: taskA.id, newStatus: .inProgress)
        _ = try await ctx.taskService.updateStatus(actorId: coord.id, taskId: taskA.id, newStatus: .done)
        let updatedB = try await ctx.taskService.updateStatus(actorId: coord.id, taskId: taskB.id, newStatus: .inProgress)
        #expect(updatedB.status == .inProgress)
    }

    // MARK: - 11. Idempotency

    @Test("Workflow: double-accept assignment → idempotent")
    func doubleAcceptIdempotent() async throws {
        let ctx = try makeDB()
        let coord = try await makeUser(ctx, role: .coordinator)
        let tech = try await makeUser(ctx, role: .technician)

        let posting = try await ctx.postingService.create(
            actorId: coord.id, title: "Idempotent Test",
            siteAddress: "A", dueDate: Date().addingTimeInterval(86400),
            budgetCents: 100, acceptanceMode: .inviteOnly, watermarkEnabled: false
        )
        _ = try await ctx.postingService.publish(actorId: coord.id, postingId: posting.id)
        _ = try await ctx.assignmentService.invite(
            actorId: coord.id, postingId: posting.id, technicianIds: [tech.id]
        )

        let first = try await ctx.assignmentService.accept(
            actorId: tech.id, postingId: posting.id, technicianId: tech.id
        )
        let second = try await ctx.assignmentService.accept(
            actorId: tech.id, postingId: posting.id, technicianId: tech.id
        )
        #expect(first.id == second.id)
    }

    struct WorkflowError: Error {
        let message: String
        init(_ msg: String) { self.message = msg }
    }
}
