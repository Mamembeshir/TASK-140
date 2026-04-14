import Foundation
import SwiftUI

@Observable
final class AuthViewModel {
    var username = ""
    var password = ""
    var errorMessage: String?
    var isLoading = false

    // Biometric state
    var biometricType: BiometricHelper.BiometricType = .none
    var biometricFailureCount = 0
    var showPasswordFallback: Bool { biometricFailureCount >= 3 }

    private let authService: AuthService
    private let appState: AppState

    init(authService: AuthService, appState: AppState) {
        self.authService = authService
        self.appState = appState
    }

    // MARK: - Login (for LoginView)

    func login() async {
        guard !username.isEmpty, !password.isEmpty else {
            errorMessage = "Username and password are required."
            return
        }

        isLoading = true
        errorMessage = nil

        do {
            let user = try await authService.login(username: username, password: password)
            await MainActor.run {
                appState.login(userId: user.id, role: user.role, username: user.username)
                resetForm()
            }
        } catch {
            await MainActor.run {
                errorMessage = error.localizedDescription
                isLoading = false
            }
        }
    }

    // MARK: - Biometric Unlock (for LockScreenView)

    func biometricUnlock() async {
        guard let userId = appState.currentUserId else { return }

        do {
            _ = try await authService.biometricUnlock(userId: userId)
            await MainActor.run {
                appState.unlock()
                biometricFailureCount = 0
            }
        } catch {
            await MainActor.run {
                biometricFailureCount += 1
                if biometricFailureCount >= 3 {
                    errorMessage = "Biometric failed. Please enter your password."
                } else {
                    errorMessage = error.localizedDescription
                }
            }
        }
    }

    // MARK: - Password Unlock (for LockScreenView)

    func passwordUnlock() async {
        guard !password.isEmpty else {
            errorMessage = "Password is required."
            return
        }
        guard let userId = appState.currentUserId else { return }

        isLoading = true
        errorMessage = nil

        do {
            _ = try await authService.passwordUnlock(userId: userId, password: password)
            await MainActor.run {
                appState.unlock()
                appState.hasPasswordAuthenticatedThisSession = true
                biometricFailureCount = 0
                resetForm()
            }
        } catch {
            await MainActor.run {
                errorMessage = error.localizedDescription
                isLoading = false
            }
        }
    }

    // MARK: - Helpers

    func checkBiometricAvailability() {
        biometricType = BiometricHelper.availableBiometricType()
    }

    func resetForm() {
        username = ""
        password = ""
        errorMessage = nil
        isLoading = false
    }
}
