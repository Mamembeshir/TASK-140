import Foundation
import GRDB

struct PluginDefinition: Codable, FetchableRecord, MutablePersistableRecord, Identifiable, Sendable {
    static let databaseTableName = "plugin_definitions"

    var id: UUID
    var name: String
    var description: String
    var category: String
    var status: PluginStatus
    var createdBy: UUID
    var version: Int
    var createdAt: Date
    var updatedAt: Date

    enum Columns: String, ColumnExpression {
        case id, name, description, category, status, createdBy, version, createdAt, updatedAt
    }
}
