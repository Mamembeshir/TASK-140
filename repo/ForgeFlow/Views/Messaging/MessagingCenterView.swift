import SwiftUI
import GRDB

struct MessagingCenterView: View {
    @State private var viewModel: MessagingCenterViewModel
    @State private var showingDNDSettings = false
    @Environment(AppState.self) private var appState

    let notificationService: NotificationService
    let authService: AuthService
    let dbPool: DatabasePool

    init(notificationService: NotificationService, authService: AuthService, dbPool: DatabasePool, appState: AppState) {
        _viewModel = State(initialValue: MessagingCenterViewModel(
            notificationService: notificationService,
            dbPool: dbPool,
            appState: appState
        ))
        self.notificationService = notificationService
        self.authService = authService
        self.dbPool = dbPool
    }

    var body: some View {
        Group {
            if viewModel.filteredNotifications.isEmpty && !viewModel.isLoading {
                EmptyStateView(
                    icon: "bell.slash",
                    heading: "No Notifications",
                    description: "You're all caught up."
                )
            } else {
                List {
                    ForEach(viewModel.filteredNotifications) { notification in
                        NotificationRowView(notification: notification) {
                            Task { await viewModel.markSeen(notification) }
                        }
                    }
                }
                .listStyle(.insetGrouped)
            }
        }
        .navigationTitle("Messaging Center")
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                if viewModel.unreadCount > 0 {
                    Button("Mark All Seen") {
                        Task { await viewModel.markAllSeen() }
                    }
                    .font(.subheadline)
                }
            }
            ToolbarItem(placement: .secondaryAction) {
                Menu {
                    Button("All") { viewModel.selectedEventType = nil }
                    Divider()
                    ForEach(NotificationEventType.allCases, id: \.self) { type in
                        Button(type.displayName) { viewModel.selectedEventType = type }
                    }
                } label: {
                    Label("Filter", systemImage: "line.3.horizontal.decrease.circle")
                }
            }
            ToolbarItem(placement: .secondaryAction) {
                Button {
                    showingDNDSettings = true
                } label: {
                    Label("Quiet Hours", systemImage: "moon.fill")
                }
            }
        }
        .task {
            await viewModel.load()
            viewModel.startObserving()
        }
        .refreshable {
            await viewModel.load()
        }
        .sheet(isPresented: $showingDNDSettings) {
            DNDSettingsView(authService: authService)
        }
        .alert("Error", isPresented: .constant(viewModel.errorMessage != nil)) {
            Button("OK") { viewModel.errorMessage = nil }
        } message: {
            Text(viewModel.errorMessage ?? "")
        }
    }
}
