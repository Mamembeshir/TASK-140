import Foundation
import GRDB

struct PluginField: Codable, FetchableRecord, MutablePersistableRecord, Identifiable, Sendable {
    static let databaseTableName = "plugin_fields"

    var id: UUID
    var pluginId: UUID
    var fieldName: String
    var fieldType: PluginFieldType
    var unit: String?
    var validationRules: String? // JSON
    var sortOrder: Int
    var createdAt: Date

    enum Columns: String, ColumnExpression {
        case id, pluginId, fieldName, fieldType, unit, validationRules, sortOrder, createdAt
    }
}
