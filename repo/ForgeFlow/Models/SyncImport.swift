import Foundation
import GRDB

struct SyncImport: Codable, FetchableRecord, MutablePersistableRecord, Identifiable, Sendable {
    static let databaseTableName = "sync_imports"

    var id: UUID
    var importedBy: UUID
    var filePath: String
    var recordCount: Int
    var conflictsCount: Int
    var status: SyncImportStatus
    var importedAt: Date
    /// The `exportedAt` timestamp parsed from the source peer's export manifest.
    /// Advance the import-side cursor to this value — NOT to `importedAt` (local clock).
    /// Using local time as the watermark can skip records created on the source between
    /// export generation and local import time.
    var sourceExportedAt: Date?
    /// JSON-encoded entity-type array parsed from the source manifest (e.g. `["postings","tasks"]`).
    /// Use these exact types when calling `recordImportedFrom` so the cursor scope matches
    /// what the source actually exported, not what the local UI toggles are set to.
    var sourceEntityTypes: String?

    enum Columns: String, ColumnExpression {
        case id, importedBy, filePath, recordCount, conflictsCount, status, importedAt
        case sourceExportedAt, sourceEntityTypes
    }
}
