import Foundation
import BackgroundTasks
import os.log

enum OrphanCleanupTask {
    static let identifier = "com.forgeflow.app.orphan-cleanup"

    static func register() {
        BGTaskScheduler.shared.register(forTaskWithIdentifier: identifier, using: nil) { task in
            guard let processingTask = task as? BGProcessingTask else { return }
            handleTask(processingTask)
        }
    }

    static func schedule() {
        let request = BGProcessingTaskRequest(identifier: identifier)
        request.requiresNetworkConnectivity = false
        request.requiresExternalPower = false
        request.earliestBeginDate = Date(timeIntervalSinceNow: 24 * 3600) // daily

        try? BGTaskScheduler.shared.submit(request)
    }

    private static func handleTask(_ task: BGProcessingTask) {
        let dbPool = DatabaseManager.shared.dbPool
        let attachmentRepo = AttachmentRepository(dbPool: dbPool)
        let cleanupService = CleanupService(dbPool: dbPool, attachmentRepository: attachmentRepo)

        let cleanupTask = Task {
            do {
                ForgeLogger.background.info("OrphanCleanupTask: starting")
                let count = try await cleanupService.cleanOrphans()
                ForgeLogger.background.info("OrphanCleanupTask: removed \(count, privacy: .public) orphans")
                task.setTaskCompleted(success: true)
                // Reschedule
                schedule()
            } catch {
                ForgeLogger.background.error("OrphanCleanupTask: failed — \(error.localizedDescription, privacy: .public)")
                task.setTaskCompleted(success: false)
                schedule()
            }
        }

        task.expirationHandler = {
            cleanupTask.cancel()
        }
    }
}
