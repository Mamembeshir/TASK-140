import Foundation
import SwiftUI

@Observable
final class AdminViewModel {
    var users: [User] = []
    var isLoading = false
    var errorMessage: String?

    // Create user form
    var newUsername = ""
    var newPassword = ""
    var newRole: Role = .technician
    var showCreateSheet = false

    let authService: AuthService
    private let appState: AppState

    init(authService: AuthService, appState: AppState) {
        self.authService = authService
        self.appState = appState
    }

    func loadUsers() async {
        isLoading = true
        do {
            guard let actorId = appState.currentUserId else { return }
            users = try await authService.listUsers(actorId: actorId)
        } catch {
            errorMessage = error.localizedDescription
        }
        isLoading = false
    }

    func createUser() async {
        guard let actorId = appState.currentUserId else { return }
        isLoading = true
        errorMessage = nil

        do {
            _ = try await authService.createUser(
                actorId: actorId,
                username: newUsername,
                password: newPassword,
                role: newRole
            )
            resetCreateForm()
            showCreateSheet = false
            await loadUsers()
        } catch {
            errorMessage = error.localizedDescription
            isLoading = false
        }
    }

    func deactivateUser(userId: UUID) async {
        guard let actorId = appState.currentUserId else { return }
        do {
            _ = try await authService.updateUserStatus(actorId: actorId, userId: userId, status: .deactivated)
            await loadUsers()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func reactivateUser(userId: UUID) async {
        guard let actorId = appState.currentUserId else { return }
        do {
            _ = try await authService.updateUserStatus(actorId: actorId, userId: userId, status: .active)
            await loadUsers()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func resetCreateForm() {
        newUsername = ""
        newPassword = ""
        newRole = .technician
        errorMessage = nil
    }
}
