import Foundation
import GRDB

struct ConnectorDefinition: Codable, FetchableRecord, MutablePersistableRecord, Identifiable, Sendable {
    static let databaseTableName = "connector_definitions"

    var id: UUID
    var name: String
    var connectorType: String
    var isEnabled: Bool
    var configJson: String?
    var createdAt: Date
    var updatedAt: Date

    enum Columns: String, ColumnExpression {
        case id, name, connectorType, isEnabled, configJson, createdAt, updatedAt
    }
}
