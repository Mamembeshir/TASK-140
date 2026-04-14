import Foundation
import Testing
@testable import ForgeFlow

@Suite("Task View Tests")
struct TaskViewTests {

    @Test("TaskListViewModel groups parent and subtasks")
    func taskHierarchy() async throws {
        let dbManager = try DatabaseManager(inMemory: true)
        let dbPool = dbManager.dbPool
        let taskRepo = TaskRepository(dbPool: dbPool)
        let depRepo = DependencyRepository(dbPool: dbPool)
        let postingRepo = PostingRepository(dbPool: dbPool)
        let auditService = AuditService(dbPool: dbPool)
        let userRepo = UserRepository(dbPool: dbPool)
        let taskService = TaskService(dbPool: dbPool, taskRepository: taskRepo,
                                      dependencyRepository: depRepo, postingRepository: postingRepo,
                                      auditService: auditService, userRepository: userRepo)

        // Seed user and posting
        let now = Date()
        let coord = User(id: UUID(), username: "coord", role: .coordinator, status: .active,
                         failedLoginCount: 0, lockedUntil: nil, biometricEnabled: false,
                         dndStartTime: nil, dndEndTime: nil, storageQuotaBytes: 2_147_483_648,
                         version: 1, createdAt: now, updatedAt: now)
        try await dbPool.write { db in try coord.insert(db) }

        let ps = PostingService(dbPool: dbPool, postingRepository: postingRepo,
                                taskRepository: taskRepo, userRepository: UserRepository(dbPool: dbPool),
                                auditService: auditService)
        let posting = try await ps.create(
            actorId: coord.id, title: "Hierarchy Test", siteAddress: "Addr",
            dueDate: Date().addingTimeInterval(86400), budgetCents: 100,
            acceptanceMode: .open, watermarkEnabled: false
        )

        let tasks = try await taskService.listTasks(postingId: posting.id, actorId: coord.id)
        let parent = tasks.first { $0.parentTaskId == nil }!

        _ = try await taskService.createSubtask(actorId: coord.id, parentTaskId: parent.id,
                                                 title: "Sub A", priority: .p0, assignedTo: nil)
        _ = try await taskService.createSubtask(actorId: coord.id, parentTaskId: parent.id,
                                                 title: "Sub B", priority: .p3, assignedTo: nil)

        let appState = AppState()
        appState.login(userId: coord.id, role: .coordinator)
        let vm = await TaskListViewModel(postingId: posting.id, taskService: taskService, appState: appState)
        await vm.loadTasks()

        await MainActor.run {
            #expect(vm.parentTasks.count == 1)
            #expect(vm.subtasks(for: parent.id).count == 6) // 4 template + 2 manual
            #expect(vm.tasks.count == 7) // parent + 6 subtasks
        }
    }

    @Test("TodoCenterViewModel sorts tasks by priority P0 first")
    func todoSortsByPriority() async throws {
        let dbManager = try DatabaseManager(inMemory: true)
        let dbPool = dbManager.dbPool
        let taskRepo = TaskRepository(dbPool: dbPool)
        let depRepo = DependencyRepository(dbPool: dbPool)
        let postingRepo = PostingRepository(dbPool: dbPool)
        let userRepo = UserRepository(dbPool: dbPool)
        let auditService = AuditService(dbPool: dbPool)
        let ps = PostingService(dbPool: dbPool, postingRepository: postingRepo,
                                taskRepository: taskRepo, userRepository: userRepo, auditService: auditService)
        let ts = TaskService(dbPool: dbPool, taskRepository: taskRepo,
                             dependencyRepository: depRepo, postingRepository: postingRepo, auditService: auditService,
                             userRepository: userRepo)

        let now = Date()
        let coord = User(id: UUID(), username: "coord", role: .coordinator, status: .active,
                         failedLoginCount: 0, lockedUntil: nil, biometricEnabled: false,
                         dndStartTime: nil, dndEndTime: nil, storageQuotaBytes: 2_147_483_648,
                         version: 1, createdAt: now, updatedAt: now)
        try await dbPool.write { db in try coord.insert(db) }

        let posting = try await ps.create(
            actorId: coord.id, title: "Priority Test", siteAddress: "Addr",
            dueDate: Date().addingTimeInterval(86400), budgetCents: 100,
            acceptanceMode: .open, watermarkEnabled: false
        )

        let tasks = try await ts.listTasks(postingId: posting.id, actorId: coord.id)
        let parent = tasks.first { $0.parentTaskId == nil }!
        _ = try await ts.createSubtask(actorId: coord.id, parentTaskId: parent.id,
                                        title: "Low Priority", priority: .p3, assignedTo: nil)
        _ = try await ts.createSubtask(actorId: coord.id, parentTaskId: parent.id,
                                        title: "Critical", priority: .p0, assignedTo: nil)

        let appState = AppState()
        appState.login(userId: coord.id, role: .coordinator)
        let vm = await TodoCenterViewModel(taskService: ts, postingService: ps, appState: appState)
        await vm.loadTodaysTasks()

        await MainActor.run {
            let groups = vm.tasksByPosting
            #expect(groups.count == 1)
            let taskGroup = groups[0].tasks
            // P0 should be before P3
            if taskGroup.count >= 2 {
                #expect(taskGroup[0].priority.rawValue <= taskGroup[1].priority.rawValue)
            }
        }
    }
}
