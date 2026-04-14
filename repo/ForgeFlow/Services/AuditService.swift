import Foundation
import GRDB

/// Append-only audit recording service.
/// All write operations in the app must record an audit entry.
final class AuditService: Sendable {
    private let dbPool: DatabasePool

    init(dbPool: DatabasePool) {
        self.dbPool = dbPool
    }

    /// Records an audit entry. This is append-only — entries are never updated or deleted.
    func record(
        actorId: UUID,
        action: String,
        entityType: String,
        entityId: UUID,
        beforeData: String? = nil,
        afterData: String? = nil
    ) async throws {
        let entry = AuditEntry(
            id: UUID(),
            actorId: actorId,
            action: action,
            entityType: entityType,
            entityId: entityId,
            beforeData: beforeData,
            afterData: afterData,
            timestamp: Date()
        )

        try await dbPool.write { db in
            try entry.insert(db)
        }
    }

    /// Records an audit entry within an existing database transaction.
    func record(
        db: Database,
        actorId: UUID,
        action: String,
        entityType: String,
        entityId: UUID,
        beforeData: String? = nil,
        afterData: String? = nil
    ) throws {
        let entry = AuditEntry(
            id: UUID(),
            actorId: actorId,
            action: action,
            entityType: entityType,
            entityId: entityId,
            beforeData: beforeData,
            afterData: afterData,
            timestamp: Date()
        )
        try entry.insert(db)
    }

    /// Fetches audit entries for a specific entity.
    func entries(for entityType: String, entityId: UUID) async throws -> [AuditEntry] {
        try await dbPool.read { db in
            try AuditEntry
                .filter(AuditEntry.Columns.entityType == entityType)
                .filter(AuditEntry.Columns.entityId == entityId)
                .order(AuditEntry.Columns.timestamp.desc)
                .fetchAll(db)
        }
    }

    /// Fetches recent audit entries.
    func recentEntries(limit: Int = 50) async throws -> [AuditEntry] {
        try await dbPool.read { db in
            try AuditEntry
                .order(AuditEntry.Columns.timestamp.desc)
                .limit(limit)
                .fetchAll(db)
        }
    }
}
