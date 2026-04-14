import Foundation
import SwiftUI

@Observable
final class PluginEditorViewModel {
    var plugin: PluginDefinition?
    var fields: [PluginField] = []
    var isLoading = false
    var errorMessage: String?

    // Field editor state
    var newFieldName = ""
    var newFieldType: PluginFieldType = .text
    var newFieldUnit = ""
    var newFieldValidation = ""

    private let pluginService: PluginService
    private let appState: AppState

    init(pluginService: PluginService, appState: AppState) {
        self.pluginService = pluginService
        self.appState = appState
    }

    func load(pluginId: UUID) async {
        isLoading = true
        do {
            plugin = try await pluginService.getPlugin(pluginId)
            fields = try await pluginService.getFields(pluginId: pluginId)
        } catch {
            errorMessage = error.localizedDescription
        }
        isLoading = false
    }

    func addField() async {
        guard let pluginId = plugin?.id,
              let userId = appState.currentUserId,
              !newFieldName.isEmpty else { return }
        do {
            _ = try await pluginService.addField(
                pluginId: pluginId,
                fieldName: newFieldName,
                fieldType: newFieldType,
                unit: newFieldUnit.isEmpty ? nil : newFieldUnit,
                validationRules: newFieldValidation.isEmpty ? nil : newFieldValidation,
                actorId: userId
            )
            newFieldName = ""
            newFieldUnit = ""
            newFieldValidation = ""
            await load(pluginId: pluginId)
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func submitForApproval() async {
        guard let pluginId = plugin?.id,
              let userId = appState.currentUserId else { return }
        do {
            try await pluginService.submitForApproval(pluginId: pluginId, actorId: userId)
            await load(pluginId: pluginId)
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}
