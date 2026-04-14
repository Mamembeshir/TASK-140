import Foundation
import GRDB

struct PluginApproval: Codable, FetchableRecord, MutablePersistableRecord, Identifiable, Sendable {
    static let databaseTableName = "plugin_approvals"

    var id: UUID
    var pluginId: UUID
    var approverId: UUID
    var step: Int
    var decision: PluginApprovalDecision
    var notes: String?
    var decidedAt: Date

    enum Columns: String, ColumnExpression {
        case id, pluginId, approverId, step, decision, notes, decidedAt
    }
}
