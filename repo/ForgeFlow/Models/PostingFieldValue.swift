import Foundation
import GRDB

/// Stores per-posting custom field values set by plugins.
struct PostingFieldValue: Codable, FetchableRecord, MutablePersistableRecord, Identifiable, Sendable {
    static let databaseTableName = "posting_field_values"

    var id: UUID
    var postingId: UUID
    var pluginFieldId: UUID
    var value: String // stored as string; interpreted per field type
    var createdAt: Date
    var updatedAt: Date

    enum Columns: String, ColumnExpression {
        case id, postingId, pluginFieldId, value, createdAt, updatedAt
    }
}
