import Foundation
import GRDB

struct User: Codable, FetchableRecord, PersistableRecord, Identifiable, Sendable {
    static let databaseTableName = "users"

    var id: UUID
    var username: String
    var role: Role
    var status: UserStatus
    var failedLoginCount: Int
    var lockedUntil: Date?
    var biometricEnabled: Bool
    var dndStartTime: String?
    var dndEndTime: String?
    var storageQuotaBytes: Int
    var version: Int
    var createdAt: Date
    var updatedAt: Date

    enum Columns: String, ColumnExpression {
        case id, username, role, status, failedLoginCount, lockedUntil
        case biometricEnabled, dndStartTime, dndEndTime, storageQuotaBytes
        case version, createdAt, updatedAt
    }
}
