import Foundation
import GRDB

enum PostingsSchemaMigration {
    static func migrate(_ db: Database) throws {
        // MARK: - Service Postings
        try db.create(table: "service_postings") { t in
            t.primaryKey("id", .text).notNull()
            t.column("title", .text).notNull()
            t.column("siteAddress", .text).notNull()
            t.column("dueDate", .datetime).notNull()
            t.column("budgetCapCents", .integer).notNull()
            t.column("status", .text).notNull().defaults(to: "DRAFT")
            t.column("acceptanceMode", .text).notNull().defaults(to: "INVITE_ONLY")
            t.column("createdBy", .text).notNull()
                .references("users", onDelete: .restrict)
            t.column("watermarkEnabled", .boolean).notNull().defaults(to: false)
            t.column("version", .integer).notNull().defaults(to: 1)
            t.column("createdAt", .datetime).notNull()
            t.column("updatedAt", .datetime).notNull()
        }

        try db.create(index: "idx_service_postings_createdBy",
                       on: "service_postings", columns: ["createdBy"])
        try db.create(index: "idx_service_postings_status",
                       on: "service_postings", columns: ["status"])

        // MARK: - Assignments
        try db.create(table: "assignments") { t in
            t.primaryKey("id", .text).notNull()
            t.column("postingId", .text).notNull()
                .references("service_postings", onDelete: .cascade)
            t.column("technicianId", .text).notNull()
                .references("users", onDelete: .restrict)
            t.column("status", .text).notNull().defaults(to: "INVITED")
            t.column("acceptedAt", .datetime)
            t.column("auditNote", .text)
            t.column("version", .integer).notNull().defaults(to: 1)
            t.column("createdAt", .datetime).notNull()
            t.column("updatedAt", .datetime).notNull()
            t.uniqueKey(["postingId", "technicianId"])
        }

        try db.create(index: "idx_assignments_postingId",
                       on: "assignments", columns: ["postingId"])
        try db.create(index: "idx_assignments_technicianId",
                       on: "assignments", columns: ["technicianId"])

        // MARK: - Tasks
        try db.create(table: "tasks") { t in
            t.primaryKey("id", .text).notNull()
            t.column("postingId", .text).notNull()
                .references("service_postings", onDelete: .cascade)
            t.column("parentTaskId", .text)
                .references("tasks", onDelete: .restrict)
            t.column("title", .text).notNull()
            t.column("description", .text)
            t.column("priority", .text).notNull().defaults(to: "P2")
            t.column("status", .text).notNull().defaults(to: "NOT_STARTED")
            t.column("blockedComment", .text)
            t.column("assignedTo", .text)
                .references("users", onDelete: .setNull)
            t.column("sortOrder", .integer).notNull().defaults(to: 0)
            t.column("version", .integer).notNull().defaults(to: 1)
            t.column("createdAt", .datetime).notNull()
            t.column("updatedAt", .datetime).notNull()
        }

        try db.create(index: "idx_tasks_postingId",
                       on: "tasks", columns: ["postingId"])

        // MARK: - Dependencies
        try db.create(table: "dependencies") { t in
            t.primaryKey("id", .text).notNull()
            t.column("taskId", .text).notNull()
                .references("tasks", onDelete: .cascade)
            t.column("dependsOnTaskId", .text).notNull()
                .references("tasks", onDelete: .cascade)
            t.column("type", .text).notNull().defaults(to: "FINISH_TO_START")
            t.uniqueKey(["taskId", "dependsOnTaskId"])
        }
    }
}
