import Foundation
import GRDB

final class AttachmentRepository: Sendable {
    private let dbPool: DatabasePool

    init(dbPool: DatabasePool) {
        self.dbPool = dbPool
    }

    func findById(_ id: UUID) async throws -> Attachment? {
        try await dbPool.read { db in try Attachment.fetchOne(db, key: id) }
    }

    func findByPosting(_ postingId: UUID) async throws -> [Attachment] {
        try await dbPool.read { db in
            try Attachment
                .filter(Attachment.Columns.postingId == postingId)
                .order(Attachment.Columns.createdAt.desc)
                .fetchAll(db)
        }
    }

    func findByComment(_ commentId: UUID) async throws -> [Attachment] {
        try await dbPool.read { db in
            try Attachment
                .filter(Attachment.Columns.commentId == commentId)
                .fetchAll(db)
        }
    }

    func findByChecksum(_ checksum: String, postingId: UUID) async throws -> Attachment? {
        try await dbPool.read { db in
            try Attachment
                .filter(Attachment.Columns.checksumSha256 == checksum)
                .filter(Attachment.Columns.postingId == postingId)
                .fetchOne(db)
        }
    }

    func totalSizeForUser(_ userId: UUID) async throws -> Int {
        try await dbPool.read { db in
            let sql = "SELECT COALESCE(SUM(fileSizeBytes), 0) FROM attachments WHERE uploadedBy = ?"
            return try Int.fetchOne(db, sql: sql, arguments: [userId.uuidString]) ?? 0
        }
    }

    func findOrphans(olderThan date: Date) async throws -> [Attachment] {
        try await dbPool.read { db in
            // Files with no comment, posting, or task reference older than threshold
            try Attachment
                .filter(Attachment.Columns.commentId == nil)
                .filter(Attachment.Columns.postingId == nil)
                .filter(Attachment.Columns.taskId == nil)
                .filter(Attachment.Columns.createdAt < date)
                .fetchAll(db)
        }
    }

    func insertInTransaction(db: Database, _ attachment: Attachment) throws {
        try attachment.insert(db)
    }

    func insert(_ attachment: Attachment) async throws {
        try await dbPool.write { db in try attachment.insert(db) }
    }

    func delete(_ id: UUID) async throws {
        try await dbPool.write { db in
            try db.execute(sql: "DELETE FROM attachments WHERE id = ?", arguments: [id.uuidString])
        }
    }
}
