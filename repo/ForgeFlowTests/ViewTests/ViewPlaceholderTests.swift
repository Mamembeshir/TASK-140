import Foundation
import Testing
@testable import ForgeFlow

// MARK: - AppState State Machine Tests

@Suite("AppState")
struct AppStateTests {

    // MARK: Initial state

    @Test func initialStateIsLockedAndUnauthenticated() {
        let state = AppState()
        #expect(state.isLocked == true)
        #expect(state.isAuthenticated == false)
        #expect(state.currentUserId == nil)
        #expect(state.currentUserRole == nil)
        #expect(state.currentUsername == nil)
        #expect(state.hasPasswordAuthenticatedThisSession == false)
    }

    // MARK: login()

    @Test func loginSetsAuthenticatedAndUnlocked() {
        let state = AppState()
        let userId = UUID()
        state.login(userId: userId, role: .admin)

        #expect(state.isAuthenticated == true)
        #expect(state.isLocked == false)
    }

    @Test func loginStoresUserId() {
        let state = AppState()
        let userId = UUID()
        state.login(userId: userId, role: .technician)
        #expect(state.currentUserId == userId)
    }

    @Test func loginStoresRole() {
        let state = AppState()
        state.login(userId: UUID(), role: .coordinator)
        #expect(state.currentUserRole == .coordinator)
    }

    @Test func loginStoresUsername() {
        let state = AppState()
        state.login(userId: UUID(), role: .admin, username: "alice")
        #expect(state.currentUsername == "alice")
    }

    @Test func loginSetsPasswordAuthFlag() {
        let state = AppState()
        state.login(userId: UUID(), role: .admin)
        #expect(state.hasPasswordAuthenticatedThisSession == true)
    }

    @Test func loginUpdatesInteractionTime() {
        let state = AppState()
        let before = state.lastInteractionTime
        // Small delay to guarantee time advances
        Thread.sleep(forTimeInterval: 0.01)
        state.login(userId: UUID(), role: .admin)
        #expect(state.lastInteractionTime >= before)
    }

    // MARK: logout()

    @Test func logoutClearsAuthentication() {
        let state = AppState()
        state.login(userId: UUID(), role: .admin)
        state.logout()
        #expect(state.isAuthenticated == false)
    }

    @Test func logoutLocksApp() {
        let state = AppState()
        state.login(userId: UUID(), role: .admin)
        state.logout()
        #expect(state.isLocked == true)
    }

    @Test func logoutClearsUserId() {
        let state = AppState()
        state.login(userId: UUID(), role: .admin)
        state.logout()
        #expect(state.currentUserId == nil)
    }

    @Test func logoutClearsRole() {
        let state = AppState()
        state.login(userId: UUID(), role: .coordinator)
        state.logout()
        #expect(state.currentUserRole == nil)
    }

    @Test func logoutClearsUsername() {
        let state = AppState()
        state.login(userId: UUID(), role: .admin, username: "bob")
        state.logout()
        #expect(state.currentUsername == nil)
    }

    @Test func logoutClearsPasswordAuthFlag() {
        let state = AppState()
        state.login(userId: UUID(), role: .admin)
        state.logout()
        #expect(state.hasPasswordAuthenticatedThisSession == false)
    }

    // MARK: lock() / unlock()

    @Test func lockSetsLockedTrue() {
        let state = AppState()
        state.login(userId: UUID(), role: .admin) // unlocks it
        state.lock()
        #expect(state.isLocked == true)
    }

    @Test func unlockSetsLockedFalse() {
        let state = AppState()
        // Starts locked; unlock it
        state.unlock()
        #expect(state.isLocked == false)
    }

    @Test func unlockUpdatesInteractionTime() {
        let state = AppState()
        let before = state.lastInteractionTime
        Thread.sleep(forTimeInterval: 0.01)
        state.unlock()
        #expect(state.lastInteractionTime >= before)
    }

    @Test func lockDoesNotAffectAuthentication() {
        let state = AppState()
        state.login(userId: UUID(), role: .admin)
        state.lock()
        // Authentication status is independent of lock
        #expect(state.isAuthenticated == true)
        #expect(state.isLocked == true)
    }

    // MARK: recordInteraction()

    @Test func recordInteractionUpdatesTimestamp() {
        let state = AppState()
        let before = state.lastInteractionTime
        Thread.sleep(forTimeInterval: 0.01)
        state.recordInteraction()
        #expect(state.lastInteractionTime > before)
    }

    // MARK: handleScenePhase()

    @Test func handleScenePhaseActiveDoesNotLockFreshSession() {
        let state = AppState()
        state.login(userId: UUID(), role: .admin)
        // Immediately check active phase — interaction time is fresh, should stay unlocked
        state.handleScenePhase(.active)
        #expect(state.isLocked == false)
    }

    @Test func handleScenePhaseBackgroundDoesNotLockFreshSession() {
        let state = AppState()
        state.login(userId: UUID(), role: .admin)
        state.handleScenePhase(.background)
        #expect(state.isLocked == false)
    }

    @Test func handleScenePhaseBeginsNoLockWhenUnauthenticated() {
        let state = AppState()
        // Not authenticated — phase changes should be no-ops
        state.handleScenePhase(.background)
        state.handleScenePhase(.inactive)
        state.handleScenePhase(.active)
        #expect(state.isLocked == true)   // still locked from initial state
        #expect(state.isAuthenticated == false)
    }

    // MARK: Inactivity monitoring lifecycle

    @Test func startAndStopMonitoringDoesNotCrash() {
        let state = AppState()
        state.startInactivityMonitoring()
        state.stopInactivityMonitoring()
        // If we get here without a crash, monitoring starts and stops cleanly
    }

    @Test func logoutStopsMonitoringWithoutCrash() {
        let state = AppState()
        state.login(userId: UUID(), role: .admin) // starts monitoring
        state.logout()                             // stops it
        // Calling logout a second time should not crash (double-stop guard)
        state.logout()
    }

    // MARK: Role-based checks

    @Test func loginWithAdminRole() {
        let state = AppState()
        state.login(userId: UUID(), role: .admin)
        #expect(state.currentUserRole == .admin)
    }

    @Test func loginWithTechnicianRole() {
        let state = AppState()
        state.login(userId: UUID(), role: .technician)
        #expect(state.currentUserRole == .technician)
    }

    @Test func loginWithCoordinatorRole() {
        let state = AppState()
        state.login(userId: UUID(), role: .coordinator)
        #expect(state.currentUserRole == .coordinator)
    }

    // MARK: Sequential state transitions

    @Test func loginThenLogoutThenLoginAgain() {
        let state = AppState()
        let id1 = UUID()
        let id2 = UUID()

        state.login(userId: id1, role: .admin)
        #expect(state.currentUserId == id1)

        state.logout()
        #expect(state.currentUserId == nil)

        state.login(userId: id2, role: .technician)
        #expect(state.currentUserId == id2)
        #expect(state.currentUserRole == .technician)
        #expect(state.isAuthenticated == true)
    }

    @Test func lockUnlockDoesNotChangeAuthStatus() {
        let state = AppState()
        state.login(userId: UUID(), role: .admin)
        state.lock()
        state.unlock()
        #expect(state.isAuthenticated == true)
    }
}
