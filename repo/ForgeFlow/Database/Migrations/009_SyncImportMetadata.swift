import Foundation
import GRDB

enum SyncImportMetadataMigration {
    static func migrate(_ db: Database) throws {
        // Add source-manifest metadata to sync_imports so the import-side delta cursor
        // can be advanced to the source's exportedAt watermark (not local importedAt)
        // and scoped to exactly the entity types the source included in the file.
        try db.alter(table: "sync_imports") { t in
            t.add(column: "sourceExportedAt", .datetime)
            t.add(column: "sourceEntityTypes", .text) // JSON array, e.g. ["postings","tasks"]
        }
    }
}
