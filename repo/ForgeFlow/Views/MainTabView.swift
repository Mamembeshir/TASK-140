import SwiftUI
import GRDB

struct MainTabView: View {
    @State private var selectedTab: Tab? = .dashboard
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    @Environment(AppState.self) private var appState
    var authService: AuthService?
    var postingService: PostingService?
    var assignmentService: AssignmentService?
    var taskService: TaskService?
    var commentService: CommentService?
    var attachmentService: AttachmentService?
    var notificationService: NotificationService?
    var pluginService: PluginService?
    var syncService: SyncService?

    enum Tab: String, CaseIterable {
        case dashboard = "Dashboard"
        case postings = "Postings"
        case calendar = "Calendar"
        case messaging = "Messaging"
        case plugins = "Plugins"
        case sync = "Sync"

        var icon: String {
            switch self {
            case .dashboard: return "square.grid.2x2.fill"
            case .postings: return "doc.text.fill"
            case .calendar: return "calendar"
            case .messaging: return "bell.fill"
            case .plugins: return "puzzlepiece.extension.fill"
            case .sync: return "arrow.triangle.2.circlepath"
            }
        }

        /// Tabs visible based on role
        static func visibleTabs(for role: Role?) -> [Tab] {
            switch role {
            case .admin:
                return [.dashboard, .postings, .calendar, .messaging, .plugins, .sync]
            case .coordinator:
                return [.dashboard, .postings, .calendar, .messaging, .sync]
            default:
                return [.dashboard, .postings, .calendar, .messaging]
            }
        }
    }

    var body: some View {
        if horizontalSizeClass == .regular {
            iPadLayout
        } else {
            iPhoneLayout
        }
    }

    // MARK: - iPhone Layout (TabView)

    private var visibleTabs: [Tab] {
        Tab.visibleTabs(for: appState.currentUserRole)
    }

    private var iPhoneLayout: some View {
        TabView(selection: $selectedTab) {
            ForEach(visibleTabs, id: \.self) { tab in
                NavigationStack {
                    tabContent(for: tab)
                }
                .tabItem {
                    Label(tab.rawValue, systemImage: tab.icon)
                }
                .tag(tab)
            }
        }
        .tint(Color("ForgeBlue"))
    }

    // MARK: - iPad Layout (NavigationSplitView)

    private var iPadLayout: some View {
        NavigationSplitView {
            List(selection: $selectedTab) {
                ForEach(visibleTabs, id: \.self) { tab in
                    Label(tab.rawValue, systemImage: tab.icon)
                        .tag(tab)
                }
            }
            .navigationTitle("ForgeFlow")
            .listStyle(.sidebar)
        } detail: {
            NavigationStack {
                tabContent(for: selectedTab ?? .dashboard)
            }
        }
        .tint(Color("ForgeBlue"))
    }

    // MARK: - Tab Content

    @ViewBuilder
    private func tabContent(for tab: Tab) -> some View {
        switch tab {
        case .dashboard:
            DashboardPlaceholderView(authService: authService)
        case .postings:
            if let postingService, let assignmentService, let authService {
                PostingListView(
                    postingService: postingService,
                    assignmentService: assignmentService,
                    authService: authService,
                    appState: appState,
                    taskService: taskService,
                    commentService: commentService,
                    attachmentService: attachmentService,
                    pluginService: pluginService
                )
            } else {
                PostingsPlaceholderView()
            }
        case .calendar:
            if let postingService, let assignmentService, let authService, let taskService {
                CalendarTabView(
                    postingService: postingService,
                    assignmentService: assignmentService,
                    authService: authService,
                    taskService: taskService,
                    appState: appState
                )
            } else {
                CalendarPlaceholderView()
            }
        case .messaging:
            if let notificationService, let authService {
                MessagingCenterView(
                    notificationService: notificationService,
                    authService: authService,
                    dbPool: DatabaseManager.shared.dbPool,
                    appState: appState
                )
            } else {
                MessagingPlaceholderView()
            }
        case .plugins:
            if let pluginService, let postingService {
                PluginListView(pluginService: pluginService, postingService: postingService)
            } else {
                PluginsPlaceholderView()
            }
        case .sync:
            if let syncService, let postingService {
                SyncStatusView(syncService: syncService, postingService: postingService)
            } else {
                SyncPlaceholderView()
            }
        }
    }
}

// MARK: - Placeholder Views

struct PluginsPlaceholderView: View {
    var body: some View {
        EmptyStateView(
            icon: "puzzlepiece.extension",
            heading: "Plugins",
            description: "Manage plugins to extend ForgeFlow."
        )
        .navigationTitle("Plugins")
        .background(Color("SurfacePrimary"))
    }
}

struct SyncPlaceholderView: View {
    var body: some View {
        EmptyStateView(
            icon: "arrow.triangle.2.circlepath",
            heading: "Sync",
            description: "Export and import data for offline use."
        )
        .navigationTitle("Sync")
        .background(Color("SurfacePrimary"))
    }
}

struct DashboardPlaceholderView: View {
    @Environment(AppState.self) private var appState
    var authService: AuthService?

    var body: some View {
        EmptyStateView(
            icon: "square.grid.2x2",
            heading: "Dashboard",
            description: "Your work overview will appear here."
        )
        .navigationTitle("Dashboard")
        .background(Color("SurfacePrimary"))
        .toolbar {
            if appState.currentUserRole == .admin, let authService {
                ToolbarItem(placement: .primaryAction) {
                    NavigationLink {
                        UserManagementView(authService: authService, appState: appState)
                    } label: {
                        Image(systemName: "person.2.fill")
                    }
                    .accessibilityLabel("User Management")
                }
            }
            ToolbarItem(placement: .navigationBarLeading) {
                Button {
                    appState.logout()
                } label: {
                    Image(systemName: "rectangle.portrait.and.arrow.right")
                }
                .accessibilityLabel("Logout")
            }
        }
    }
}

struct PostingsPlaceholderView: View {
    var body: some View {
        EmptyStateView(
            icon: "doc.text",
            heading: "Service Postings",
            description: "Create and manage service postings.",
            actionTitle: "Create Posting",
            action: {}
        )
        .navigationTitle("Postings")
        .background(Color("SurfacePrimary"))
    }
}

struct CalendarPlaceholderView: View {
    var body: some View {
        EmptyStateView(
            icon: "calendar",
            heading: "Calendar",
            description: "View scheduled work by day, week, or month."
        )
        .navigationTitle("Calendar")
        .background(Color("SurfacePrimary"))
    }
}

struct MessagingPlaceholderView: View {
    var body: some View {
        EmptyStateView(
            icon: "bell",
            heading: "Messaging Center",
            description: "Notifications and messages will appear here."
        )
        .navigationTitle("Messaging")
        .background(Color("SurfacePrimary"))
    }
}

#Preview("iPhone") {
    MainTabView()
        .environment(AppState())
}

#Preview("iPad") {
    MainTabView()
        .environment(AppState())
}
