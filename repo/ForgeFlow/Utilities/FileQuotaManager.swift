import Foundation
import GRDB

enum FileQuotaManager {
    /// Returns (usedBytes, quotaBytes) for a user.
    static func getUsage(userId: UUID, dbPool: DatabasePool) async throws -> (used: Int, quota: Int) {
        let used = try await dbPool.read { db in
            let sql = "SELECT COALESCE(SUM(fileSizeBytes), 0) FROM attachments WHERE uploadedBy = ?"
            return try Int.fetchOne(db, sql: sql, arguments: [userId.uuidString]) ?? 0
        }
        let quota = try await dbPool.read { db in
            let sql = "SELECT storageQuotaBytes FROM users WHERE id = ?"
            return try Int.fetchOne(db, sql: sql, arguments: [userId.uuidString]) ?? 2_147_483_648
        }
        return (used: used, quota: quota)
    }

    /// Returns true if the user can upload a file of the given size.
    static func checkQuota(userId: UUID, fileSizeBytes: Int, dbPool: DatabasePool) async throws -> Bool {
        let usage = try await getUsage(userId: userId, dbPool: dbPool)
        return (usage.used + fileSizeBytes) <= usage.quota
    }

    /// Returns usage as a percentage (0.0 to 1.0+).
    static func usagePercentage(userId: UUID, dbPool: DatabasePool) async throws -> Double {
        let usage = try await getUsage(userId: userId, dbPool: dbPool)
        guard usage.quota > 0 else { return 0 }
        return Double(usage.used) / Double(usage.quota)
    }
}
