import Foundation
import GRDB

struct Assignment: Codable, FetchableRecord, PersistableRecord, Identifiable, Sendable {
    static let databaseTableName = "assignments"

    var id: UUID
    var postingId: UUID
    var technicianId: UUID
    var status: AssignmentStatus
    var acceptedAt: Date?
    var auditNote: String?
    var version: Int
    var createdAt: Date
    var updatedAt: Date

    enum Columns: String, ColumnExpression {
        case id, postingId, technicianId, status
        case acceptedAt, auditNote
        case version, createdAt, updatedAt
    }
}
