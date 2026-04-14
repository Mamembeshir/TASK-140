import Foundation
import GRDB
import SwiftUI

@Observable
final class MessagingCenterViewModel {
    var notifications: [ForgeNotification] = []
    var unreadCount: Int = 0
    var selectedEventType: NotificationEventType?
    var isLoading = false
    var errorMessage: String?

    private let notificationService: NotificationService
    private let dbPool: DatabasePool
    private let appState: AppState
    private var observationTask: Task<Void, Never>?

    var filteredNotifications: [ForgeNotification] {
        guard let filter = selectedEventType else { return notifications }
        return notifications.filter { $0.eventType == filter }
    }

    init(notificationService: NotificationService, dbPool: DatabasePool, appState: AppState) {
        self.notificationService = notificationService
        self.dbPool = dbPool
        self.appState = appState
    }

    func load() async {
        guard let userId = appState.currentUserId else { return }
        isLoading = true
        do {
            notifications = try await notificationService.listNotifications(userId: userId, actorId: userId)
            unreadCount = try await notificationService.getUnreadCount(userId: userId, actorId: userId)
        } catch {
            errorMessage = error.localizedDescription
        }
        isLoading = false
    }

    /// Starts a live ValueObservation so the inbox updates without manual refresh.
    func startObserving() {
        guard let userId = appState.currentUserId else { return }
        observationTask?.cancel()

        let observation = ValueObservation.tracking { db -> [ForgeNotification] in
            try ForgeNotification
                .filter(ForgeNotification.Columns.recipientId == userId.uuidString)
                .order(ForgeNotification.Columns.createdAt.desc)
                .fetchAll(db)
        }

        observationTask = Task { [weak self] in
            guard let self else { return }
            do {
                for try await notifs in observation.values(in: dbPool) {
                    await MainActor.run {
                        self.notifications = notifs
                        self.unreadCount = notifs.filter { $0.status == .delivered }.count
                    }
                }
            } catch { }
        }
    }

    func markSeen(_ notification: ForgeNotification) async {
        guard notification.status == .delivered,
              let userId = appState.currentUserId else { return }
        do {
            try await notificationService.markSeen(notification.id, actorId: userId)
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func markAllSeen() async {
        guard let userId = appState.currentUserId else { return }
        do {
            try await notificationService.bulkMarkSeen(userId: userId, actorId: userId)
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func releaseDND() async {
        guard let userId = appState.currentUserId else { return }
        try? await notificationService.releaseDNDHeld(userId: userId)
    }

    deinit {
        observationTask?.cancel()
    }
}
