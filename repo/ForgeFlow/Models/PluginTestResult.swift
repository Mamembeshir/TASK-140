import Foundation
import GRDB

struct PluginTestResult: Codable, FetchableRecord, MutablePersistableRecord, Identifiable, Sendable {
    static let databaseTableName = "plugin_test_results"

    var id: UUID
    var pluginId: UUID
    var postingId: UUID
    var status: PluginTestResultStatus
    var errorDetails: String?
    var testedAt: Date

    enum Columns: String, ColumnExpression {
        case id, pluginId, postingId, status, errorDetails, testedAt
    }
}
