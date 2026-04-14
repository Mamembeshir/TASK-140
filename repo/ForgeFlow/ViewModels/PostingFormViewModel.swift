import Foundation
import SwiftUI

@Observable
final class PostingFormViewModel {
    var title = ""
    var siteAddress = ""
    var dueDate = Date().addingTimeInterval(86400 * 7)
    var budgetDollars = ""
    var acceptanceMode: AcceptanceMode = .inviteOnly
    var watermarkEnabled = false
    var isLoading = false
    var errorMessage: String?

    // Plugin custom fields loaded from active plugins
    var activePluginFields: [(plugin: PluginDefinition, fields: [PluginField])] = []
    var pluginFieldValues: [UUID: String] = [:]

    private let postingService: PostingService
    private let pluginService: PluginService?
    private let appState: AppState

    init(postingService: PostingService, appState: AppState, pluginService: PluginService? = nil) {
        self.postingService = postingService
        self.appState = appState
        self.pluginService = pluginService
    }

    var budgetCents: Int {
        let cleaned = budgetDollars.replacingOccurrences(of: ",", with: "")
        guard let dollars = Double(cleaned) else { return 0 }
        return Int(dollars * 100)
    }

    var pluginValidationErrors: [String] {
        guard let ps = pluginService else { return [] }
        return activePluginFields.flatMap { group in
            ps.validateFieldValues(fields: group.fields, values: pluginFieldValues)
        }
    }

    var isValid: Bool {
        !title.trimmingCharacters(in: .whitespaces).isEmpty
            && !siteAddress.trimmingCharacters(in: .whitespaces).isEmpty
            && dueDate > Date()
            && budgetCents > 0
            && pluginValidationErrors.isEmpty
    }

    func loadPluginFields() async {
        guard let ps = pluginService else { return }
        do {
            activePluginFields = try await ps.getActivePluginsWithFields()
        } catch {
            // Non-fatal: proceed without plugin fields if load fails
        }
    }

    func createPosting() async -> ServicePosting? {
        guard let actorId = appState.currentUserId else { return nil }
        isLoading = true
        errorMessage = nil

        do {
            let posting = try await postingService.create(
                actorId: actorId,
                title: title.trimmingCharacters(in: .whitespaces),
                siteAddress: siteAddress.trimmingCharacters(in: .whitespaces),
                dueDate: dueDate,
                budgetCents: budgetCents,
                acceptanceMode: acceptanceMode,
                watermarkEnabled: watermarkEnabled
            )
            // Persist plugin custom field values for this posting
            if let ps = pluginService {
                for (fieldId, value) in pluginFieldValues where !value.isEmpty {
                    try await ps.setFieldValue(
                        postingId: posting.id,
                        pluginFieldId: fieldId,
                        value: value,
                        actorId: actorId
                    )
                }
            }
            await MainActor.run { resetForm() }
            return posting
        } catch {
            await MainActor.run {
                errorMessage = error.localizedDescription
                isLoading = false
            }
            return nil
        }
    }

    func resetForm() {
        title = ""
        siteAddress = ""
        dueDate = Date().addingTimeInterval(86400 * 7)
        budgetDollars = ""
        acceptanceMode = .inviteOnly
        watermarkEnabled = false
        errorMessage = nil
        isLoading = false
        pluginFieldValues = [:]
        activePluginFields = []
    }
}
