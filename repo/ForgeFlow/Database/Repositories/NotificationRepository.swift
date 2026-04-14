import Foundation
import GRDB

final class NotificationRepository: Sendable {
    private let dbPool: DatabasePool

    init(dbPool: DatabasePool) {
        self.dbPool = dbPool
    }

    // MARK: - Reads

    func findById(_ id: UUID) async throws -> ForgeNotification? {
        try await dbPool.read { db in
            try ForgeNotification.fetchOne(db, key: id)
        }
    }

    func findByRecipient(_ userId: UUID) async throws -> [ForgeNotification] {
        try await dbPool.read { db in
            try ForgeNotification
                .filter(ForgeNotification.Columns.recipientId == userId)
                .order(ForgeNotification.Columns.createdAt.desc)
                .fetchAll(db)
        }
    }

    /// MSG-02: Check for a duplicate notification within the given window.
    func findDuplicate(
        eventType: NotificationEventType,
        postingId: UUID?,
        recipientId: UUID,
        within window: TimeInterval,
        now: Date = Date()
    ) async throws -> ForgeNotification? {
        let threshold = now.addingTimeInterval(-window)
        return try await dbPool.read { db in
            var request = ForgeNotification
                .filter(ForgeNotification.Columns.recipientId == recipientId)
                .filter(ForgeNotification.Columns.eventType == eventType.rawValue)
                .filter(ForgeNotification.Columns.createdAt >= threshold)
            if let pid = postingId {
                request = request.filter(ForgeNotification.Columns.postingId == pid)
            } else {
                request = request.filter(ForgeNotification.Columns.postingId == nil)
            }
            return try request.fetchOne(db)
        }
    }

    func countUnread(_ userId: UUID) async throws -> Int {
        try await dbPool.read { db in
            try ForgeNotification
                .filter(ForgeNotification.Columns.recipientId == userId)
                .filter(ForgeNotification.Columns.status == NotificationStatus.delivered.rawValue)
                .fetchCount(db)
        }
    }

    func findPending(_ userId: UUID) async throws -> [ForgeNotification] {
        try await dbPool.read { db in
            try ForgeNotification
                .filter(ForgeNotification.Columns.recipientId == userId)
                .filter(ForgeNotification.Columns.status == NotificationStatus.pending.rawValue)
                .fetchAll(db)
        }
    }

    /// Synchronous dedup check for use inside an existing write transaction.
    func findDuplicateInTransaction(
        db: Database,
        eventType: NotificationEventType,
        postingId: UUID?,
        recipientId: UUID,
        within window: TimeInterval,
        now: Date
    ) throws -> ForgeNotification? {
        let threshold = now.addingTimeInterval(-window)
        var request = ForgeNotification
            .filter(ForgeNotification.Columns.recipientId == recipientId)
            .filter(ForgeNotification.Columns.eventType == eventType.rawValue)
            .filter(ForgeNotification.Columns.createdAt >= threshold)
        if let pid = postingId {
            request = request.filter(ForgeNotification.Columns.postingId == pid)
        } else {
            request = request.filter(ForgeNotification.Columns.postingId == nil)
        }
        return try request.fetchOne(db)
    }

    // MARK: - Transactional writes

    func insertInTransaction(db: Database, _ notification: ForgeNotification) throws {
        var n = notification
        try n.insert(db)
    }

    func updateStatusInTransaction(db: Database, id: UUID, status: NotificationStatus) throws {
        try db.execute(
            sql: "UPDATE notifications SET status = ?, updatedAt = ? WHERE id = ?",
            arguments: [status.rawValue, Date(), id]
        )
    }

    func markAllDeliveredSeenInTransaction(db: Database, userId: UUID) throws {
        try db.execute(
            sql: """
                UPDATE notifications
                SET status = ?, updatedAt = ?
                WHERE recipientId = ? AND status = ?
            """,
            arguments: [
                NotificationStatus.seen.rawValue,
                Date(),
                userId,
                NotificationStatus.delivered.rawValue
            ]
        )
    }
}
