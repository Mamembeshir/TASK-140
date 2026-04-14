import SwiftUI

struct UserStoragePolicyView: View {
    let user: User
    let authService: AuthService
    @Environment(AppState.self) private var appState
    @State private var quotaGB: Double
    @State private var isSaving = false
    @State private var successMessage: String?
    @State private var errorMessage: String?

    init(user: User, authService: AuthService, appState: AppState) {
        self.user = user
        self.authService = authService
        _quotaGB = State(initialValue: Double(user.storageQuotaBytes) / (1024 * 1024 * 1024))
    }

    var body: some View {
        List {
            Section("User Info") {
                LabeledContent("Username", value: user.username)
                LabeledContent("Role", value: user.role.rawValue.capitalized)
                LabeledContent("Status", value: user.status.rawValue.capitalized)
            }

            Section("Storage Policy") {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Storage Quota")
                        .font(.subheadline.weight(.medium))
                    HStack {
                        Slider(value: $quotaGB, in: 0.5...10, step: 0.5)
                        Text(String(format: "%.1f GB", quotaGB))
                            .font(.subheadline.monospaced())
                            .frame(width: 60, alignment: .trailing)
                    }
                    Text("Current: \(formatBytes(user.storageQuotaBytes))")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Button {
                    Task { await saveQuota() }
                } label: {
                    HStack {
                        if isSaving { ProgressView().padding(.trailing, 4) }
                        Text("Update Quota")
                            .fontWeight(.semibold)
                    }
                }
                .disabled(isSaving)
            }

            if let msg = successMessage {
                Section {
                    Label(msg, systemImage: "checkmark.circle.fill")
                        .foregroundStyle(.green)
                        .font(.subheadline)
                }
            }

            if let err = errorMessage {
                Section {
                    Text(err).font(.caption).foregroundStyle(.red)
                }
            }
        }
        .navigationTitle("Storage Policy")
        .navigationBarTitleDisplayMode(.inline)
    }

    private func saveQuota() async {
        guard let actorId = appState.currentUserId else { return }
        isSaving = true
        errorMessage = nil
        successMessage = nil
        do {
            let quotaBytes = Int(quotaGB * 1024 * 1024 * 1024)
            _ = try await authService.updateStorageQuota(
                actorId: actorId, userId: user.id, quotaBytes: quotaBytes
            )
            successMessage = "Quota updated to \(formatBytes(quotaBytes))"
        } catch {
            errorMessage = error.localizedDescription
        }
        isSaving = false
    }

    private func formatBytes(_ bytes: Int) -> String {
        let gb = Double(bytes) / (1024 * 1024 * 1024)
        return String(format: "%.1f GB", gb)
    }
}
