import Foundation
import GRDB

enum SyncCursorSchemaMigration {
    static func migrate(_ db: Database) throws {
        // MARK: - sync_cursors
        // Persists per-peer, per-entity-type sync state for incremental (delta) exports.
        try db.create(table: "sync_cursors") { t in
            t.primaryKey("id", .text).notNull()
            t.column("peerId", .text).notNull()
            t.column("entityType", .text).notNull()
            t.column("lastSyncedAt", .datetime).notNull()
            t.column("updatedAt", .datetime).notNull()
        }

        // Unique index ensures one cursor per (peer, entityType) pair
        try db.create(
            index: "idx_sync_cursors_peer_entity",
            on: "sync_cursors",
            columns: ["peerId", "entityType"],
            unique: true
        )
    }
}
