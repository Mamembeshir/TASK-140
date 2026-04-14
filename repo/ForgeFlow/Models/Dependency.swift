import Foundation
import GRDB

struct Dependency: Codable, FetchableRecord, PersistableRecord, Identifiable, Sendable {
    static let databaseTableName = "dependencies"

    var id: UUID
    var taskId: UUID
    var dependsOnTaskId: UUID
    var type: DependencyType

    enum Columns: String, ColumnExpression {
        case id, taskId, dependsOnTaskId, type
    }
}
