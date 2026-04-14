import Foundation
import GRDB

enum MessagingSchemaMigration {
    static func migrate(_ db: Database) throws {
        // MARK: - notifications

        try db.create(table: "notifications") { t in
            t.column("id", .text).notNull().primaryKey()
            t.column("recipientId", .text).notNull()
                .references("users", column: "id", onDelete: .cascade)
            t.column("eventType", .text).notNull()
            t.column("postingId", .text)
                .references("service_postings", column: "id", onDelete: .setNull)
            t.column("title", .text).notNull()
            t.column("body", .text).notNull()
            t.column("status", .text).notNull().defaults(to: "PENDING")
            t.column("createdAt", .datetime).notNull()
            t.column("updatedAt", .datetime).notNull()
        }

        try db.create(indexOn: "notifications", columns: ["recipientId", "status"])
        try db.create(indexOn: "notifications", columns: ["recipientId", "eventType", "postingId", "createdAt"])

        // MARK: - connector_definitions (MSG-06: Email + SMS placeholders)

        try db.create(table: "connector_definitions") { t in
            t.column("id", .text).notNull().primaryKey()
            t.column("name", .text).notNull()
            t.column("connectorType", .text).notNull()
            t.column("isEnabled", .boolean).notNull().defaults(to: false)
            t.column("configJson", .text)
            t.column("createdAt", .datetime).notNull()
            t.column("updatedAt", .datetime).notNull()
        }

        // Seed Email and SMS connectors (disabled per MSG-06)
        let now = Date()
        try db.execute(
            sql: """
                INSERT INTO connector_definitions (id, name, connectorType, isEnabled, configJson, createdAt, updatedAt)
                VALUES (?, 'Email', 'EMAIL', 0, NULL, ?, ?)
            """,
            arguments: [UUID().uuidString, now, now]
        )
        try db.execute(
            sql: """
                INSERT INTO connector_definitions (id, name, connectorType, isEnabled, configJson, createdAt, updatedAt)
                VALUES (?, 'SMS', 'SMS', 0, NULL, ?, ?)
            """,
            arguments: [UUID().uuidString, now, now]
        )
    }
}
