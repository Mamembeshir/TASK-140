import Foundation
import GRDB

enum PostingFieldValuesMigration {
    static func migrate(_ db: Database) throws {
        try db.create(table: "posting_field_values") { t in
            t.primaryKey("id", .text).notNull()
            t.column("postingId", .text).notNull()
                .references("service_postings", column: "id", onDelete: .cascade)
            t.column("pluginFieldId", .text).notNull()
                .references("plugin_fields", column: "id", onDelete: .cascade)
            t.column("value", .text).notNull()
            t.column("createdAt", .datetime).notNull()
            t.column("updatedAt", .datetime).notNull()
        }

        try db.create(
            index: "idx_posting_field_values_posting",
            on: "posting_field_values",
            columns: ["postingId"]
        )

        try db.create(
            index: "idx_posting_field_values_unique",
            on: "posting_field_values",
            columns: ["postingId", "pluginFieldId"],
            unique: true
        )
    }
}
