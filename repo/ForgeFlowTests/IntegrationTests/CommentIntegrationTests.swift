import Foundation
import Testing
import GRDB
@testable import ForgeFlow

// MARK: - Comment Service Integration Tests
//
// Covers the full comment lifecycle: create, list, reply hierarchy, thread
// building, authorization matrix (admin / coordinator / accepted-tech /
// uninvited-tech), task-scoped comments, notification dispatch on creation,
// and audit entries.

@Suite("Comment Integration Tests", .serialized)
struct CommentIntegrationTests {

    // MARK: - Fixture factory

    private struct Services {
        let dbPool: DatabasePool
        let commentService: CommentService
        let postingService: PostingService
        let assignmentService: AssignmentService
        let notificationService: NotificationService
        let auditService: AuditService
    }

    private func makeServices() throws -> Services {
        let db = try DatabaseManager(inMemory: true)
        let pool = db.dbPool
        let auditSvc = AuditService(dbPool: pool)
        let userRepo = UserRepository(dbPool: pool)
        let postingRepo = PostingRepository(dbPool: pool)
        let assignmentRepo = AssignmentRepository(dbPool: pool)
        let taskRepo = TaskRepository(dbPool: pool)
        let commentRepo = CommentRepository(dbPool: pool)
        let notifRepo = NotificationRepository(dbPool: pool)
        let notifSvc = NotificationService(dbPool: pool, notificationRepository: notifRepo, userRepository: userRepo)
        let commentSvc = CommentService(
            dbPool: pool, commentRepository: commentRepo, auditService: auditSvc,
            notificationService: notifSvc,
            postingRepository: postingRepo,
            assignmentRepository: assignmentRepo,
            userRepository: userRepo
        )
        let postingSvc = PostingService(
            dbPool: pool, postingRepository: postingRepo,
            taskRepository: taskRepo, userRepository: userRepo, auditService: auditSvc
        )
        let assignmentSvc = AssignmentService(
            dbPool: pool, assignmentRepository: assignmentRepo,
            postingRepository: postingRepo, userRepository: userRepo, auditService: auditSvc
        )
        return Services(
            dbPool: pool, commentService: commentSvc,
            postingService: postingSvc, assignmentService: assignmentSvc,
            notificationService: notifSvc, auditService: auditSvc
        )
    }

    private func makeUser(_ pool: DatabasePool, username: String, role: Role) async throws -> User {
        let now = Date()
        let user = User(
            id: UUID(), username: username, role: role, status: .active,
            failedLoginCount: 0, lockedUntil: nil, biometricEnabled: false,
            dndStartTime: nil, dndEndTime: nil,
            storageQuotaBytes: 2_147_483_648,
            version: 1, createdAt: now, updatedAt: now
        )
        try await pool.write { db in try user.insert(db) }
        return user
    }

    private func makeOpenPosting(_ s: Services, creatorId: UUID) async throws -> ServicePosting {
        let posting = try await s.postingService.create(
            actorId: creatorId, title: "HVAC Repair", siteAddress: "100 Oak Ave",
            dueDate: Date().addingTimeInterval(86400), budgetCents: 75_000,
            acceptanceMode: .open, watermarkEnabled: false
        )
        return try await s.postingService.publish(actorId: creatorId, postingId: posting.id)
    }

    // MARK: - Basic create / list

    @Test("Admin can create a comment and it appears in list")
    func adminCreateAndList() async throws {
        let s = try makeServices()
        let admin = try await makeUser(s.dbPool, username: "admin", role: .admin)
        let posting = try await makeOpenPosting(s, creatorId: admin.id)

        let comment = try await s.commentService.create(
            postingId: posting.id, authorId: admin.id, body: "Looks good to me."
        )

        #expect(comment.body == "Looks good to me.")
        #expect(comment.postingId == posting.id)
        #expect(comment.parentCommentId == nil)
        #expect(comment.taskId == nil)

        let listed = try await s.commentService.listComments(postingId: posting.id, actorId: admin.id)
        #expect(listed.count == 1)
        #expect(listed[0].id == comment.id)
    }

    @Test("Coordinator can create a comment on their own posting")
    func coordinatorCreateOnOwnPosting() async throws {
        let s = try makeServices()
        let coord = try await makeUser(s.dbPool, username: "coord", role: .coordinator)
        let posting = try await makeOpenPosting(s, creatorId: coord.id)

        let comment = try await s.commentService.create(
            postingId: posting.id, authorId: coord.id, body: "Starting Monday."
        )
        #expect(comment.authorId == coord.id)
    }

    @Test("Accepted technician can create a comment")
    func acceptedTechCanComment() async throws {
        let s = try makeServices()
        let coord = try await makeUser(s.dbPool, username: "coord2", role: .coordinator)
        let tech = try await makeUser(s.dbPool, username: "tech2", role: .technician)
        let posting = try await makeOpenPosting(s, creatorId: coord.id)
        _ = try await s.assignmentService.accept(actorId: tech.id, postingId: posting.id, technicianId: tech.id)

        let comment = try await s.commentService.create(
            postingId: posting.id, authorId: tech.id, body: "On my way."
        )
        #expect(comment.authorId == tech.id)
    }

    @Test("Uninvited technician cannot comment — throws notAuthorized")
    func uninvitedTechCannotComment() async throws {
        let s = try makeServices()
        let coord = try await makeUser(s.dbPool, username: "coord3", role: .coordinator)
        let stranger = try await makeUser(s.dbPool, username: "stranger", role: .technician)
        let posting = try await makeOpenPosting(s, creatorId: coord.id)

        await #expect(throws: PostingError.self) {
            _ = try await s.commentService.create(
                postingId: posting.id, authorId: stranger.id, body: "Let me in."
            )
        }
    }

    @Test("Empty-body comment is rejected")
    func emptyBodyRejected() async throws {
        let s = try makeServices()
        let admin = try await makeUser(s.dbPool, username: "adm2", role: .admin)
        let posting = try await makeOpenPosting(s, creatorId: admin.id)

        await #expect(throws: PostingError.self) {
            _ = try await s.commentService.create(
                postingId: posting.id, authorId: admin.id, body: "   "
            )
        }
    }

    @Test("Whitespace-only body is also rejected")
    func whitespaceBodyRejected() async throws {
        let s = try makeServices()
        let admin = try await makeUser(s.dbPool, username: "adm3", role: .admin)
        let posting = try await makeOpenPosting(s, creatorId: admin.id)

        await #expect(throws: PostingError.self) {
            _ = try await s.commentService.create(
                postingId: posting.id, authorId: admin.id, body: "\t\n  "
            )
        }
    }

    // MARK: - Reply thread hierarchy

    @Test("Reply to a comment creates correct parentCommentId")
    func replyCreatesCorrectParent() async throws {
        let s = try makeServices()
        let admin = try await makeUser(s.dbPool, username: "adm4", role: .admin)
        let posting = try await makeOpenPosting(s, creatorId: admin.id)

        let root = try await s.commentService.create(
            postingId: posting.id, authorId: admin.id, body: "Root comment."
        )
        let reply = try await s.commentService.create(
            postingId: posting.id, authorId: admin.id,
            body: "Reply to root.", parentCommentId: root.id
        )

        #expect(reply.parentCommentId == root.id)
        #expect(reply.postingId == posting.id)
    }

    @Test("getReplies returns only direct children of a comment")
    func getRepliesReturnsDirectChildren() async throws {
        let s = try makeServices()
        let admin = try await makeUser(s.dbPool, username: "adm5", role: .admin)
        let posting = try await makeOpenPosting(s, creatorId: admin.id)

        let root = try await s.commentService.create(
            postingId: posting.id, authorId: admin.id, body: "Root."
        )
        let r1 = try await s.commentService.create(
            postingId: posting.id, authorId: admin.id, body: "Reply 1.", parentCommentId: root.id
        )
        let r2 = try await s.commentService.create(
            postingId: posting.id, authorId: admin.id, body: "Reply 2.", parentCommentId: root.id
        )
        // Deep reply (child of r1) — should NOT appear as a direct child of root
        _ = try await s.commentService.create(
            postingId: posting.id, authorId: admin.id, body: "Deep.", parentCommentId: r1.id
        )

        let replies = try await s.commentService.getReplies(commentId: root.id, actorId: admin.id)
        let replyIds = Set(replies.map { $0.id })
        #expect(replyIds.contains(r1.id))
        #expect(replyIds.contains(r2.id))
        #expect(replies.count == 2, "Only 2 direct replies, not the deep one")
    }

    @Test("threadedComments builds correct root/reply structure")
    func threadedCommentsStructure() async throws {
        let s = try makeServices()
        let admin = try await makeUser(s.dbPool, username: "adm6", role: .admin)
        let posting = try await makeOpenPosting(s, creatorId: admin.id)

        let root1 = try await s.commentService.create(
            postingId: posting.id, authorId: admin.id, body: "Root 1."
        )
        _ = try await s.commentService.create(
            postingId: posting.id, authorId: admin.id, body: "Root 2."
        )
        _ = try await s.commentService.create(
            postingId: posting.id, authorId: admin.id, body: "Reply to R1.", parentCommentId: root1.id
        )

        let threaded = try await s.commentService.threadedComments(
            postingId: posting.id, actorId: admin.id
        )

        #expect(threaded.count == 2, "Two root-level threads")
        let root1Thread = threaded.first { $0.comment.id == root1.id }
        #expect(root1Thread?.replies.count == 1)
        let root2Thread = threaded.first { $0.comment.id != root1.id }
        #expect(root2Thread?.replies.count == 0)
    }

    // MARK: - Task-scoped comments

    @Test("Comment on a specific task is retrievable via listComments(taskId:)")
    func taskScopedComment() async throws {
        let s = try makeServices()
        let admin = try await makeUser(s.dbPool, username: "adm7", role: .admin)
        let posting = try await makeOpenPosting(s, creatorId: admin.id)

        // Get the auto-generated root task
        let taskRepo = TaskRepository(dbPool: s.dbPool)
        let tasks = try await taskRepo.findByPosting(posting.id)
        let task = tasks.first { $0.parentTaskId == nil }!

        let taskComment = try await s.commentService.create(
            postingId: posting.id, taskId: task.id,
            authorId: admin.id, body: "Task-level note."
        )
        let postingComment = try await s.commentService.create(
            postingId: posting.id, taskId: nil,
            authorId: admin.id, body: "Posting-level note."
        )

        let taskComments = try await s.commentService.listComments(
            taskId: task.id, postingId: posting.id, actorId: admin.id
        )
        #expect(taskComments.count == 1)
        #expect(taskComments[0].id == taskComment.id)

        let allComments = try await s.commentService.listComments(
            postingId: posting.id, actorId: admin.id
        )
        #expect(allComments.count == 2)
        _ = postingComment // suppress unused warning
    }

    // MARK: - Multiple participants see each other's comments

    @Test("Coordinator and accepted technician both see the same comment list")
    func sharedVisibility() async throws {
        let s = try makeServices()
        let coord = try await makeUser(s.dbPool, username: "coord4", role: .coordinator)
        let tech = try await makeUser(s.dbPool, username: "tech4", role: .technician)
        let posting = try await makeOpenPosting(s, creatorId: coord.id)
        _ = try await s.assignmentService.accept(actorId: tech.id, postingId: posting.id, technicianId: tech.id)

        _ = try await s.commentService.create(postingId: posting.id, authorId: coord.id, body: "Hello.")
        _ = try await s.commentService.create(postingId: posting.id, authorId: tech.id, body: "Hi back.")

        let coordView = try await s.commentService.listComments(postingId: posting.id, actorId: coord.id)
        let techView  = try await s.commentService.listComments(postingId: posting.id, actorId: tech.id)

        #expect(coordView.count == 2)
        #expect(techView.count == 2)
        #expect(Set(coordView.map { $0.id }) == Set(techView.map { $0.id }))
    }

    // MARK: - Audit entries

    @Test("COMMENT_ADDED audit entry is written for every comment")
    func auditEntryWritten() async throws {
        let s = try makeServices()
        let admin = try await makeUser(s.dbPool, username: "adm8", role: .admin)
        let posting = try await makeOpenPosting(s, creatorId: admin.id)

        let c1 = try await s.commentService.create(postingId: posting.id, authorId: admin.id, body: "One.")
        let c2 = try await s.commentService.create(postingId: posting.id, authorId: admin.id, body: "Two.")

        let entries1 = try await s.auditService.entries(for: "Comment", entityId: c1.id)
        let entries2 = try await s.auditService.entries(for: "Comment", entityId: c2.id)

        #expect(entries1.contains(where: { $0.action == "COMMENT_ADDED" }))
        #expect(entries2.contains(where: { $0.action == "COMMENT_ADDED" }))
    }

    // MARK: - Notification on comment

    @Test("Posting creator receives a notification when a technician comments")
    func notificationSentToPostingCreator() async throws {
        let s = try makeServices()
        let coord = try await makeUser(s.dbPool, username: "coord5", role: .coordinator)
        let tech = try await makeUser(s.dbPool, username: "tech5", role: .technician)
        let posting = try await makeOpenPosting(s, creatorId: coord.id)
        _ = try await s.assignmentService.accept(actorId: tech.id, postingId: posting.id, technicianId: tech.id)

        _ = try await s.commentService.create(
            postingId: posting.id, authorId: tech.id, body: "Job done."
        )

        // Give the fire-and-forget Task a moment to complete
        try await Task.sleep(nanoseconds: 200_000_000)

        let coordNotifs = try await s.notificationService.listNotifications(
            userId: coord.id, actorId: coord.id
        )
        #expect(coordNotifs.contains(where: { $0.eventType == .commentAdded }))
    }

    @Test("Commenter does NOT receive a notification for their own comment")
    func commenterNotNotifiedOfOwnComment() async throws {
        let s = try makeServices()
        let admin = try await makeUser(s.dbPool, username: "adm9", role: .admin)
        let posting = try await makeOpenPosting(s, creatorId: admin.id)

        _ = try await s.commentService.create(
            postingId: posting.id, authorId: admin.id, body: "Self-comment."
        )

        try await Task.sleep(nanoseconds: 200_000_000)

        let adminNotifs = try await s.notificationService.listNotifications(
            userId: admin.id, actorId: admin.id
        )
        let commentNotifs = adminNotifs.filter { $0.eventType == .commentAdded }
        #expect(commentNotifs.isEmpty, "Author should not receive their own comment notification")
    }
}
