import Foundation
import GRDB

struct Attachment: Codable, FetchableRecord, PersistableRecord, Identifiable, Sendable {
    static let databaseTableName = "attachments"

    var id: UUID
    var commentId: UUID?
    var postingId: UUID?
    var taskId: UUID?
    var fileName: String
    var filePath: String
    var fileSizeBytes: Int
    var mimeType: AttachmentMimeType
    var checksumSha256: String
    var thumbnailPath: String?
    var isCompressed: Bool
    var originalEncryptedPath: String?
    var uploadedBy: UUID
    var createdAt: Date

    enum Columns: String, ColumnExpression {
        case id, commentId, postingId, taskId, fileName, filePath
        case fileSizeBytes, mimeType, checksumSha256, thumbnailPath
        case isCompressed, originalEncryptedPath, uploadedBy, createdAt
    }
}
