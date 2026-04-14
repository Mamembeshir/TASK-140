import Foundation
import GRDB

struct ForgeTask: Codable, FetchableRecord, PersistableRecord, Identifiable, Sendable {
    static let databaseTableName = "tasks"

    var id: UUID
    var postingId: UUID
    var parentTaskId: UUID?
    var title: String
    var taskDescription: String?
    var priority: Priority
    var status: TaskStatus
    var blockedComment: String?
    var assignedTo: UUID?
    var sortOrder: Int
    var version: Int
    var createdAt: Date
    var updatedAt: Date

    enum CodingKeys: String, CodingKey {
        case id, postingId, parentTaskId, title
        case taskDescription = "description"
        case priority, status, blockedComment, assignedTo
        case sortOrder, version, createdAt, updatedAt
    }

    enum Columns: String, ColumnExpression {
        case id, postingId, parentTaskId, title
        case description
        case priority, status, blockedComment, assignedTo
        case sortOrder, version, createdAt, updatedAt
    }
}
