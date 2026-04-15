import Foundation
import GRDB

final class CommentService: Sendable {
    private let dbPool: DatabasePool
    private let commentRepository: CommentRepository
    private let auditService: AuditService
    let notificationService: NotificationService?
    private let postingRepository: PostingRepository?
    private let assignmentRepository: AssignmentRepository?

    private let userRepository: UserRepository?

    init(dbPool: DatabasePool, commentRepository: CommentRepository, auditService: AuditService,
         notificationService: NotificationService? = nil,
         postingRepository: PostingRepository? = nil,
         assignmentRepository: AssignmentRepository? = nil,
         userRepository: UserRepository? = nil) {
        self.dbPool = dbPool
        self.commentRepository = commentRepository
        self.auditService = auditService
        self.notificationService = notificationService
        self.postingRepository = postingRepository
        self.assignmentRepository = assignmentRepository
        self.userRepository = userRepository
    }

    /// Verifies the actor is a participant on the posting (creator, assigned tech, or admin/coordinator).
    private func requireCommentAccess(actorId: UUID, postingId: UUID) async throws {
        // Admin/coordinator can always comment
        if let userRepo = userRepository, let actor = try await userRepo.findById(actorId) {
            if actor.role == .admin || actor.role == .coordinator { return }
        }
        // Posting creator can comment
        if let pr = postingRepository, let posting = try await pr.findById(postingId) {
            if posting.createdBy == actorId { return }
        }
        // Accepted technician can comment
        if let ar = assignmentRepository {
            let assignments = try await ar.findByPosting(postingId)
            if assignments.contains(where: { $0.technicianId == actorId && $0.status == .accepted }) { return }
        }
        throw PostingError.notAuthorized
    }

    func create(
        postingId: UUID,
        taskId: UUID? = nil,
        authorId: UUID,
        body: String,
        parentCommentId: UUID? = nil
    ) async throws -> Comment {
        guard !body.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw PostingError.titleRequired
        }

        // Authorization: actor must be a posting participant
        try await requireCommentAccess(actorId: authorId, postingId: postingId)

        let comment = Comment(
            id: UUID(),
            postingId: postingId,
            taskId: taskId,
            authorId: authorId,
            body: body,
            parentCommentId: parentCommentId,
            createdAt: Date()
        )

        try await dbPool.write { [self] db in
            try commentRepository.insertInTransaction(db: db, comment)

            try auditService.record(
                db: db, actorId: authorId, action: "COMMENT_ADDED",
                entityType: "Comment", entityId: comment.id,
                afterData: "{\"postingId\":\"\(postingId)\"}"
            )
        }

        // MSG-07: Notify posting participants of new comment (fire-and-forget)
        if let ns = notificationService, let pr = postingRepository, let ar = assignmentRepository {
            let pid = postingId
            Task {
                guard let posting = try? await pr.findById(pid) else { return }
                var recipientIds: Set<UUID> = [posting.createdBy]
                let assignments = (try? await ar.findByPosting(pid)) ?? []
                for a in assignments { recipientIds.insert(a.technicianId) }
                recipientIds.remove(authorId) // Don't notify the commenter
                for recipientId in recipientIds {
                    try? await ns.send(
                        recipientId: recipientId,
                        eventType: .commentAdded,
                        postingId: pid,
                        title: "New Comment",
                        body: "A new comment was added to your posting."
                    )
                }
            }
        }

        return comment
    }

    func listComments(postingId: UUID, actorId: UUID) async throws -> [Comment] {
        try await requireCommentAccess(actorId: actorId, postingId: postingId)
        return try await commentRepository.findByPosting(postingId)
    }

    func listComments(taskId: UUID, postingId: UUID, actorId: UUID) async throws -> [Comment] {
        try await requireCommentAccess(actorId: actorId, postingId: postingId)
        return try await commentRepository.findByTask(taskId)
    }

    func getReplies(commentId: UUID, actorId: UUID) async throws -> [Comment] {
        guard let parent = try await commentRepository.findById(commentId) else {
            throw PostingError.postingNotFound
        }
        try await requireCommentAccess(actorId: actorId, postingId: parent.postingId)
        return try await commentRepository.findReplies(to: commentId)
    }

    /// Groups comments into a threaded hierarchy.
    func threadedComments(postingId: UUID, actorId: UUID) async throws -> [ThreadedComment] {
        try await requireCommentAccess(actorId: actorId, postingId: postingId)
        let all = try await commentRepository.findByPosting(postingId)
        let roots = all.filter { $0.parentCommentId == nil }
        return roots.map { root in
            buildThread(root: root, allComments: all)
        }
    }

    private func buildThread(root: Comment, allComments: [Comment]) -> ThreadedComment {
        let replies = allComments
            .filter { $0.parentCommentId == root.id }
            .map { buildThread(root: $0, allComments: allComments) }
        return ThreadedComment(comment: root, replies: replies)
    }
}

struct ThreadedComment: Identifiable {
    let comment: Comment
    let replies: [ThreadedComment]
    var id: UUID { comment.id }
}
