import Foundation
import SwiftUI

/// Global app state tracking inactivity timer and authentication state.
@Observable
final class AppState {
    /// Whether the user is currently authenticated
    var isAuthenticated = false

    /// Whether the app is locked due to inactivity
    var isLocked = true

    /// Whether the user has completed initial password login this session
    var hasPasswordAuthenticatedThisSession = false

    /// The currently logged-in user's ID
    var currentUserId: UUID?

    /// The currently logged-in user's role
    var currentUserRole: Role?

    /// The currently logged-in user's username (used for watermark stamping)
    var currentUsername: String?

    /// Timestamp of last user interaction
    private(set) var lastInteractionTime = Date()

    /// Inactivity timeout duration (5 minutes)
    private let inactivityTimeout: TimeInterval = 5 * 60

    /// Timer for checking inactivity
    private var inactivityTimer: Timer?

    /// Updates the last interaction timestamp. Call on user taps/scrolls.
    func recordInteraction() {
        lastInteractionTime = Date()
    }

    /// Starts the inactivity monitoring timer.
    func startInactivityMonitoring() {
        inactivityTimer?.invalidate()
        inactivityTimer = Timer.scheduledTimer(withTimeInterval: 30, repeats: true) { [weak self] _ in
            self?.checkInactivity()
        }
    }

    /// Stops the inactivity monitoring timer.
    func stopInactivityMonitoring() {
        inactivityTimer?.invalidate()
        inactivityTimer = nil
    }

    /// Checks if the inactivity timeout has been exceeded.
    private func checkInactivity() {
        guard isAuthenticated, !isLocked else { return }
        let elapsed = Date().timeIntervalSince(lastInteractionTime)
        if elapsed >= inactivityTimeout {
            lock()
        }
    }

    /// Handles scene phase changes.
    func handleScenePhase(_ phase: ScenePhase) {
        switch phase {
        case .active:
            checkInactivity()
        case .inactive, .background:
            if isAuthenticated {
                let elapsed = Date().timeIntervalSince(lastInteractionTime)
                if elapsed >= inactivityTimeout {
                    lock()
                }
            }
        @unknown default:
            break
        }
    }

    /// Locks the app, requiring re-authentication.
    func lock() {
        isLocked = true
    }

    /// Unlocks the app after successful authentication.
    func unlock() {
        isLocked = false
        recordInteraction()
    }

    /// Logs out the current user completely.
    func logout() {
        isAuthenticated = false
        isLocked = true
        hasPasswordAuthenticatedThisSession = false
        currentUserId = nil
        currentUserRole = nil
        currentUsername = nil
        stopInactivityMonitoring()
    }

    /// Completes login for a user.
    func login(userId: UUID, role: Role, username: String = "") {
        currentUserId = userId
        currentUserRole = role
        currentUsername = username
        isAuthenticated = true
        isLocked = false
        hasPasswordAuthenticatedThisSession = true
        recordInteraction()
        startInactivityMonitoring()
    }
}
