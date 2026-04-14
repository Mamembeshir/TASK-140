import SwiftUI

@main
struct ForgeFlowApp: App {
    @State private var appState = AppState()
    @Environment(\.scenePhase) private var scenePhase

    private let authService: AuthService
    private let postingService: PostingService
    private let assignmentService: AssignmentService
    private let taskService: TaskService
    private let commentService: CommentService
    private let attachmentService: AttachmentService
    private let notificationService: NotificationService
    private let pluginService: PluginService
    private let syncService: SyncService

    init() {
        let dbPool = DatabaseManager.shared.dbPool
        let userRepository = UserRepository(dbPool: dbPool)
        let auditService = AuditService(dbPool: dbPool)
        let postingRepository = PostingRepository(dbPool: dbPool)
        let assignmentRepository = AssignmentRepository(dbPool: dbPool)
        let taskRepository = TaskRepository(dbPool: dbPool)
        let dependencyRepository = DependencyRepository(dbPool: dbPool)
        let commentRepository = CommentRepository(dbPool: dbPool)
        let attachmentRepository = AttachmentRepository(dbPool: dbPool)
        let notificationRepository = NotificationRepository(dbPool: dbPool)

        let notifService = NotificationService(
            dbPool: dbPool, notificationRepository: notificationRepository,
            userRepository: userRepository
        )
        self.notificationService = notifService

        self.authService = AuthService(
            dbPool: dbPool, userRepository: userRepository, auditService: auditService
        )

        let pluginRepo = PluginRepository(dbPool: dbPool)
        let pluginSvc = PluginService(
            dbPool: dbPool, pluginRepository: pluginRepo,
            postingRepository: postingRepository, auditService: auditService,
            notificationService: notifService,
            userRepository: userRepository
        )
        self.pluginService = pluginSvc

        let postService = PostingService(
            dbPool: dbPool, postingRepository: postingRepository,
            taskRepository: taskRepository, userRepository: userRepository,
            auditService: auditService,
            notificationService: notifService,
            assignmentRepository: assignmentRepository,
            pluginService: pluginSvc
        )
        self.postingService = postService

        self.assignmentService = AssignmentService(
            dbPool: dbPool, assignmentRepository: assignmentRepository,
            postingRepository: postingRepository, userRepository: userRepository,
            auditService: auditService, notificationService: notifService
        )
        self.taskService = TaskService(
            dbPool: dbPool, taskRepository: taskRepository,
            dependencyRepository: dependencyRepository,
            postingRepository: postingRepository, auditService: auditService,
            notificationService: notifService,
            postingService: postService,
            userRepository: userRepository
        )
        self.commentService = CommentService(
            dbPool: dbPool, commentRepository: commentRepository, auditService: auditService,
            notificationService: notifService,
            postingRepository: postingRepository,
            assignmentRepository: assignmentRepository,
            userRepository: userRepository
        )
        self.attachmentService = AttachmentService(
            dbPool: dbPool, attachmentRepository: attachmentRepository, auditService: auditService,
            userRepository: userRepository, postingRepository: postingRepository,
            assignmentRepository: assignmentRepository
        )

        let syncRepo = SyncRepository(dbPool: dbPool)
        self.syncService = SyncService(
            dbPool: dbPool, syncRepository: syncRepo,
            postingRepository: postingRepository, auditService: auditService,
            taskRepository: taskRepository, assignmentRepository: assignmentRepository,
            commentRepository: commentRepository, dependencyRepository: dependencyRepository,
            userRepository: userRepository
        )

        // Register background tasks
        OrphanCleanupTask.register()
        ImageCompressionTask.register()
        CacheEvictionTask.register()
        FileChunkingTask.register()
    }

    var body: some Scene {
        WindowGroup {
            ContentView(
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
            .environment(appState)
            .onAppear {
                #if DEBUG
                Task {
                    try? await Seeder.seedIfNeeded(dbPool: DatabaseManager.shared.dbPool)
                }
                #endif
                OrphanCleanupTask.schedule()
                ImageCompressionTask.schedule()
                CacheEvictionTask.schedule()
                FileChunkingTask.schedule()
            }
            .onChange(of: scenePhase) { _, newPhase in
                appState.handleScenePhase(newPhase)
                // Release DND-held notifications when app returns to foreground
                if newPhase == .active, let userId = appState.currentUserId {
                    Task { try? await notificationService.releaseDNDHeld(userId: userId) }
                }
            }
        }
    }
}
