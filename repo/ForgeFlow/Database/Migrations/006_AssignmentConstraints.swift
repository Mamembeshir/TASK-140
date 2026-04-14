import Foundation
import GRDB

enum AssignmentConstraintsMigration {
    static func migrate(_ db: Database) throws {
        // First-accepted-wins enforcement for OPEN postings:
        //
        // GRDB DatabasePool serializes all writes through a single writer connection,
        // so the check-then-insert in AssignmentService.accept() is already atomic.
        //
        // We add a covering index to make the "find accepted for posting" query fast,
        // ensuring the serialized check is efficient even under load.
        try db.create(
            index: "idx_assignments_posting_status",
            on: "assignments",
            columns: ["postingId", "status"],
            ifNotExists: true
        )
    }
}
