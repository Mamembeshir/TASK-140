import Foundation
import GRDB

final class AssignmentService: Sendable {
    private let dbPool: DatabasePool
    private let assignmentRepository: AssignmentRepository
    private let postingRepository: PostingRepository
    private let userRepository: UserRepository
    private let auditService: AuditService
    let notificationService: NotificationService?

    init(dbPool: DatabasePool, assignmentRepository: AssignmentRepository,
         postingRepository: PostingRepository, userRepository: UserRepository,
         auditService: AuditService, notificationService: NotificationService? = nil) {
        self.dbPool = dbPool
        self.assignmentRepository = assignmentRepository
        self.postingRepository = postingRepository
        self.userRepository = userRepository
        self.auditService = auditService
        self.notificationService = notificationService
    }

    // MARK: - Authorization

    /// Validates that the actor is the posting creator, admin, or coordinator.
    private func requireInviteAccess(actorId: UUID, postingId: UUID) async throws {
        guard let posting = try await postingRepository.findById(postingId) else {
            throw PostingError.postingNotFound
        }
        if posting.createdBy == actorId { return }
        if let actor = try await userRepository.findById(actorId) {
            if actor.role == .admin || actor.role == .coordinator { return }
        }
        throw AssignmentError.notAuthorized
    }

    /// Validates that actorId matches technicianId (self-service) or actor is admin/coordinator.
    private func requireSelfOrAdmin(actorId: UUID, technicianId: UUID) async throws {
        if actorId == technicianId { return }
        if let actor = try await userRepository.findById(actorId) {
            if actor.role == .admin || actor.role == .coordinator { return }
        }
        throw AssignmentError.notAuthorized
    }

    // MARK: - Invite (INVITE_ONLY postings)

    func invite(actorId: UUID, postingId: UUID, technicianIds: [UUID]) async throws -> [Assignment] {
        try await requireInviteAccess(actorId: actorId, postingId: postingId)
        let assignments: [Assignment] = try await dbPool.write { [self] db in
            guard let posting = try postingRepository.findByIdInTransaction(db: db, postingId) else {
                throw PostingError.postingNotFound
            }
            guard posting.status == .open else {
                throw AssignmentError.postingNotOpen
            }
            guard posting.acceptanceMode == .inviteOnly else {
                throw AssignmentError.notAuthorized
            }

            let now = Date()
            var result: [Assignment] = []

            for techId in technicianIds {
                let assignment = Assignment(
                    id: UUID(),
                    postingId: postingId,
                    technicianId: techId,
                    status: .invited,
                    acceptedAt: nil,
                    auditNote: nil,
                    version: 1,
                    createdAt: now,
                    updatedAt: now
                )
                // Idempotent: INSERT OR IGNORE for UNIQUE(postingId, technicianId)
                try assignmentRepository.insertOrIgnoreInTransaction(db: db, assignment)

                if db.changesCount > 0 {
                    result.append(assignment)
                    try auditService.record(
                        db: db,
                        actorId: actorId,
                        action: "ASSIGNMENT_INVITED",
                        entityType: "Assignment",
                        entityId: assignment.id,
                        afterData: "{\"postingId\":\"\(postingId)\",\"technicianId\":\"\(techId)\"}"
                    )
                }
            }

            return result
        }

        // MSG-07: Notify invited technicians (fire-and-forget, outside transaction)
        if let ns = notificationService, !assignments.isEmpty {
            let invitedIds = assignments.map { $0.technicianId }
            let pid = postingId
            Task {
                for techId in invitedIds {
                    try? await ns.send(
                        recipientId: techId,
                        eventType: .assignmentInvited,
                        postingId: pid,
                        title: "New Service Invitation",
                        body: "You have been invited to a service posting."
                    )
                }
            }
        }

        return assignments
    }

    // MARK: - Accept (first-accepted-wins for OPEN, idempotent)

    func accept(actorId: UUID, postingId: UUID, technicianId: UUID) async throws -> Assignment {
        // Actor identity binding: actor must be the technician or an admin/coordinator
        try await requireSelfOrAdmin(actorId: actorId, technicianId: technicianId)
        let result: Result<Assignment, Error> = try await dbPool.write { [self] db in
            guard var posting = try postingRepository.findByIdInTransaction(db: db, postingId) else {
                return .failure(PostingError.postingNotFound)
            }

            guard posting.status == .open || posting.status == .inProgress else {
                return .failure(AssignmentError.postingNotOpen)
            }

            // Check first-accepted-wins for OPEN postings
            if posting.acceptanceMode == .open {
                if let existing = try assignmentRepository.findAcceptedForPostingInTransaction(db: db, postingId: postingId) {
                    // Idempotent: same technician re-tapping accept after winning → return their existing assignment
                    if existing.technicianId == technicianId {
                        return .success(existing)
                    }

                    // Already accepted by someone else — look up their name
                    let winnerName: String
                    if let winner = try userRepository.findByIdInTransaction(db: db, existing.technicianId) {
                        winnerName = winner.username
                    } else {
                        winnerName = "another technician"
                    }

                    try auditService.record(
                        db: db,
                        actorId: technicianId,
                        action: "ASSIGNMENT_ACCEPT_BLOCKED",
                        entityType: "ServicePosting",
                        entityId: postingId,
                        afterData: "{\"blockedBy\":\"\(winnerName)\",\"acceptedAt\":\"\(existing.acceptedAt?.description ?? "")\"}"
                    )

                    // Persist a visible audit note on the blocked technician's assignment record
                    let blockedDate = existing.acceptedAt.map {
                        DateFormatters.display.string(from: $0)
                    } ?? "unknown time"
                    let auditNote = "Blocked: \(winnerName) was first to accept on \(blockedDate)"
                    let now = Date()
                    let blockedAssignment = Assignment(
                        id: UUID(),
                        postingId: postingId,
                        technicianId: technicianId,
                        status: .declined,
                        acceptedAt: nil,
                        auditNote: auditNote,
                        version: 1,
                        createdAt: now,
                        updatedAt: now
                    )
                    try assignmentRepository.insertOrIgnoreInTransaction(db: db, blockedAssignment)

                    return .failure(AssignmentError.alreadyAssigned(
                        name: winnerName,
                        at: existing.acceptedAt ?? existing.createdAt
                    ))
                }

                // OPEN: create new assignment directly as ACCEPTED.
                // Race safety: GRDB DatabasePool serializes all writes through
                // a single writer connection. The check above + insert below
                // execute atomically within this dbPool.write block.
                let now = Date()
                let assignment = Assignment(
                    id: UUID(),
                    postingId: postingId,
                    technicianId: technicianId,
                    status: .accepted,
                    acceptedAt: now,
                    auditNote: nil,
                    version: 1,
                    createdAt: now,
                    updatedAt: now
                )
                try assignmentRepository.insertOrIgnoreInTransaction(db: db, assignment)

                // Transition posting to IN_PROGRESS if still OPEN
                if posting.status == .open {
                    posting.status = .inProgress
                    try postingRepository.updateWithLocking(db: db, posting: &posting)
                }

                try auditService.record(
                    db: db,
                    actorId: technicianId,
                    action: "ASSIGNMENT_ACCEPTED",
                    entityType: "Assignment",
                    entityId: assignment.id,
                    afterData: "{\"postingId\":\"\(postingId)\",\"mode\":\"OPEN\"}"
                )

                return .success(assignment)
            }

            // INVITE_ONLY: find existing assignment
            guard var assignment = try assignmentRepository.findByPostingAndTechnicianInTransaction(
                db: db, postingId: postingId, technicianId: technicianId
            ) else {
                return .failure(AssignmentError.notInvited)
            }

            // Idempotent: if already accepted, return it
            if assignment.status == .accepted {
                return .success(assignment)
            }

            guard assignment.status == .invited else {
                return .failure(AssignmentError.invalidStatusTransition(
                    from: assignment.status, to: .accepted
                ))
            }

            assignment.status = .accepted
            assignment.acceptedAt = Date()
            try assignmentRepository.updateWithLocking(db: db, assignment: &assignment)

            // Transition posting to IN_PROGRESS if still OPEN
            if posting.status == .open {
                posting.status = .inProgress
                try postingRepository.updateWithLocking(db: db, posting: &posting)
            }

            try auditService.record(
                db: db,
                actorId: technicianId,
                action: "ASSIGNMENT_ACCEPTED",
                entityType: "Assignment",
                entityId: assignment.id,
                afterData: "{\"postingId\":\"\(postingId)\",\"mode\":\"INVITE_ONLY\"}"
            )

            return .success(assignment)
        }

        let assignment = try result.get()

        // MSG-07: Notify coordinator that assignment was accepted
        if let ns = notificationService {
            let pid = postingId
            Task {
                if let posting = try? await postingRepository.findById(pid) {
                    try? await ns.send(
                        recipientId: posting.createdBy,
                        eventType: .assignmentAccepted,
                        postingId: pid,
                        title: "Assignment Accepted",
                        body: "A technician has accepted your service posting."
                    )
                }
            }
        }

        return assignment
    }

    // MARK: - Decline

    func decline(actorId: UUID, postingId: UUID, technicianId: UUID) async throws -> Assignment {
        try await requireSelfOrAdmin(actorId: actorId, technicianId: technicianId)
        return try await dbPool.write { [self] db in
            guard var assignment = try assignmentRepository.findByPostingAndTechnicianInTransaction(
                db: db, postingId: postingId, technicianId: technicianId
            ) else {
                throw AssignmentError.assignmentNotFound
            }

            guard assignment.status == .invited else {
                throw AssignmentError.invalidStatusTransition(
                    from: assignment.status, to: .declined
                )
            }

            assignment.status = .declined
            try assignmentRepository.updateWithLocking(db: db, assignment: &assignment)

            try auditService.record(
                db: db,
                actorId: technicianId,
                action: "ASSIGNMENT_DECLINED",
                entityType: "Assignment",
                entityId: assignment.id,
                afterData: "{\"postingId\":\"\(postingId)\"}"
            )

            return assignment
        }
    }

    // MARK: - Reads

    func listAssignments(postingId: UUID, actorId: UUID) async throws -> [Assignment] {
        guard let actor = try await userRepository.findById(actorId) else {
            throw AssignmentError.notAuthorized
        }
        if actor.role == .technician {
            let assignments = try await assignmentRepository.findByPosting(postingId)
            guard assignments.contains(where: {
                $0.technicianId == actorId && ($0.status == .accepted || $0.status == .invited)
            }) else {
                throw AssignmentError.notAuthorized
            }
        }
        return try await assignmentRepository.findByPosting(postingId)
    }

    func listForTechnician(technicianId: UUID, actorId: UUID) async throws -> [Assignment] {
        // Actor must be the technician themselves or admin/coordinator — no bypass path allowed
        if actorId != technicianId {
            guard let actor = try await userRepository.findById(actorId),
                  actor.role == .admin || actor.role == .coordinator else {
                throw AssignmentError.notAuthorized
            }
        }
        return try await assignmentRepository.findByTechnician(technicianId)
    }
}
