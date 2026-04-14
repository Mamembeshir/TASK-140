import Foundation
import GRDB

struct ServicePosting: Codable, FetchableRecord, PersistableRecord, Identifiable, Sendable {
    static let databaseTableName = "service_postings"

    var id: UUID
    var title: String
    var siteAddress: String
    var dueDate: Date
    var budgetCapCents: Int
    var status: PostingStatus
    var acceptanceMode: AcceptanceMode
    var createdBy: UUID
    var watermarkEnabled: Bool
    var version: Int
    var createdAt: Date
    var updatedAt: Date

    enum Columns: String, ColumnExpression {
        case id, title, siteAddress, dueDate, budgetCapCents
        case status, acceptanceMode, createdBy, watermarkEnabled
        case version, createdAt, updatedAt
    }
}
