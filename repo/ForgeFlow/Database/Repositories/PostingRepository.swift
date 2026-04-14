import Foundation
import GRDB

final class PostingRepository: Sendable {
    private let dbPool: DatabasePool

    init(dbPool: DatabasePool) {
        self.dbPool = dbPool
    }

    // MARK: - Reads

    func findById(_ id: UUID) async throws -> ServicePosting? {
        try await dbPool.read { db in
            try ServicePosting.fetchOne(db, key: id)
        }
    }

    func findAll() async throws -> [ServicePosting] {
        try await dbPool.read { db in
            try ServicePosting.order(ServicePosting.Columns.createdAt.desc).fetchAll(db)
        }
    }

    func findByCreator(_ userId: UUID) async throws -> [ServicePosting] {
        try await dbPool.read { db in
            try ServicePosting
                .filter(ServicePosting.Columns.createdBy == userId)
                .order(ServicePosting.Columns.createdAt.desc)
                .fetchAll(db)
        }
    }

    func findForTechnician(_ technicianId: UUID) async throws -> [ServicePosting] {
        try await dbPool.read { db in
            // OPEN postings with acceptanceMode=OPEN are discoverable by all technicians.
            // INVITE_ONLY postings are only visible once an INVITED or ACCEPTED assignment exists.
            let sql = """
                SELECT DISTINCT sp.* FROM service_postings sp
                LEFT JOIN assignments a ON a.postingId = sp.id AND a.technicianId = ?
                WHERE (sp.status = 'OPEN' AND sp.acceptanceMode = 'OPEN')
                   OR (a.status = 'INVITED' OR a.status = 'ACCEPTED')
                ORDER BY sp.createdAt DESC
                """
            return try ServicePosting.fetchAll(db, sql: sql, arguments: [technicianId])
        }
    }

    // MARK: - Transactional

    func findByIdInTransaction(db: Database, _ id: UUID) throws -> ServicePosting? {
        try ServicePosting.fetchOne(db, key: id)
    }

    func insertInTransaction(db: Database, _ posting: ServicePosting) throws {
        try posting.insert(db)
    }

    func updateWithLocking(db: Database, posting: inout ServicePosting) throws {
        let current = try ServicePosting.fetchOne(db, key: posting.id)
        guard current?.version == posting.version else {
            throw StaleRecordError(entityType: "ServicePosting", entityId: posting.id)
        }
        posting.version += 1
        posting.updatedAt = Date()
        try posting.update(db)
    }
}
