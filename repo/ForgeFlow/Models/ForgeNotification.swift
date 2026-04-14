import Foundation
import GRDB

// Named ForgeNotification to avoid conflict with Foundation.Notification

struct ForgeNotification: Codable, FetchableRecord, MutablePersistableRecord, Identifiable, Sendable {
    static let databaseTableName = "notifications"

    var id: UUID
    var recipientId: UUID
    var eventType: NotificationEventType
    var postingId: UUID?
    var title: String
    var body: String
    var status: NotificationStatus
    var createdAt: Date
    var updatedAt: Date

    enum Columns: String, ColumnExpression {
        case id, recipientId, eventType, postingId, title, body, status, createdAt, updatedAt
    }
}
