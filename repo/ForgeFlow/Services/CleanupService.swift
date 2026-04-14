import Foundation
import GRDB
import UIKit

final class CleanupService: Sendable {
    private let dbPool: DatabasePool
    private let attachmentRepository: AttachmentRepository

    init(dbPool: DatabasePool, attachmentRepository: AttachmentRepository) {
        self.dbPool = dbPool
        self.attachmentRepository = attachmentRepository
    }

    /// Deletes orphan attachment files older than 30 days with no entity reference.
    /// BG-04: Runs as BGProcessingTask daily.
    func cleanOrphans() async throws -> Int {
        // BG-02: Skip when battery < 20%
        let batteryLevel = await MainActor.run {
            UIDevice.current.isBatteryMonitoringEnabled = true
            return UIDevice.current.batteryLevel
        }
        if batteryLevel > 0 && batteryLevel < 0.2 {
            return 0
        }

        let threshold = Date().addingTimeInterval(-30 * 24 * 3600) // 30 days ago
        let orphans = try await attachmentRepository.findOrphans(olderThan: threshold)

        let fileManager = FileManager.default
        let documentsURL = try fileManager.url(for: .documentDirectory, in: .userDomainMask,
                                                appropriateFor: nil, create: false)
        let attachmentsDir = documentsURL.appendingPathComponent("attachments")
        var deletedCount = 0

        for orphan in orphans {
            // Delete file from disk
            let filePath: URL
            if let postingId = orphan.postingId {
                filePath = attachmentsDir
                    .appendingPathComponent(postingId.uuidString)
                    .appendingPathComponent(orphan.filePath)
            } else {
                filePath = attachmentsDir.appendingPathComponent(orphan.filePath)
            }

            try? fileManager.removeItem(at: filePath)

            // Delete thumbnail if exists
            if let thumbPath = orphan.thumbnailPath {
                let thumbURL = filePath.deletingLastPathComponent().appendingPathComponent(thumbPath)
                try? fileManager.removeItem(at: thumbURL)
            }

            // Delete DB record
            try await attachmentRepository.delete(orphan.id)
            deletedCount += 1
        }

        return deletedCount
    }
}
