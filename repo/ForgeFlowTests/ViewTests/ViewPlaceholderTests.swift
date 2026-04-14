import Foundation
import Testing
@testable import ForgeFlow

@Suite("View Tests")
struct ViewTests {
    @Test("AppState initializes in locked state")
    func appStateInitialState() {
        let appState = AppState()
        #expect(appState.isLocked == true)
        #expect(appState.isAuthenticated == false)
        #expect(appState.currentUserId == nil)
    }

    @Test("AppState login sets correct state")
    func appStateLogin() {
        let appState = AppState()
        let userId = UUID()
        appState.login(userId: userId, role: .admin)

        #expect(appState.isAuthenticated == true)
        #expect(appState.isLocked == false)
        #expect(appState.currentUserId == userId)
        #expect(appState.currentUserRole == .admin)
    }

    @Test("AppState logout resets state")
    func appStateLogout() {
        let appState = AppState()
        appState.login(userId: UUID(), role: .coordinator)
        appState.logout()

        #expect(appState.isAuthenticated == false)
        #expect(appState.isLocked == true)
        #expect(appState.currentUserId == nil)
    }
}
