import Foundation
import SwiftUI

@Observable
final class PluginTestViewModel {
    var plugin: PluginDefinition?
    var testResults: [PluginTestResult] = []
    var availablePostings: [ServicePosting] = []
    var selectedPostingIds: Set<UUID> = []
    var isRunning = false
    var errorMessage: String?

    private let pluginService: PluginService
    private let postingService: PostingService
    private let appState: AppState

    init(pluginService: PluginService, postingService: PostingService, appState: AppState) {
        self.pluginService = pluginService
        self.postingService = postingService
        self.appState = appState
    }

    func load(pluginId: UUID) async {
        do {
            plugin = try await pluginService.getPlugin(pluginId)
            testResults = try await pluginService.getTestResults(pluginId: pluginId)
            // Derive role from actorId — not caller-supplied
            if let actorId = appState.currentUserId {
                availablePostings = try await postingService.listPostings(actorId: actorId)
            }
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func runTests() async {
        guard let pluginId = plugin?.id,
              let actorId = appState.currentUserId,
              !selectedPostingIds.isEmpty else { return }
        isRunning = true
        do {
            // Pass actorId for admin enforcement
            testResults = try await pluginService.testPlugin(
                pluginId: pluginId,
                samplePostingIds: Array(selectedPostingIds),
                actorId: actorId
            )
            plugin = try await pluginService.getPlugin(pluginId)
        } catch {
            errorMessage = error.localizedDescription
        }
        isRunning = false
    }

    func togglePosting(_ postingId: UUID) {
        if selectedPostingIds.contains(postingId) {
            selectedPostingIds.remove(postingId)
        } else {
            selectedPostingIds.insert(postingId)
        }
    }
}
