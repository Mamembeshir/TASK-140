import Foundation
import GRDB

enum InitialSchemaMigration {
    static func migrate(_ db: Database) throws {
        // MARK: - Users
        try db.create(table: "users") { t in
            t.primaryKey("id", .text).notNull()
            t.column("username", .text).notNull().unique()
            t.column("role", .text).notNull()
            t.column("status", .text).notNull().defaults(to: "ACTIVE")
            t.column("failedLoginCount", .integer).notNull().defaults(to: 0)
            t.column("lockedUntil", .datetime)
            t.column("biometricEnabled", .boolean).notNull().defaults(to: false)
            t.column("dndStartTime", .text)
            t.column("dndEndTime", .text)
            t.column("storageQuotaBytes", .integer).notNull().defaults(to: 2_147_483_648) // 2 GB
            t.column("version", .integer).notNull().defaults(to: 1)
            t.column("createdAt", .datetime).notNull()
            t.column("updatedAt", .datetime).notNull()
        }

        // MARK: - Audit Entries (Append-Only)
        try db.create(table: "audit_entries") { t in
            t.primaryKey("id", .text).notNull()
            t.column("actorId", .text).notNull()
                .references("users", onDelete: .restrict)
            t.column("action", .text).notNull()
            t.column("entityType", .text).notNull()
            t.column("entityId", .text).notNull()
            t.column("beforeData", .text)
            t.column("afterData", .text)
            t.column("timestamp", .datetime).notNull()
        }

        try db.create(index: "idx_audit_entries_entityType_entityId",
                       on: "audit_entries",
                       columns: ["entityType", "entityId"])
        try db.create(index: "idx_audit_entries_actorId",
                       on: "audit_entries",
                       columns: ["actorId"])
        try db.create(index: "idx_audit_entries_timestamp",
                       on: "audit_entries",
                       columns: ["timestamp"])

        // MARK: - Sync Exports
        try db.create(table: "sync_exports") { t in
            t.primaryKey("id", .text).notNull()
            t.column("exportedBy", .text).notNull()
                .references("users", onDelete: .restrict)
            t.column("filePath", .text).notNull()
            t.column("entityTypes", .text).notNull() // JSON array
            t.column("recordCount", .integer).notNull()
            t.column("checksumSha256", .text).notNull()
            t.column("exportedAt", .datetime).notNull()
        }

        // MARK: - Sync Imports
        try db.create(table: "sync_imports") { t in
            t.primaryKey("id", .text).notNull()
            t.column("importedBy", .text).notNull()
                .references("users", onDelete: .restrict)
            t.column("filePath", .text).notNull()
            t.column("recordCount", .integer).notNull()
            t.column("conflictsCount", .integer).notNull().defaults(to: 0)
            t.column("status", .text).notNull().defaults(to: "PENDING")
            t.column("importedAt", .datetime).notNull()
        }
    }
}
