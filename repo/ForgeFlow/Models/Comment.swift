import Foundation
import GRDB

struct Comment: Codable, FetchableRecord, PersistableRecord, Identifiable, Sendable {
    static let databaseTableName = "comments"

    var id: UUID
    var postingId: UUID
    var taskId: UUID?
    var authorId: UUID
    var body: String
    var parentCommentId: UUID?
    var createdAt: Date

    enum Columns: String, ColumnExpression {
        case id, postingId, taskId, authorId, body, parentCommentId, createdAt
    }
}
