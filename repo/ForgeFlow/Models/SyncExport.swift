import Foundation
import GRDB

struct SyncExport: Codable, FetchableRecord, PersistableRecord, Identifiable, Sendable {
    static let databaseTableName = "sync_exports"

    var id: UUID
    var exportedBy: UUID
    var filePath: String
    var entityTypes: String // JSON array
    var recordCount: Int
    var checksumSha256: String
    var exportedAt: Date

    enum Columns: String, ColumnExpression {
        case id, exportedBy, filePath, entityTypes, recordCount, checksumSha256, exportedAt
    }
}
