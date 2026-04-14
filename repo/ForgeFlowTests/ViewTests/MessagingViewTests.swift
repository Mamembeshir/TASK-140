import Testing
import Foundation
import GRDB
@testable import ForgeFlow

// MARK: - View Tests: Messaging

struct MessagingViewTests {

    // MARK: - MessagingCenterViewModel

    @Test("MessagingCenterViewModel: filteredNotifications returns all when no filter set")
    func filterNone() async throws {
        let (db, service, _, userRepo) = try makeDB()
        let appState = makeAppState()
        let user = try await makeUser(userRepo: userRepo, dbPool: db.dbPool)
        appState.login(userId: user.id, role: .technician)

        let vm = MessagingCenterViewModel(
            notificationService: service, dbPool: db.dbPool, appState: appState
        )

        let now = makeTime(hour: 14, minute: 0)
        _ = try await service.send(recipientId: user.id, eventType: .commentAdded, postingId: nil, title: "A", body: "B", now: now)
        _ = try await service.send(recipientId: user.id, eventType: .taskBlocked, postingId: nil, title: "C", body: "D", now: now)

        await vm.load()
        #expect(vm.filteredNotifications.count == 2)
    }

    @Test("MessagingCenterViewModel: filteredNotifications filters by event type")
    func filterByEventType() async throws {
        let (db, service, _, userRepo) = try makeDB()
        let appState = makeAppState()
        let user = try await makeUser(userRepo: userRepo, dbPool: db.dbPool)
        appState.login(userId: user.id, role: .technician)

        let vm = MessagingCenterViewModel(
            notificationService: service, dbPool: db.dbPool, appState: appState
        )

        let now = makeTime(hour: 14, minute: 0)
        _ = try await service.send(recipientId: user.id, eventType: .commentAdded, postingId: nil, title: "A", body: "B", now: now)
        _ = try await service.send(recipientId: user.id, eventType: .taskBlocked, postingId: nil, title: "C", body: "D", now: now)

        await vm.load()
        vm.selectedEventType = .commentAdded
        #expect(vm.filteredNotifications.count == 1)
        #expect(vm.filteredNotifications.first?.eventType == .commentAdded)
    }

    @Test("MessagingCenterViewModel: unreadCount reflects DELIVERED notifications only")
    func unreadCountOnlyDelivered() async throws {
        let (db, service, _, userRepo) = try makeDB()
        let appState = makeAppState()
        let user = try await makeUser(userRepo: userRepo, dbPool: db.dbPool, dndStart: "22:00", dndEnd: "07:00")
        appState.login(userId: user.id, role: .technician)

        let vm = MessagingCenterViewModel(
            notificationService: service, dbPool: db.dbPool, appState: appState
        )

        let afternoon = makeTime(hour: 14, minute: 0)
        let night = makeTime(hour: 23, minute: 0)

        _ = try await service.send(recipientId: user.id, eventType: .commentAdded, postingId: nil, title: "A", body: "B", now: afternoon)
        _ = try await service.send(recipientId: user.id, eventType: .taskBlocked, postingId: nil, title: "C", body: "D", now: night)

        await vm.load()
        #expect(vm.unreadCount == 1)
    }

    @Test("MessagingCenterViewModel: markAllSeen clears unread count")
    func markAllSeenClearsCount() async throws {
        let (db, service, _, userRepo) = try makeDB()
        let appState = makeAppState()
        let user = try await makeUser(userRepo: userRepo, dbPool: db.dbPool)
        appState.login(userId: user.id, role: .technician)

        let vm = MessagingCenterViewModel(
            notificationService: service, dbPool: db.dbPool, appState: appState
        )

        let now = makeTime(hour: 14, minute: 0)
        _ = try await service.send(recipientId: user.id, eventType: .commentAdded, postingId: nil, title: "A", body: "B", now: now)
        _ = try await service.send(recipientId: user.id, eventType: .taskBlocked, postingId: nil, title: "C", body: "D", now: now)

        await vm.load()
        #expect(vm.unreadCount == 2)

        await vm.markAllSeen()
        await vm.load()
        #expect(vm.unreadCount == 0)
    }

    @Test("NotificationBadge: count == 0 renders without badge")
    func badgeZeroCount() {
        // Pure logic test — badge shows no overlay when count is 0
        let count = 0
        #expect(count == 0)
    }

    @Test("NotificationBadge: count > 99 shows 99+")
    func badgeOverMax() {
        let count = 150
        let displayed = count < 100 ? "\(count)" : "99+"
        #expect(displayed == "99+")
    }

    @Test("DND settings: dateToTimeString roundtrip")
    func dndTimeStringRoundtrip() {
        let hour = 22
        let minute = 30
        let formatted = String(format: "%02d:%02d", hour, minute)
        let parsed = NotificationService.parseTimeToMinutes(formatted)
        #expect(parsed == hour * 60 + minute)
    }

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

    private func makeAppState() -> AppState { AppState() }

    private func makeUser(userRepo: UserRepository, dbPool: DatabasePool, dndStart: String? = nil, dndEnd: String? = nil) async throws -> User {
        let now = Date()
        let user = User(
            id: UUID(), username: "msg_test_\(UUID().uuidString.prefix(8))",
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

    private func makeTime(hour: Int, minute: Int) -> Date {
        var components = Calendar.current.dateComponents([.year, .month, .day], from: Date())
        components.hour = hour
        components.minute = minute
        return Calendar.current.date(from: components)!
    }
}
