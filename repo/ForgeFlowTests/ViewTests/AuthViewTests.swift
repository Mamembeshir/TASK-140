import Foundation
import Testing
@testable import ForgeFlow

@Suite("Auth View Tests")
struct AuthViewTests {

    @Test("AppState starts locked and unauthenticated")
    func initialState() {
        let appState = AppState()
        #expect(appState.isLocked == true)
        #expect(appState.isAuthenticated == false)
        #expect(appState.hasPasswordAuthenticatedThisSession == false)
        #expect(appState.currentUserId == nil)
    }

    @Test("Login sets authenticated state with correct role")
    func loginSetsState() {
        let appState = AppState()
        let userId = UUID()
        appState.login(userId: userId, role: .coordinator)

        #expect(appState.isAuthenticated == true)
        #expect(appState.isLocked == false)
        #expect(appState.hasPasswordAuthenticatedThisSession == true)
        #expect(appState.currentUserId == userId)
        #expect(appState.currentUserRole == .coordinator)
    }

    @Test("Lock sets isLocked without clearing auth")
    func lockPreservesAuth() {
        let appState = AppState()
        appState.login(userId: UUID(), role: .admin)
        appState.lock()

        #expect(appState.isAuthenticated == true)
        #expect(appState.isLocked == true)
        #expect(appState.currentUserId != nil)
    }

    @Test("Unlock clears lock and records interaction")
    func unlockClearsLock() {
        let appState = AppState()
        appState.login(userId: UUID(), role: .admin)
        appState.lock()
        appState.unlock()

        #expect(appState.isLocked == false)
        #expect(appState.isAuthenticated == true)
    }

    @Test("Logout resets all auth state")
    func logoutResetsAll() {
        let appState = AppState()
        appState.login(userId: UUID(), role: .technician)
        appState.logout()

        #expect(appState.isAuthenticated == false)
        #expect(appState.isLocked == true)
        #expect(appState.hasPasswordAuthenticatedThisSession == false)
        #expect(appState.currentUserId == nil)
        #expect(appState.currentUserRole == nil)
    }

    @Test("AuthViewModel biometric failure count triggers password fallback")
    func biometricFailureFallback() async throws {
        let dbManager = try DatabaseManager(inMemory: true)
        let dbPool = dbManager.dbPool
        let userRepo = UserRepository(dbPool: dbPool)
        let auditService = AuditService(dbPool: dbPool)
        let authService = AuthService(dbPool: dbPool, userRepository: userRepo, auditService: auditService)
        let appState = AppState()

        let viewModel = await AuthViewModel(authService: authService, appState: appState)

        await MainActor.run {
            #expect(viewModel.showPasswordFallback == false)
            viewModel.biometricFailureCount = 3
            #expect(viewModel.showPasswordFallback == true)
        }
    }
}
