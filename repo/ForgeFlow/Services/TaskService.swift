import Foundation
import GRDB

final class TaskService: Sendable {
    private let dbPool: DatabasePool
    private let taskRepository: TaskRepository
    private let dependencyRepository: DependencyRepository
    private let postingRepository: PostingRepository
    private let auditService: AuditService
    private let userRepository: UserRepository?
    let notificationService: NotificationService?
    private let postingServiceRef: PostingService?

    init(dbPool: DatabasePool, taskRepository: TaskRepository, dependencyRepository: DependencyRepository,
         postingRepository: PostingRepository, auditService: AuditService,
         notificationService: NotificationService? = nil,
         postingService: PostingService? = nil,
         userRepository: UserRepository? = nil) {
        self.dbPool = dbPool
        self.taskRepository = taskRepository
        self.dependencyRepository = dependencyRepository
        self.postingRepository = postingRepository
        self.auditService = auditService
        self.notificationService = notificationService
        self.postingServiceRef = postingService
        self.userRepository = userRepository
    }

    /// Checks that the actor may read or mutate the task.
    /// Allowed actors: assigned technician, admin, coordinator, posting creator,
    /// or any technician with an accepted assignment on the task's posting.
    private func requireTaskAccess(actorId: UUID, task: ForgeTask) async throws {
        // Assigned tech can always update their own tasks
        if task.assignedTo == actorId { return }
        // Check role: admin/coordinator can update any task
        if let userRepo = userRepository, let actor = try await userRepo.findById(actorId) {
            if actor.role == .admin || actor.role == .coordinator { return }
        }
        // Check posting ownership
        if let posting = try await postingRepository.findById(task.postingId) {
            if posting.createdBy == actorId { return }
        }
        // Accepted technicians can work on any task in their posting (including unassigned tasks)
        let hasAcceptedAssignment = try await dbPool.read { db in
            try Assignment
                .filter(Assignment.Columns.postingId == task.postingId)
                .filter(Assignment.Columns.technicianId == actorId)
                .filter(Assignment.Columns.status == AssignmentStatus.accepted.rawValue)
                .fetchCount(db) > 0
        }
        if hasAcceptedAssignment { return }
        throw TaskError.notAuthorized
    }

    // MARK: - Create Subtask

    func createSubtask(
        actorId: UUID,
        parentTaskId: UUID,
        title: String,
        priority: Priority,
        assignedTo: UUID?
    ) async throws -> ForgeTask {
        guard !title.trimmingCharacters(in: .whitespaces).isEmpty else {
            throw TaskError.titleRequired
        }

        // Authorization: must be posting creator, admin, or coordinator
        if let parent = try await taskRepository.findById(parentTaskId) {
            try await requireTaskAccess(actorId: actorId, task: parent)
        }

        return try await dbPool.write { [self] db in
            guard let parent = try taskRepository.findByIdInTransaction(db: db, parentTaskId) else {
                throw TaskError.taskNotFound
            }

            let siblings = try taskRepository.findSubtasksInTransaction(db: db, parentId: parentTaskId)
            let now = Date()

            let subtask = ForgeTask(
                id: UUID(),
                postingId: parent.postingId,
                parentTaskId: parentTaskId,
                title: title.trimmingCharacters(in: .whitespaces),
                taskDescription: nil,
                priority: priority,
                status: .notStarted,
                blockedComment: nil,
                assignedTo: assignedTo,
                sortOrder: siblings.count,
                version: 1,
                createdAt: now,
                updatedAt: now
            )

            try taskRepository.insertInTransaction(db: db, subtask)

            try auditService.record(
                db: db, actorId: actorId, action: "TASK_CREATED",
                entityType: "Task", entityId: subtask.id,
                afterData: "{\"title\":\"\(subtask.title)\",\"parentTaskId\":\"\(parentTaskId)\"}"
            )

            return subtask
        }
    }

    // MARK: - Update Status (State Machine PRD 9.3)

    func updateStatus(
        actorId: UUID,
        taskId: UUID,
        newStatus: TaskStatus,
        blockedComment: String? = nil
    ) async throws -> ForgeTask {
        // Authorization check
        if let task = try await taskRepository.findById(taskId) {
            try await requireTaskAccess(actorId: actorId, task: task)
        }
        let result: Result<ForgeTask, Error> = try await dbPool.write { [self] db in
            guard var task = try taskRepository.findByIdInTransaction(db: db, taskId) else {
                return .failure(TaskError.taskNotFound)
            }

            let oldStatus = task.status

            // Validate state transition
            guard Self.isValidTransition(from: oldStatus, to: newStatus) else {
                return .failure(TaskError.invalidStatusTransition(from: oldStatus, to: newStatus))
            }

            // TASK-04: BLOCKED requires comment >= 10 chars
            if newStatus == .blocked {
                guard let comment = blockedComment, !comment.trimmingCharacters(in: .whitespaces).isEmpty else {
                    return .failure(TaskError.blockedCommentRequired)
                }
                guard comment.count >= 10 else {
                    return .failure(TaskError.blockedCommentTooShort)
                }
                task.blockedComment = comment
            }

            // TASK-05: IN_PROGRESS checks dependencies
            if newStatus == .inProgress {
                let deps = try dependencyRepository.findByTaskInTransaction(db: db, taskId)
                for dep in deps {
                    if let depTask = try taskRepository.findByIdInTransaction(db: db, dep.dependsOnTaskId) {
                        if depTask.status != .done {
                            return .failure(TaskError.unmetDependencies)
                        }
                    }
                }
            }

            // TASK-06: DONE on parent requires all subtasks DONE
            if newStatus == .done {
                let subtasks = try taskRepository.findSubtasksInTransaction(db: db, parentId: taskId)
                if !subtasks.isEmpty {
                    let allDone = subtasks.allSatisfy { $0.status == .done }
                    if !allDone {
                        return .failure(TaskError.subtasksNotComplete)
                    }
                }
            }

            task.status = newStatus
            if newStatus != .blocked {
                task.blockedComment = nil
            }
            try taskRepository.updateWithLocking(db: db, task: &task)

            try auditService.record(
                db: db, actorId: actorId, action: "TASK_STATUS_CHANGED",
                entityType: "Task", entityId: taskId,
                beforeData: "{\"status\":\"\(oldStatus.rawValue)\"}",
                afterData: "{\"status\":\"\(newStatus.rawValue)\"}"
            )

            // TASK-07: Completing all tasks → posting auto-completes
            if newStatus == .done {
                try self.checkPostingAutoComplete(db: db, actorId: actorId, postingId: task.postingId)
            }

            return .success(task)
        }

        let task = try result.get()

        // MSG-07: Notify posting creator of task status changes and blocks
        if let ns = notificationService {
            let capturedTask = task
            Task {
                guard let posting = try? await postingRepository.findById(capturedTask.postingId) else { return }
                let eventType: NotificationEventType = capturedTask.status == .blocked
                    ? .taskBlocked : .taskStatusChanged
                let notifTitle = capturedTask.status == .blocked
                    ? "Task Blocked" : "Task Status Changed"
                let notifBody = "\"\(capturedTask.title)\" is now \(capturedTask.status.rawValue)."
                try? await ns.send(
                    recipientId: posting.createdBy,
                    eventType: eventType,
                    postingId: capturedTask.postingId,
                    title: notifTitle,
                    body: notifBody
                )
                // Also notify assigned technician if different from creator and task is blocked
                if capturedTask.status == .blocked,
                   let assignedTo = capturedTask.assignedTo,
                   assignedTo != posting.createdBy {
                    try? await ns.send(
                        recipientId: assignedTo,
                        eventType: .taskBlocked,
                        postingId: capturedTask.postingId,
                        title: "Task Blocked",
                        body: notifBody
                    )
                }
            }
        }

        return task
    }

    // MARK: - Add Dependency

    func addDependency(actorId: UUID, taskId: UUID, dependsOnTaskId: UUID) async throws -> Dependency {
        // Authorization: must have access to the task's posting
        if let task = try await taskRepository.findById(taskId) {
            try await requireTaskAccess(actorId: actorId, task: task)
        }
        return try await dbPool.write { [self] db in
            guard let task = try taskRepository.findByIdInTransaction(db: db, taskId) else {
                throw TaskError.taskNotFound
            }
            guard let depTask = try taskRepository.findByIdInTransaction(db: db, dependsOnTaskId) else {
                throw TaskError.taskNotFound
            }
            guard task.postingId == depTask.postingId else {
                throw TaskError.notAuthorized
            }

            // Check for circular dependency
            if try hasCircularDependency(db: db, from: dependsOnTaskId, to: taskId) {
                throw TaskError.unmetDependencies
            }

            let dep = Dependency(
                id: UUID(),
                taskId: taskId,
                dependsOnTaskId: dependsOnTaskId,
                type: .finishToStart
            )
            try dependencyRepository.insertInTransaction(db: db, dep)

            try auditService.record(
                db: db, actorId: actorId, action: "DEPENDENCY_ADDED",
                entityType: "Task", entityId: taskId,
                afterData: "{\"dependsOn\":\"\(dependsOnTaskId)\"}"
            )

            return dep
        }
    }

    // MARK: - Reorder Tasks

    func reorderTasks(actorId: UUID, postingId: UUID, taskIds: [UUID]) async throws {
        // Authorization: must be posting creator, admin, or coordinator
        if let posting = try await postingRepository.findById(postingId) {
            if let userRepo = userRepository, let actor = try await userRepo.findById(actorId) {
                guard actor.role == .admin || actor.role == .coordinator || posting.createdBy == actorId else {
                    throw TaskError.notAuthorized
                }
            }
        }
        try await dbPool.write { [self] db in
            try taskRepository.updateSortOrders(db: db, taskIds: taskIds)

            try auditService.record(
                db: db, actorId: actorId, action: "TASKS_REORDERED",
                entityType: "ServicePosting", entityId: postingId
            )
        }
    }

    // MARK: - Reads

    func getTask(id: UUID, actorId: UUID) async throws -> ForgeTask {
        guard let task = try await taskRepository.findById(id) else {
            throw TaskError.taskNotFound
        }
        try await requireTaskAccess(actorId: actorId, task: task)
        return task
    }

    func listTasks(postingId: UUID, actorId: UUID) async throws -> [ForgeTask] {
        guard let userRepo = userRepository else {
            throw TaskError.notAuthorized
        }
        guard let actor = try await userRepo.findById(actorId) else {
            throw TaskError.notAuthorized
        }
        if actor.role == .technician {
            // Technicians can only see tasks on postings they're assigned to
            let assigned = try await dbPool.read { db in
                try Assignment
                    .filter(Assignment.Columns.postingId == postingId)
                    .filter(Assignment.Columns.technicianId == actorId)
                    .filter(Assignment.Columns.status == AssignmentStatus.accepted.rawValue)
                    .fetchOne(db)
            }
            if let posting = try await postingRepository.findById(postingId) {
                if posting.createdBy != actorId && assigned == nil {
                    throw TaskError.notAuthorized
                }
            }
        }
        return try await taskRepository.findByPosting(postingId)
    }

    func listTasksForUser(userId: UUID, actorId: UUID) async throws -> [ForgeTask] {
        // Actor must be the user themselves or admin/coordinator
        if actorId != userId {
            if let userRepo = userRepository, let actor = try await userRepo.findById(actorId) {
                guard actor.role == .admin || actor.role == .coordinator else {
                    throw TaskError.notAuthorized
                }
            } else {
                throw TaskError.notAuthorized
            }
        }
        return try await taskRepository.findByAssignee(userId)
    }

    func getDependencies(taskId: UUID) async throws -> [Dependency] {
        try await dependencyRepository.findByTask(taskId)
    }

    func getDependents(taskId: UUID) async throws -> [Dependency] {
        try await dependencyRepository.findDependents(of: taskId)
    }

    // MARK: - State Machine Validation (PRD 9.3)

    static func isValidTransition(from: TaskStatus, to: TaskStatus) -> Bool {
        switch (from, to) {
        case (.notStarted, .inProgress): return true
        case (.notStarted, .blocked): return true
        case (.inProgress, .done): return true
        case (.inProgress, .blocked): return true
        case (.blocked, .inProgress): return true
        case (.blocked, .notStarted): return true
        default: return false
        }
    }

    // MARK: - Private

    private func checkPostingAutoComplete(db: Database, actorId: UUID, postingId: UUID) throws {
        let allTasks = try taskRepository.findByPostingInTransaction(db: db, postingId)
        let allDone = allTasks.allSatisfy { $0.status == .done }

        if allDone && !allTasks.isEmpty {
            guard var posting = try postingRepository.findByIdInTransaction(db: db, postingId) else { return }
            if posting.status == .inProgress {
                let title = posting.title
                posting.status = .completed
                try postingRepository.updateWithLocking(db: db, posting: &posting)

                try auditService.record(
                    db: db, actorId: actorId, action: "POSTING_AUTO_COMPLETED",
                    entityType: "ServicePosting", entityId: postingId,
                    afterData: "{\"reason\":\"All tasks completed\"}"
                )

                // MSG-07: Notify all participants
                postingServiceRef?.notifyCompleted(postingId: postingId, title: title)
            }
        }
    }

    private func hasCircularDependency(db: Database, from taskId: UUID, to targetId: UUID) throws -> Bool {
        var visited = Set<UUID>()
        var stack = [taskId]

        while let current = stack.popLast() {
            if current == targetId { return true }
            if visited.contains(current) { continue }
            visited.insert(current)

            let deps = try dependencyRepository.findByTaskInTransaction(db: db, current)
            for dep in deps {
                stack.append(dep.dependsOnTaskId)
            }
        }
        return false
    }
}
