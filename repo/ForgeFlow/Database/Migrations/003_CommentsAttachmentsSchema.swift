import Foundation
import GRDB

enum CommentsAttachmentsSchemaMigration {
    static func migrate(_ db: Database) throws {
        // MARK: - Comments
        try db.create(table: "comments") { t in
            t.primaryKey("id", .text).notNull()
            t.column("postingId", .text).notNull()
                .references("service_postings", onDelete: .cascade)
            t.column("taskId", .text)
                .references("tasks", onDelete: .cascade)
            t.column("authorId", .text).notNull()
                .references("users", onDelete: .restrict)
            t.column("body", .text).notNull()
            t.column("parentCommentId", .text)
                .references("comments", onDelete: .cascade)
            t.column("createdAt", .datetime).notNull()
        }

        try db.create(index: "idx_comments_postingId", on: "comments", columns: ["postingId"])
        try db.create(index: "idx_comments_taskId", on: "comments", columns: ["taskId"])
        try db.create(index: "idx_comments_parentCommentId", on: "comments", columns: ["parentCommentId"])

        // MARK: - Attachments
        try db.create(table: "attachments") { t in
            t.primaryKey("id", .text).notNull()
            t.column("commentId", .text)
                .references("comments", onDelete: .setNull)
            t.column("postingId", .text)
                .references("service_postings", onDelete: .cascade)
            t.column("taskId", .text)
                .references("tasks", onDelete: .cascade)
            t.column("fileName", .text).notNull()
            t.column("filePath", .text).notNull()
            t.column("fileSizeBytes", .integer).notNull()
            t.column("mimeType", .text).notNull()
            t.column("checksumSha256", .text).notNull()
            t.column("thumbnailPath", .text)
            t.column("isCompressed", .boolean).notNull().defaults(to: false)
            t.column("originalEncryptedPath", .text)
            t.column("uploadedBy", .text).notNull()
                .references("users", onDelete: .restrict)
            t.column("createdAt", .datetime).notNull()
        }

        try db.create(index: "idx_attachments_postingId", on: "attachments", columns: ["postingId"])
        try db.create(index: "idx_attachments_uploadedBy", on: "attachments", columns: ["uploadedBy"])
        try db.create(index: "idx_attachments_checksumSha256", on: "attachments", columns: ["checksumSha256"])
    }
}
