import Foundation
import GRDB

final class CommentRepository: Sendable {
    private let dbPool: DatabasePool

    init(dbPool: DatabasePool) {
        self.dbPool = dbPool
    }

    func findById(_ id: UUID) async throws -> Comment? {
        try await dbPool.read { db in try Comment.fetchOne(db, key: id) }
    }

    func findByPosting(_ postingId: UUID) async throws -> [Comment] {
        try await dbPool.read { db in
            try Comment
                .filter(Comment.Columns.postingId == postingId)
                .order(Comment.Columns.createdAt)
                .fetchAll(db)
        }
    }

    func findByTask(_ taskId: UUID) async throws -> [Comment] {
        try await dbPool.read { db in
            try Comment
                .filter(Comment.Columns.taskId == taskId)
                .order(Comment.Columns.createdAt)
                .fetchAll(db)
        }
    }

    func findReplies(to commentId: UUID) async throws -> [Comment] {
        try await dbPool.read { db in
            try Comment
                .filter(Comment.Columns.parentCommentId == commentId)
                .order(Comment.Columns.createdAt)
                .fetchAll(db)
        }
    }

    func insertInTransaction(db: Database, _ comment: Comment) throws {
        try comment.insert(db)
    }

    func insert(_ comment: Comment) async throws {
        try await dbPool.write { db in try comment.insert(db) }
    }
}
