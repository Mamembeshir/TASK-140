import Foundation
import GRDB

struct AuditEntry: Codable, FetchableRecord, PersistableRecord, Identifiable, Sendable {
    static let databaseTableName = "audit_entries"

    var id: UUID
    var actorId: UUID
    var action: String
    var entityType: String
    var entityId: UUID
    var beforeData: String?
    var afterData: String?
    var timestamp: Date

    enum Columns: String, ColumnExpression {
        case id, actorId, action, entityType, entityId, beforeData, afterData, timestamp
    }
}
