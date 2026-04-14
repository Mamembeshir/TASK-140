import SwiftUI

struct UserManagementView: View {
    @Environment(AppState.self) private var appState
    @State private var viewModel: AdminViewModel

    init(authService: AuthService, appState: AppState) {
        _viewModel = State(initialValue: AdminViewModel(authService: authService, appState: appState))
    }

    var body: some View {
        Group {
            if viewModel.users.isEmpty && !viewModel.isLoading {
                EmptyStateView(
                    icon: "person.3",
                    heading: "No Users",
                    description: "Create user accounts to get started.",
                    actionTitle: "Add User",
                    action: { viewModel.showCreateSheet = true }
                )
            } else {
                List {
                    ForEach(viewModel.users) { user in
                        NavigationLink {
                            UserStoragePolicyView(user: user, authService: viewModel.authService, appState: appState)
                        } label: {
                            UserRow(user: user)
                        }
                        .swipeActions(edge: .trailing) {
                                if user.status == .active {
                                    Button("Deactivate") {
                                        Task { await viewModel.deactivateUser(userId: user.id) }
                                    }
                                    .tint(Color("Danger"))
                                } else if user.status == .deactivated {
                                    Button("Reactivate") {
                                        Task { await viewModel.reactivateUser(userId: user.id) }
                                    }
                                    .tint(Color("Success"))
                                }
                            }
                    }
                }
                .listStyle(.insetGrouped)
            }
        }
        .navigationTitle("User Management")
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button {
                    viewModel.showCreateSheet = true
                } label: {
                    Image(systemName: "plus")
                }
                .accessibilityLabel("Add User")
            }
        }
        .sheet(isPresented: $viewModel.showCreateSheet) {
            CreateUserSheet(viewModel: viewModel)
        }
        .task { await viewModel.loadUsers() }
    }
}

// MARK: - User Row

private struct UserRow: View {
    let user: User

    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: 4) {
                Text(user.username)
                    .font(.body)
                    .fontWeight(.medium)
                    .foregroundStyle(Color("TextPrimary"))

                Text(user.role.rawValue.capitalized)
                    .font(.caption)
                    .foregroundStyle(Color("TextSecondary"))
            }

            Spacer()

            statusBadge
        }
        .padding(.vertical, 4)
        .accessibilityElement(children: .combine)
    }

    @ViewBuilder
    private var statusBadge: some View {
        switch user.status {
        case .active:
            Text("Active")
                .font(.caption2).fontWeight(.bold)
                .foregroundStyle(Color("Success"))
                .padding(.horizontal, 8).padding(.vertical, 4)
                .background(Color("Success").opacity(0.15), in: Capsule())
        case .locked:
            Text("Locked")
                .font(.caption2).fontWeight(.bold)
                .foregroundStyle(Color("Warning"))
                .padding(.horizontal, 8).padding(.vertical, 4)
                .background(Color("Warning").opacity(0.15), in: Capsule())
        case .deactivated:
            Text("Deactivated")
                .font(.caption2).fontWeight(.bold)
                .foregroundStyle(Color("Danger"))
                .padding(.horizontal, 8).padding(.vertical, 4)
                .background(Color("Danger").opacity(0.15), in: Capsule())
        }
    }
}

// MARK: - Create User Sheet

private struct CreateUserSheet: View {
    @Bindable var viewModel: AdminViewModel
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            Form {
                Section("Account Details") {
                    TextField("Username *", text: $viewModel.newUsername)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()

                    SecureField("Password *", text: $viewModel.newPassword)
                }

                Section("Role") {
                    Picker("Role", selection: $viewModel.newRole) {
                        Text("Administrator").tag(Role.admin)
                        Text("Coordinator").tag(Role.coordinator)
                        Text("Technician").tag(Role.technician)
                    }
                    .pickerStyle(.inline)
                    .labelsHidden()
                }

                if let error = viewModel.errorMessage {
                    Section {
                        Text(error)
                            .font(.caption)
                            .foregroundStyle(Color("Danger"))
                    }
                }
            }
            .navigationTitle("New User")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Create") {
                        Task { await viewModel.createUser() }
                    }
                    .disabled(viewModel.newUsername.isEmpty || viewModel.newPassword.isEmpty || viewModel.isLoading)
                    .fontWeight(.bold)
                }
            }
        }
    }
}
