import Foundation
import SwiftUI

@Observable
final class PluginApprovalViewModel {
    var plugin: PluginDefinition?
    var fields: [PluginField] = []
    var testResults: [PluginTestResult] = []
    var approvals: [PluginApproval] = []
    var isLoading = false
    var errorMessage: String?

    private let pluginService: PluginService
    private let appState: AppState

    init(pluginService: PluginService, appState: AppState) {
        self.pluginService = pluginService
        self.appState = appState
    }

    var currentStep: Int {
        if approvals.contains(where: { $0.step == 1 }) { return 2 }
        return 1
    }

    var canApprove: Bool {
        guard let userId = appState.currentUserId,
              plugin?.status == .pendingApproval else { return false }
        // Can't approve if same admin already did step 1
        if currentStep == 2,
           let step1 = approvals.first(where: { $0.step == 1 }),
           step1.approverId == userId {
            return false
        }
        return !approvals.contains(where: { $0.step == currentStep })
    }

    func load(pluginId: UUID) async {
        isLoading = true
        do {
            plugin = try await pluginService.getPlugin(pluginId)
            fields = try await pluginService.getFields(pluginId: pluginId)
            testResults = try await pluginService.getTestResults(pluginId: pluginId)
            approvals = try await pluginService.getApprovals(pluginId: pluginId)
        } catch {
            errorMessage = error.localizedDescription
        }
        isLoading = false
    }

    func approve(notes: String?) async {
        guard let pluginId = plugin?.id,
              let userId = appState.currentUserId else { return }
        do {
            try await pluginService.approveStep(
                pluginId: pluginId,
                approverId: userId,
                step: currentStep,
                decision: .approved,
                notes: notes
            )
            await load(pluginId: pluginId)
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func reject(notes: String?) async {
        guard let pluginId = plugin?.id,
              let userId = appState.currentUserId else { return }
        do {
            try await pluginService.approveStep(
                pluginId: pluginId,
                approverId: userId,
                step: currentStep,
                decision: .rejected,
                notes: notes
            )
            await load(pluginId: pluginId)
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}
