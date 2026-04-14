import Foundation
import GRDB

enum PluginSyncSchemaMigration {
    static func migrate(_ db: Database) throws {
        // MARK: - plugin_definitions

        try db.create(table: "plugin_definitions") { t in
            t.primaryKey("id", .text).notNull()
            t.column("name", .text).notNull()
            t.column("description", .text).notNull()
            t.column("category", .text).notNull()
            t.column("status", .text).notNull().defaults(to: "DRAFT")
            t.column("createdBy", .text).notNull()
                .references("users", column: "id", onDelete: .restrict)
            t.column("version", .integer).notNull().defaults(to: 1)
            t.column("createdAt", .datetime).notNull()
            t.column("updatedAt", .datetime).notNull()
        }

        // MARK: - plugin_fields

        try db.create(table: "plugin_fields") { t in
            t.primaryKey("id", .text).notNull()
            t.column("pluginId", .text).notNull()
                .references("plugin_definitions", column: "id", onDelete: .cascade)
            t.column("fieldName", .text).notNull()
            t.column("fieldType", .text).notNull()
            t.column("unit", .text)
            t.column("validationRules", .text) // JSON string
            t.column("sortOrder", .integer).notNull().defaults(to: 0)
            t.column("createdAt", .datetime).notNull()
        }

        try db.create(
            index: "idx_plugin_fields_pluginId",
            on: "plugin_fields",
            columns: ["pluginId"]
        )

        // MARK: - plugin_test_results

        try db.create(table: "plugin_test_results") { t in
            t.primaryKey("id", .text).notNull()
            t.column("pluginId", .text).notNull()
                .references("plugin_definitions", column: "id", onDelete: .cascade)
            t.column("postingId", .text).notNull()
                .references("service_postings", column: "id", onDelete: .cascade)
            t.column("status", .text).notNull() // PASS / FAIL
            t.column("errorDetails", .text)
            t.column("testedAt", .datetime).notNull()
        }

        // MARK: - plugin_approvals

        try db.create(table: "plugin_approvals") { t in
            t.primaryKey("id", .text).notNull()
            t.column("pluginId", .text).notNull()
                .references("plugin_definitions", column: "id", onDelete: .cascade)
            t.column("approverId", .text).notNull()
                .references("users", column: "id", onDelete: .restrict)
            t.column("step", .integer).notNull() // 1 or 2
            t.column("decision", .text).notNull() // APPROVED / REJECTED
            t.column("notes", .text)
            t.column("decidedAt", .datetime).notNull()
        }

        try db.create(
            index: "idx_plugin_approvals_pluginId",
            on: "plugin_approvals",
            columns: ["pluginId"]
        )
    }
}
