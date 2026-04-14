import Foundation
import GRDB

final class PostingService: Sendable {
    private let dbPool: DatabasePool
    private let postingRepository: PostingRepository
    private let taskRepository: TaskRepository
    private let userRepository: UserRepository
    private let auditService: AuditService
    let notificationService: NotificationService?
    private let assignmentRepository: AssignmentRepository?
    private let pluginService: PluginService?

    init(dbPool: DatabasePool, postingRepository: PostingRepository, taskRepository: TaskRepository,
         userRepository: UserRepository, auditService: AuditService,
         notificationService: NotificationService? = nil,
         assignmentRepository: AssignmentRepository? = nil,
         pluginService: PluginService? = nil) {
        self.dbPool = dbPool
        self.postingRepository = postingRepository
        self.taskRepository = taskRepository
        self.userRepository = userRepository
        self.auditService = auditService
        self.notificationService = notificationService
        self.assignmentRepository = assignmentRepository
        self.pluginService = pluginService
    }

    // MARK: - Authorization

    /// Checks that the actor is admin, coordinator, or the posting creator.
    private func requirePostingAccess(actorId: UUID, posting: ServicePosting) async throws {
        // Owner always has access
        if posting.createdBy == actorId { return }
        // Check role
        if let actor = try await userRepository.findById(actorId) {
            guard actor.role == .admin || actor.role == .coordinator else {
                throw PostingError.notAuthorized
            }
        }
    }

    /// Checks that the actor is admin or coordinator (can create/publish postings).
    private func requireCreateAccess(actorId: UUID) async throws {
        // Look up actor's role — technicians cannot create postings
        if let actor = try await userRepository.findById(actorId) {
            guard actor.role == .admin || actor.role == .coordinator else {
                throw PostingError.notAuthorized
            }
        }
        // If user not found in read path, let the write transaction's FK constraint catch it
    }

    // MARK: - Validation

    static func validateTitle(_ title: String) throws {
        guard !title.trimmingCharacters(in: .whitespaces).isEmpty else {
            throw PostingError.titleRequired
        }
    }

    static func validateSiteAddress(_ address: String) throws {
        guard !address.trimmingCharacters(in: .whitespaces).isEmpty else {
            throw PostingError.siteAddressRequired
        }
    }

    static func validateDueDate(_ date: Date) throws {
        guard date > Date() else {
            throw PostingError.dueDateMustBeFuture
        }
    }

    static func validateBudget(_ cents: Int) throws {
        guard cents > 0 else {
            throw PostingError.budgetMustBePositive
        }
    }

    // MARK: - Create (DRAFT + auto-generate root task)

    func create(
        actorId: UUID,
        title: String,
        siteAddress: String,
        dueDate: Date,
        budgetCents: Int,
        acceptanceMode: AcceptanceMode,
        watermarkEnabled: Bool
    ) async throws -> ServicePosting {
        try await requireCreateAccess(actorId: actorId)
        try Self.validateTitle(title)
        try Self.validateSiteAddress(siteAddress)
        try Self.validateDueDate(dueDate)
        try Self.validateBudget(budgetCents)

        return try await dbPool.write { [self] db in
            let now = Date()

            var posting = ServicePosting(
                id: UUID(),
                title: title,
                siteAddress: siteAddress,
                dueDate: dueDate,
                budgetCapCents: budgetCents,
                status: .draft,
                acceptanceMode: acceptanceMode,
                createdBy: actorId,
                watermarkEnabled: watermarkEnabled,
                version: 1,
                createdAt: now,
                updatedAt: now
            )

            try postingRepository.insertInTransaction(db: db, posting)

            // TASK-01: Auto-generate task breakdown with subtasks + dependencies
            let rootTaskId = UUID()
            let rootTask = ForgeTask(
                id: rootTaskId,
                postingId: posting.id,
                parentTaskId: nil,
                title: title,
                taskDescription: nil,
                priority: .p2,
                status: .notStarted,
                blockedComment: nil,
                assignedTo: nil,
                sortOrder: 0,
                version: 1,
                createdAt: now,
                updatedAt: now
            )
            try taskRepository.insertInTransaction(db: db, rootTask)

            // Auto-generate standard subtask template
            let subtaskTemplates: [(String, Priority, Int)] = [
                ("Site Assessment", .p0, 1),
                ("Execute Work", .p1, 2),
                ("Quality Check", .p2, 3),
                ("Documentation & Closeout", .p3, 4),
            ]

            var previousSubtaskId: UUID?
            for (subtaskTitle, priority, order) in subtaskTemplates {
                let subtaskId = UUID()
                let subtask = ForgeTask(
                    id: subtaskId,
                    postingId: posting.id,
                    parentTaskId: rootTaskId,
                    title: subtaskTitle,
                    taskDescription: nil,
                    priority: priority,
                    status: .notStarted,
                    blockedComment: nil,
                    assignedTo: nil,
                    sortOrder: order,
                    version: 1,
                    createdAt: now,
                    updatedAt: now
                )
                try taskRepository.insertInTransaction(db: db, subtask)

                // Chain dependencies: each subtask depends on the previous (finish-to-start)
                if let prevId = previousSubtaskId {
                    let dep = Dependency(
                        id: UUID(),
                        taskId: subtaskId,
                        dependsOnTaskId: prevId,
                        type: .finishToStart
                    )
                    try dep.insert(db)
                }
                previousSubtaskId = subtaskId
            }

            try auditService.record(
                db: db,
                actorId: actorId,
                action: "POSTING_CREATED",
                entityType: "ServicePosting",
                entityId: posting.id,
                afterData: "{\"title\":\"\(title)\",\"status\":\"DRAFT\"}"
            )

            return posting
        }
    }

    // MARK: - Publish (DRAFT → OPEN)

    func publish(actorId: UUID, postingId: UUID) async throws -> ServicePosting {
        // Authorization: creator or admin
        if let posting = try await postingRepository.findById(postingId) {
            try await requirePostingAccess(actorId: actorId, posting: posting)

            // Validate against active plugin rules before publishing
            if let ps = pluginService {
                let pluginErrors = try await ps.validatePostingAgainstActivePlugins(posting)
                if !pluginErrors.isEmpty {
                    throw PostingError.invalidStatusTransition(from: posting.status, to: .open)
                }
            }
        }
        return try await dbPool.write { [self] db in
            guard var posting = try postingRepository.findByIdInTransaction(db: db, postingId) else {
                throw PostingError.postingNotFound
            }

            guard posting.status == .draft else {
                throw PostingError.invalidStatusTransition(from: posting.status, to: .open)
            }

            posting.status = .open
            try postingRepository.updateWithLocking(db: db, posting: &posting)

            try auditService.record(
                db: db,
                actorId: actorId,
                action: "POSTING_PUBLISHED",
                entityType: "ServicePosting",
                entityId: postingId,
                beforeData: "{\"status\":\"DRAFT\"}",
                afterData: "{\"status\":\"OPEN\"}"
            )

            return posting
        }
    }

    // MARK: - Cancel (any active → CANCELLED)

    func cancel(actorId: UUID, postingId: UUID) async throws -> ServicePosting {
        // Authorization: creator or admin
        if let existing = try await postingRepository.findById(postingId) {
            try await requirePostingAccess(actorId: actorId, posting: existing)
        }
        let posting = try await dbPool.write { [self] db -> ServicePosting in
            guard var posting = try postingRepository.findByIdInTransaction(db: db, postingId) else {
                throw PostingError.postingNotFound
            }

            guard posting.status != .cancelled && posting.status != .completed else {
                throw PostingError.invalidStatusTransition(from: posting.status, to: .cancelled)
            }

            let beforeStatus = posting.status
            posting.status = .cancelled
            try postingRepository.updateWithLocking(db: db, posting: &posting)

            try auditService.record(
                db: db,
                actorId: actorId,
                action: "POSTING_CANCELLED",
                entityType: "ServicePosting",
                entityId: postingId,
                beforeData: "{\"status\":\"\(beforeStatus.rawValue)\"}",
                afterData: "{\"status\":\"CANCELLED\"}"
            )

            return posting
        }

        // MSG-07: Notify all assigned technicians of cancellation
        notifyParticipants(
            postingId: postingId,
            eventType: .postingCancelled,
            title: "Posting Cancelled",
            body: "\"\(posting.title)\" has been cancelled."
        )

        return posting
    }

    // MARK: - Notify helpers (fire-and-forget, post-transaction)

    private func notifyParticipants(
        postingId: UUID,
        eventType: NotificationEventType,
        title: String,
        body: String
    ) {
        guard let ns = notificationService, let ar = assignmentRepository else { return }
        Task {
            guard let posting = try? await postingRepository.findById(postingId) else { return }
            var recipientIds: Set<UUID> = [posting.createdBy]
            let assignments = (try? await ar.findByPosting(postingId)) ?? []
            for a in assignments { recipientIds.insert(a.technicianId) }
            for recipientId in recipientIds {
                try? await ns.send(
                    recipientId: recipientId,
                    eventType: eventType,
                    postingId: postingId,
                    title: title,
                    body: body
                )
            }
        }
    }

    // MARK: - Reads

    func getPosting(id: UUID, actorId: UUID) async throws -> ServicePosting {
        guard let posting = try await postingRepository.findById(id) else {
            throw PostingError.postingNotFound
        }
        let visible = try await listPostings(actorId: actorId)
        guard visible.contains(where: { $0.id == posting.id }) else {
            throw PostingError.notAuthorized
        }
        return posting
    }

    /// Internal read without auth check — for service-to-service calls within transactions.
    func getPostingInternal(id: UUID) async throws -> ServicePosting {
        guard let posting = try await postingRepository.findById(id) else {
            throw PostingError.postingNotFound
        }
        return posting
    }

    /// Lists postings visible to the actor, deriving role from DB — not caller-supplied.
    func listPostings(actorId: UUID) async throws -> [ServicePosting] {
        guard let actor = try await userRepository.findById(actorId) else {
            return []
        }
        switch actor.role {
        case .admin:
            return try await postingRepository.findAll()
        case .coordinator:
            return try await postingRepository.findByCreator(actorId)
        case .technician:
            return try await postingRepository.findForTechnician(actorId)
        }
    }

    /// Backward-compatible overload — derives role from DB, ignores caller-supplied role.
    func listPostings(role: Role, userId: UUID) async throws -> [ServicePosting] {
        try await listPostings(actorId: userId)
    }

    func listTasks(postingId: UUID, actorId: UUID) async throws -> [ForgeTask] {
        guard let actor = try await userRepository.findById(actorId) else {
            throw PostingError.notAuthorized
        }
        if actor.role == .technician {
            guard let repo = assignmentRepository else {
                throw PostingError.notAuthorized
            }
            let assigned = try await dbPool.read { db in
                try Assignment
                    .filter(Assignment.Columns.postingId == postingId)
                    .filter(Assignment.Columns.technicianId == actorId)
                    .fetchOne(db)
            }
            if let posting = try await postingRepository.findById(postingId) {
                if posting.createdBy != actorId && assigned == nil {
                    throw PostingError.notAuthorized
                }
            }
        }
        return try await taskRepository.findByPosting(postingId)
    }

    /// Called by TaskService after auto-complete triggers. MSG-07: posting_completed.
    func notifyCompleted(postingId: UUID, title: String) {
        notifyParticipants(
            postingId: postingId,
            eventType: .postingCompleted,
            title: "Posting Completed",
            body: "\"\(title)\" has been completed."
        )
    }
}
