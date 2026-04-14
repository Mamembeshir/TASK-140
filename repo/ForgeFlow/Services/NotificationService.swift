import Foundation
import GRDB

final class NotificationService: Sendable {
    private let dbPool: DatabasePool
    private let notificationRepository: NotificationRepository
    private let userRepository: UserRepository

    static let dedupWindow: TimeInterval = 10 * 60  // 10 minutes (MSG-02)

    init(dbPool: DatabasePool, notificationRepository: NotificationRepository, userRepository: UserRepository) {
        self.dbPool = dbPool
        self.notificationRepository = notificationRepository
        self.userRepository = userRepository
    }

    // MARK: - Send

    /// Creates a notification with dedup and DND checks.
    /// - Parameter now: Injectable for testing; defaults to current time.
    /// - Returns: The created notification, or nil if deduped.
    @discardableResult
    func send(
        recipientId: UUID,
        eventType: NotificationEventType,
        postingId: UUID?,
        title: String,
        body: String,
        now: Date = Date()
    ) async throws -> ForgeNotification? {
        // MSG-04 / questions.md 4.2: Check DND — reads user prefs, safe outside the write lock.
        let inDND = try await isWithinDND(userId: recipientId, at: now)

        // MSG-02: Dedup + insert in a single write transaction so concurrent sends
        // cannot both pass the duplicate check and produce two notifications.
        let notification: ForgeNotification? = try await dbPool.write { [self] db in
            guard try notificationRepository.findDuplicateInTransaction(
                db: db,
                eventType: eventType,
                postingId: postingId,
                recipientId: recipientId,
                within: Self.dedupWindow,
                now: now
            ) == nil else { return nil }

            let notification = ForgeNotification(
                id: UUID(),
                recipientId: recipientId,
                eventType: eventType,
                postingId: postingId,
                title: title,
                body: body,
                status: inDND ? .pending : .delivered,
                createdAt: now,
                updatedAt: now
            )
            try notificationRepository.insertInTransaction(db: db, notification)
            return notification
        }

        return notification
    }

    // MARK: - Status transitions

    func markSeen(_ notificationId: UUID, actorId: UUID) async throws {
        guard let notification = try await notificationRepository.findById(notificationId) else {
            throw NotificationError.notificationNotFound
        }
        guard notification.recipientId == actorId else {
            throw NotificationError.unauthorized
        }
        guard notification.status == .delivered else {
            throw NotificationError.invalidStatusTransition(from: notification.status, to: .seen)
        }
        try await dbPool.write { [self] db in
            try notificationRepository.updateStatusInTransaction(db: db, id: notificationId, status: .seen)
        }
    }

    func bulkMarkSeen(userId: UUID, actorId: UUID) async throws {
        guard actorId == userId else { throw NotificationError.unauthorized }
        try await dbPool.write { [self] db in
            try notificationRepository.markAllDeliveredSeenInTransaction(db: db, userId: userId)
        }
    }

    // MARK: - Queries

    /// Returns unread count. actorId must match userId (users can only read their own notifications).
    func getUnreadCount(userId: UUID, actorId: UUID) async throws -> Int {
        guard actorId == userId else { throw NotificationError.unauthorized }
        return try await notificationRepository.countUnread(userId)
    }

    /// Returns notifications for userId. actorId must match userId.
    func listNotifications(userId: UUID, actorId: UUID) async throws -> [ForgeNotification] {
        guard actorId == userId else { throw NotificationError.unauthorized }
        return try await notificationRepository.findByRecipient(userId)
    }

    // MARK: - DND release (call on foreground / timer)

    /// Transitions any PENDING notifications to DELIVERED if DND has ended.
    func releaseDNDHeld(userId: UUID, now: Date = Date()) async throws {
        let inDND = try await isWithinDND(userId: userId, at: now)
        guard !inDND else { return }

        let pending = try await notificationRepository.findPending(userId)
        guard !pending.isEmpty else { return }

        try await dbPool.write { [self] db in
            for notification in pending {
                try notificationRepository.updateStatusInTransaction(
                    db: db, id: notification.id, status: .delivered
                )
            }
        }
    }

    // MARK: - DND Helpers

    func isWithinDND(userId: UUID, at date: Date = Date()) async throws -> Bool {
        guard let user = try await userRepository.findById(userId) else { return false }
        return Self.checkDND(startTime: user.dndStartTime, endTime: user.dndEndTime, at: date)
    }

    /// Pure function — used in tests without a database.
    static func checkDND(startTime: String?, endTime: String?, at date: Date) -> Bool {
        guard let startStr = startTime, let endStr = endTime,
              let startMinutes = parseTimeToMinutes(startStr),
              let endMinutes = parseTimeToMinutes(endStr) else { return false }

        let calendar = Calendar.current
        let hour = calendar.component(.hour, from: date)
        let minute = calendar.component(.minute, from: date)
        let currentMinutes = hour * 60 + minute

        if startMinutes <= endMinutes {
            // Same-day range e.g. 08:00-18:00
            return currentMinutes >= startMinutes && currentMinutes < endMinutes
        } else {
            // Overnight range e.g. 22:00-07:00
            return currentMinutes >= startMinutes || currentMinutes < endMinutes
        }
    }

    static func parseTimeToMinutes(_ time: String) -> Int? {
        let parts = time.split(separator: ":").compactMap { Int(String($0)) }
        guard parts.count == 2, (0..<24).contains(parts[0]), (0..<60).contains(parts[1]) else { return nil }
        return parts[0] * 60 + parts[1]
    }
}
