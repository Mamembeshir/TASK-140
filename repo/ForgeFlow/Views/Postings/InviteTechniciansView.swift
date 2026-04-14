import SwiftUI

struct InviteTechniciansView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var technicians: [User] = []
    @State private var selectedIds: Set<UUID> = []
    @State private var isLoading = false
    @State private var errorMessage: String?

    private let assignmentService: AssignmentService
    private let authService: AuthService
    private let postingId: UUID
    private let appState: AppState

    init(assignmentService: AssignmentService, authService: AuthService,
         postingId: UUID, appState: AppState) {
        self.assignmentService = assignmentService
        self.authService = authService
        self.postingId = postingId
        self.appState = appState
    }

    var body: some View {
        List {
            if technicians.isEmpty && !isLoading {
                Text("No active technicians available.")
                    .font(.subheadline)
                    .foregroundStyle(Color("TextTertiary"))
            } else {
                ForEach(technicians) { tech in
                    Button {
                        if selectedIds.contains(tech.id) {
                            selectedIds.remove(tech.id)
                        } else {
                            selectedIds.insert(tech.id)
                        }
                    } label: {
                        HStack {
                            Text(tech.username)
                                .foregroundStyle(Color("TextPrimary"))
                            Spacer()
                            if selectedIds.contains(tech.id) {
                                Image(systemName: "checkmark.circle.fill")
                                    .foregroundStyle(Color("ForgeBlue"))
                            } else {
                                Image(systemName: "circle")
                                    .foregroundStyle(Color("BorderDefault"))
                            }
                        }
                    }
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
        .navigationTitle("Invite Technicians")
        .toolbar {
            ToolbarItem(placement: .confirmationAction) {
                Button("Send Invites") {
                    Task { await sendInvites() }
                }
                .disabled(selectedIds.isEmpty || isLoading)
                .fontWeight(.bold)
            }
        }
        .task { await loadTechnicians() }
    }

    private func loadTechnicians() async {
        isLoading = true
        do {
            guard let actorId = appState.currentUserId else { return }
            technicians = try await authService.listActiveTechnicians(actorId: actorId)
        } catch {
            errorMessage = error.localizedDescription
        }
        isLoading = false
    }

    private func sendInvites() async {
        guard let actorId = appState.currentUserId else { return }
        isLoading = true
        errorMessage = nil
        do {
            _ = try await assignmentService.invite(
                actorId: actorId,
                postingId: postingId,
                technicianIds: Array(selectedIds)
            )
            dismiss()
        } catch {
            errorMessage = error.localizedDescription
            isLoading = false
        }
    }
}
