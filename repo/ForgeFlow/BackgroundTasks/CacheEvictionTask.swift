import BackgroundTasks
import Foundation
import GRDB
import os.log

enum CacheEvictionTask {
    static let identifier = "com.forgeflow.app.cache-eviction"

    /// Retention window: postings older than 90 days without active assignments are evicted.
    static let retentionDays: Int = 90

    static func register() {
        BGTaskScheduler.shared.register(forTaskWithIdentifier: identifier, using: nil) { task in
            guard let processingTask = task as? BGProcessingTask else { return }
            handleTask(processingTask)
        }
    }

    static func schedule() {
        let request = BGProcessingTaskRequest(identifier: identifier)
        request.earliestBeginDate = Date(timeIntervalSinceNow: 12 * 3600) // 12 hours
        request.requiresExternalPower = false
        request.requiresNetworkConnectivity = false
        try? BGTaskScheduler.shared.submit(request)
    }

    private static func handleTask(_ task: BGProcessingTask) {
        // BG-02: Skip if low power mode
        guard !ProcessInfo.processInfo.isLowPowerModeEnabled else {
            task.setTaskCompleted(success: true)
            schedule()
            return
        }

        task.expirationHandler = {
            // BG-03: Save state on expiration
        }

        ForgeLogger.background.info("CacheEvictionTask: starting")
        // 1. Evict cached thumbnails older than 30 days
        evictStaleThumbnails()

        // 2. Evict posting data older than 90 days with no active assignments (retention policy)
        evictExpiredPostings()

        ForgeLogger.background.info("CacheEvictionTask: completed")
        task.setTaskCompleted(success: true)
        schedule()
    }

    /// Removes cached thumbnail files older than 30 days.
    private static func evictStaleThumbnails() {
        let cacheDir = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first!
        let threshold = Date().addingTimeInterval(-30 * 24 * 3600)

        guard let files = try? FileManager.default.contentsOfDirectory(
            at: cacheDir,
            includingPropertiesForKeys: [.contentModificationDateKey]
        ) else { return }

        for fileURL in files {
            if let attrs = try? fileURL.resourceValues(forKeys: [.contentModificationDateKey]),
               let modified = attrs.contentModificationDate,
               modified < threshold {
                try? FileManager.default.removeItem(at: fileURL)
            }
        }
    }

    /// Marks postings older than 90 days with no active assignments as eviction candidates.
    /// Completed/cancelled postings past retention are cleaned up.
    /// Active/in-progress postings are always retained (pinned).
    private static func evictExpiredPostings() {
        let dbPool = DatabaseManager.shared.dbPool
        let cutoff = Date().addingTimeInterval(-Double(retentionDays) * 24 * 3600)

        do {
            try dbPool.write { db in
                // Find completed/cancelled postings older than 90 days with no active assignments
                let evictablePostings = try Row.fetchAll(db, sql: """
                    SELECT sp.id, sp.status FROM service_postings sp
                    WHERE sp.updatedAt < ?
                      AND sp.status IN ('COMPLETED', 'CANCELLED')
                      AND NOT EXISTS (
                        SELECT 1 FROM assignments a
                        WHERE a.postingId = sp.id AND a.status = 'ACCEPTED'
                      )
                """, arguments: [cutoff])

                for row in evictablePostings {
                    guard let idStr = row["id"] as? String, let postingId = UUID(uuidString: idStr) else { continue }

                    // Delete the entire posting attachment directory from disk
                    // Uploads store files at attachments/<postingId>/<filename>
                    let baseDir = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first!
                        .appendingPathComponent("attachments", isDirectory: true)
                    let postingDir = baseDir.appendingPathComponent(idStr)
                    if FileManager.default.fileExists(atPath: postingDir.path) {
                        try? FileManager.default.removeItem(at: postingDir)
                    }

                    // Cascade delete handles tasks, assignments, comments, attachments via FK
                    try db.execute(sql: "DELETE FROM service_postings WHERE id = ?", arguments: [postingId])
                }
            }
        } catch {
            // Non-fatal — will retry on next schedule
        }
    }
}
