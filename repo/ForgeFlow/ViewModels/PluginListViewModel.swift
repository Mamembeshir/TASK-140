import Foundation
import SwiftUI

@Observable
final class PluginListViewModel {
    var plugins: [PluginDefinition] = []
    var isLoading = false
    var errorMessage: String?

    private let pluginService: PluginService
    private let appState: AppState

    init(pluginService: PluginService, appState: AppState) {
        self.pluginService = pluginService
        self.appState = appState
    }

    func load() async {
        isLoading = true
        do {
            plugins = try await pluginService.listAll()
        } catch {
            errorMessage = error.localizedDescription
        }
        isLoading = false
    }

    func createPlugin(name: String, description: String, category: String) async {
        guard let userId = appState.currentUserId else { return }
        do {
            _ = try await pluginService.create(
                name: name, description: description,
                category: category, createdBy: userId
            )
            await load()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func activate(pluginId: UUID) async {
        guard let userId = appState.currentUserId else { return }
        do {
            try await pluginService.activate(pluginId: pluginId, actorId: userId)
            await load()
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}
