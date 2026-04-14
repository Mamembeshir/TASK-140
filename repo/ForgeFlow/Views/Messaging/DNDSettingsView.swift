import SwiftUI

struct DNDSettingsView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(AppState.self) private var appState

    let authService: AuthService

    @State private var dndEnabled = false
    @State private var startTime = Date()
    @State private var endTime = Date()
    @State private var isSaving = false
    @State private var errorMessage: String?

    private let calendar = Calendar.current

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Toggle("Enable Quiet Hours", isOn: $dndEnabled)
                        .tint(Color("ForgeBlue"))
                } footer: {
                    Text("Notifications received during quiet hours will be held and delivered when quiet hours end.")
                        .font(.caption)
                }

                if dndEnabled {
                    Section("Quiet Hours") {
                        DatePicker("Start", selection: $startTime, displayedComponents: .hourAndMinute)
                        DatePicker("End", selection: $endTime, displayedComponents: .hourAndMinute)
                    }
                }

                if let error = errorMessage {
                    Section {
                        Text(error)
                            .font(.caption)
                            .foregroundStyle(Color("Danger"))
                    }
                }
            }
            .navigationTitle("Quiet Hours (DND)")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        Task { await save() }
                    }
                    .fontWeight(.bold)
                    .disabled(isSaving)
                }
            }
            .onAppear { loadCurrentSettings() }
        }
    }

    private func loadCurrentSettings() {
        guard let userId = appState.currentUserId else { return }
        Task {
            guard let user = try? await authService.getUser(actorId: userId, id: userId) else { return }
            await MainActor.run {
                if let startStr = user.dndStartTime, let endStr = user.dndEndTime,
                   let startDate = timeStringToDate(startStr),
                   let endDate = timeStringToDate(endStr) {
                    dndEnabled = true
                    startTime = startDate
                    endTime = endDate
                }
            }
        }
    }

    private func save() async {
        guard let userId = appState.currentUserId else { return }
        isSaving = true
        errorMessage = nil

        let startStr = dndEnabled ? dateToTimeString(startTime) : nil
        let endStr = dndEnabled ? dateToTimeString(endTime) : nil

        do {
            try await authService.updateDNDSettings(actorId: userId, userId: userId, startTime: startStr, endTime: endStr)
            dismiss()
        } catch {
            errorMessage = error.localizedDescription
        }
        isSaving = false
    }

    private func dateToTimeString(_ date: Date) -> String {
        let hour = calendar.component(.hour, from: date)
        let minute = calendar.component(.minute, from: date)
        return String(format: "%02d:%02d", hour, minute)
    }

    private func timeStringToDate(_ string: String) -> Date? {
        let parts = string.split(separator: ":").compactMap { Int(String($0)) }
        guard parts.count == 2 else { return nil }
        var components = calendar.dateComponents([.year, .month, .day], from: Date())
        components.hour = parts[0]
        components.minute = parts[1]
        return calendar.date(from: components)
    }
}
