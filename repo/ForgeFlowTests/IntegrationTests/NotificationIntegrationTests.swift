import Testing
import Foundation
import GRDB
@testable import ForgeFlow

// MARK: - Integration Tests: NotificationService

struct NotificationIntegrationTests {

    // MARK: - Helpers

    private func makeDB() throws -> (DatabaseManager, NotificationService, NotificationRepository, UserRepository) {
        let db = try DatabaseManager(inMemory: true)
        let userRepo = UserRepository(dbPool: db.dbPool)
        let notifRepo = NotificationRepository(dbPool: db.dbPool)
        let service = NotificationService(
            dbPool: db.dbPool, notificationRepository: notifRepo, userRepository: userRepo
        )
        return (db, service, notifRepo, userRepo)
    }

    private func makeUser(userRepo: UserRepository, dbPool: DatabasePool, dndStart: String? = nil, dndEnd: String? = nil) async throws -> User {
        let now = Date()
        let user = User(
            id: UUID(), username: "testuser_\(UUID().uuidString.prefix(8))",
            role: .technician, status: .active,
            failedLoginCount: 0, lockedUntil: nil,
            biometricEnabled: false,
            dndStartTime: dndStart, dndEndTime: dndEnd,
            storageQuotaBytes: 2_147_483_648,
            version: 1, createdAt: now, updatedAt: now
        )
        try await userRepo.insert(user)
        return user
    }

    // MARK: - Dedup (MSG-02)

    @Test("Dedup: same event within 10 min → second send returns nil")
    func dedupWithinWindow() async throws {
        let (db2, service2, _, userRepo2) = try makeDB()
        let user2 = try await makeUser(userRepo: userRepo2, dbPool: db2.dbPool)
        let now = Date()

        let first = try await service2.send(
            recipientId: user2.id, eventType: .commentAdded,
            postingId: nil, title: "T1", body: "B1", now: now
        )
        let second = try await service2.send(
            recipientId: user2.id, eventType: .commentAdded,
            postingId: nil, title: "T2", body: "B2",
            now: now.addingTimeInterval(60 * 5) // 5 min later — within window
        )
        #expect(first != nil)
        #expect(second == nil)
    }

    @Test("Dedup: same event after 11 min → second created")
    func dedupOutsideWindow() async throws {
        let (db, service, _, userRepo) = try makeDB()
        let user = try await makeUser(userRepo: userRepo, dbPool: db.dbPool)
        let now = Date()

        _ = try await service.send(
            recipientId: user.id, eventType: .commentAdded,
            postingId: nil, title: "T1", body: "B1", now: now
        )
        let second = try await service.send(
            recipientId: user.id, eventType: .commentAdded,
            postingId: nil, title: "T2", body: "B2",
            now: now.addingTimeInterval(60 * 11) // 11 min later — outside window
        )
        #expect(second != nil)
    }

    @Test("Dedup: different event type → both created")
    func dedupDifferentEvent() async throws {
        let (db, service, _, userRepo) = try makeDB()
        let user = try await makeUser(userRepo: userRepo, dbPool: db.dbPool)
        let now = Date()

        let first = try await service.send(
            recipientId: user.id, eventType: .commentAdded,
            postingId: nil, title: "T1", body: "B1", now: now
        )
        let second = try await service.send(
            recipientId: user.id, eventType: .taskBlocked,
            postingId: nil, title: "T2", body: "B2", now: now
        )
        #expect(first != nil)
        #expect(second != nil)
    }

    // MARK: - DND (questions.md 4.2)

    @Test("DND: notification during DND 22:00-07:00 at 23:00 stays PENDING")
    func dndNotificationStaysPending() async throws {
        let (db, service, notifRepo, userRepo) = try makeDB()
        let user = try await makeUser(userRepo: userRepo, dbPool: db.dbPool, dndStart: "22:00", dndEnd: "07:00")

        let nightTime = makeTime(hour: 23, minute: 0)
        let notif = try await service.send(
            recipientId: user.id, eventType: .assignmentInvited,
            postingId: nil, title: "Invite", body: "Body", now: nightTime
        )
        #expect(notif?.status == .pending)
    }

    @Test("DND: notification outside DND window → DELIVERED immediately")
    func dndNotificationDelivered() async throws {
        let (db, service, _, userRepo) = try makeDB()
        let user = try await makeUser(userRepo: userRepo, dbPool: db.dbPool, dndStart: "22:00", dndEnd: "07:00")

        let afternoon = makeTime(hour: 14, minute: 0)
        let notif = try await service.send(
            recipientId: user.id, eventType: .assignmentInvited,
            postingId: nil, title: "Invite", body: "Body", now: afternoon
        )
        #expect(notif?.status == .delivered)
    }

    @Test("DND: releaseDNDHeld transitions PENDING → DELIVERED after DND ends")
    func dndReleasePendingAfterWindow() async throws {
        let (db, service, notifRepo, userRepo) = try makeDB()
        let user = try await makeUser(userRepo: userRepo, dbPool: db.dbPool, dndStart: "22:00", dndEnd: "07:00")

        // Send during DND
        let nightTime = makeTime(hour: 23, minute: 30)
        let notif = try await service.send(
            recipientId: user.id, eventType: .assignmentInvited,
            postingId: nil, title: "Invite", body: "Body", now: nightTime
        )
        #expect(notif?.status == .pending)

        // Release at 10:00 (outside DND)
        let morningTime = makeTime(hour: 10, minute: 0)
        try await service.releaseDNDHeld(userId: user.id, now: morningTime)

        let all = try await notifRepo.findByRecipient(user.id)
        #expect(all.allSatisfy { $0.status == NotificationStatus.delivered })
    }

    @Test("DND: releaseDNDHeld while still in DND → notifications stay PENDING")
    func dndReleaseWhileInDND() async throws {
        let (db, service, notifRepo, userRepo) = try makeDB()
        let user = try await makeUser(userRepo: userRepo, dbPool: db.dbPool, dndStart: "22:00", dndEnd: "07:00")

        let nightTime = makeTime(hour: 23, minute: 0)
        _ = try await service.send(
            recipientId: user.id, eventType: .assignmentInvited,
            postingId: nil, title: "Invite", body: "Body", now: nightTime
        )

        // Try to release at 01:00 — still in DND
        let stillDND = makeTime(hour: 1, minute: 0)
        try await service.releaseDNDHeld(userId: user.id, now: stillDND)

        let all = try await notifRepo.findByRecipient(user.id)
        #expect(all.allSatisfy { $0.status == NotificationStatus.pending })
    }

    // MARK: - Status transitions

    @Test("markSeen: DELIVERED → SEEN")
    func markSeenTransition() async throws {
        let (db, service, notifRepo, userRepo) = try makeDB()
        let user = try await makeUser(userRepo: userRepo, dbPool: db.dbPool)
        let afternoon = makeTime(hour: 14, minute: 0)

        let notif = try await service.send(
            recipientId: user.id, eventType: .commentAdded,
            postingId: nil, title: "T", body: "B", now: afternoon
        )
        guard let notif else { throw TestError("Expected notification") }
        #expect(notif.status == .delivered)

        try await service.markSeen(notif.id, actorId: user.id)

        let updated = try await notifRepo.findById(notif.id)
        #expect(updated?.status == .seen)
    }

    @Test("markSeen: PENDING → throws invalidStatusTransition")
    func markSeenFromPendingThrows() async throws {
        let (db, service, _, userRepo) = try makeDB()
        let user = try await makeUser(userRepo: userRepo, dbPool: db.dbPool, dndStart: "22:00", dndEnd: "07:00")
        let nightTime = makeTime(hour: 23, minute: 0)

        let notif = try await service.send(
            recipientId: user.id, eventType: .commentAdded,
            postingId: nil, title: "T", body: "B", now: nightTime
        )
        guard let notif else { throw TestError("Expected notification") }
        #expect(notif.status == .pending)

        do {
            try await service.markSeen(notif.id, actorId: user.id)
            throw TestError("Expected throw but did not")
        } catch let error as NotificationError {
            if case .invalidStatusTransition(let from, let to) = error {
                #expect(from == .pending)
                #expect(to == .seen)
            } else {
                throw TestError("Wrong error: \(error)")
            }
        }
    }

    @Test("bulkMarkSeen: all DELIVERED → SEEN for user")
    func bulkMarkSeen() async throws {
        let (db, service, notifRepo, userRepo) = try makeDB()
        let user = try await makeUser(userRepo: userRepo, dbPool: db.dbPool)
        let now = makeTime(hour: 14, minute: 0)

        _ = try await service.send(recipientId: user.id, eventType: .commentAdded, postingId: nil, title: "T1", body: "B", now: now)
        _ = try await service.send(recipientId: user.id, eventType: .taskBlocked, postingId: nil, title: "T2", body: "B", now: now)

        let countBefore = try await service.getUnreadCount(userId: user.id, actorId: user.id)
        #expect(countBefore == 2)

        try await service.bulkMarkSeen(userId: user.id, actorId: user.id)

        let countAfter = try await service.getUnreadCount(userId: user.id, actorId: user.id)
        #expect(countAfter == 0)

        let all = try await notifRepo.findByRecipient(user.id)
        #expect(all.allSatisfy { $0.status == NotificationStatus.seen })
    }

    @Test("getUnreadCount: counts only DELIVERED notifications")
    func unreadCountOnlyDelivered() async throws {
        let (db, service, _, userRepo) = try makeDB()
        let user = try await makeUser(userRepo: userRepo, dbPool: db.dbPool, dndStart: "22:00", dndEnd: "07:00")

        let afternoon = makeTime(hour: 14, minute: 0)
        let night = makeTime(hour: 23, minute: 0)

        _ = try await service.send(recipientId: user.id, eventType: .commentAdded, postingId: nil, title: "T", body: "B", now: afternoon)
        _ = try await service.send(recipientId: user.id, eventType: .taskBlocked, postingId: nil, title: "T2", body: "B2", now: night)

        let count = try await service.getUnreadCount(userId: user.id, actorId: user.id)
        #expect(count == 1) // Only the DELIVERED one; the night one is PENDING
    }

    // MARK: - Assignment accepted → coordinator notified (MSG-07)

    @Test("Assignment accepted → coordinator receives ASSIGNMENT_ACCEPTED notification")
    func assignmentAcceptedNotifiesCoordinator() async throws {
        let (db, service, notifRepo, userRepo) = try makeDB()
        // Insert coordinator and technician directly (bypass audit FK constraint in test env)
        let coordinator = try await makeUserWithRole(userRepo: userRepo, dbPool: db.dbPool, role: .coordinator)
        let technician = try await makeUserWithRole(userRepo: userRepo, dbPool: db.dbPool, role: .technician)

        let postingRepo = PostingRepository(dbPool: db.dbPool)
        let assignmentRepo = AssignmentRepository(dbPool: db.dbPool)
        let taskRepo = TaskRepository(dbPool: db.dbPool)
        let auditSvc = AuditService(dbPool: db.dbPool)

        let postingService = PostingService(
            dbPool: db.dbPool, postingRepository: postingRepo,
            taskRepository: taskRepo, userRepository: userRepo, auditService: auditSvc,
            notificationService: service, assignmentRepository: assignmentRepo
        )
        let assignmentService = AssignmentService(
            dbPool: db.dbPool, assignmentRepository: assignmentRepo,
            postingRepository: postingRepo, userRepository: userRepo,
            auditService: auditSvc, notificationService: service
        )

        let posting = try await postingService.create(
            actorId: coordinator.id, title: "HVAC Repair",
            siteAddress: "123 Main St", dueDate: Date().addingTimeInterval(86400),
            budgetCents: 100_00, acceptanceMode: .open, watermarkEnabled: false
        )
        _ = try await postingService.publish(actorId: coordinator.id, postingId: posting.id)
        _ = try await assignmentService.accept(actorId: technician.id, postingId: posting.id, technicianId: technician.id)

        // Give background Task a moment to fire
        try await Task.sleep(for: .milliseconds(500))

        let notifications = try await notifRepo.findByRecipient(coordinator.id)
        let accepted = notifications.filter { $0.eventType == .assignmentAccepted }
        #expect(!accepted.isEmpty)
    }

    // MARK: - Helpers

    private func makeUserWithRole(userRepo: UserRepository, dbPool: DatabasePool, role: Role) async throws -> User {
        let now = Date()
        let user = User(
            id: UUID(), username: "testuser_\(role.rawValue)_\(UUID().uuidString.prefix(6))",
            role: role, status: .active,
            failedLoginCount: 0, lockedUntil: nil,
            biometricEnabled: false,
            dndStartTime: nil, dndEndTime: nil,
            storageQuotaBytes: 2_147_483_648,
            version: 1, createdAt: now, updatedAt: now
        )
        try await userRepo.insert(user)
        return user
    }

    private func makeTime(hour: Int, minute: Int) -> Date {
        var components = Calendar.current.dateComponents([.year, .month, .day], from: Date())
        components.hour = hour
        components.minute = minute
        return Calendar.current.date(from: components)!
    }

    struct TestError: Error {
        let message: String
        init(_ message: String) { self.message = message }
    }
}
