import Foundation
import GRDB

/// Tracks the last successful sync time per peer per entity type.
/// Used by `SyncService.exportDelta` to produce incremental exports.
struct SyncCursor: Codable, FetchableRecord, MutablePersistableRecord, Identifiable, Sendable {
    static let databaseTableName = "sync_cursors"

    var id: UUID
    /// Identifier of the remote peer/device this cursor tracks.
    var peerId: String
    /// Entity type ("postings", "tasks", "assignments", "comments", "dependencies").
    var entityType: String
    /// Latest timestamp up to which data has been successfully synced with this peer.
    var lastSyncedAt: Date
    var updatedAt: Date

    enum Columns: String, ColumnExpression {
        case id, peerId, entityType, lastSyncedAt, updatedAt
    }
}
