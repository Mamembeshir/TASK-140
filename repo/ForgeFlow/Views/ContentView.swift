import SwiftUI

struct ContentView: View {
    @Environment(AppState.self) private var appState
    let authService: AuthService
    let postingService: PostingService
    let assignmentService: AssignmentService
    let taskService: TaskService
    let commentService: CommentService
    let attachmentService: AttachmentService
    let notificationService: NotificationService
    let pluginService: PluginService
    let syncService: SyncService

    var body: some View {
        ZStack {
            if appState.isAuthenticated {
                MainTabView(
                    authService: authService,
                    postingService: postingService,
                    assignmentService: assignmentService,
                    taskService: taskService,
                    commentService: commentService,
                    attachmentService: attachmentService,
                    notificationService: notificationService,
                    pluginService: pluginService,
                    syncService: syncService
                )
            }

            if !appState.isAuthenticated {
                LoginView(authService: authService, appState: appState)
                    .transition(.opacity)
            }

            if appState.isAuthenticated && appState.isLocked {
                LockScreenView(authService: authService, appState: appState)
                    .transition(.opacity)
            }
        }
        .trackingInteraction(appState: appState)
        .animation(.default, value: appState.isAuthenticated)
        .animation(.default, value: appState.isLocked)
    }
}
