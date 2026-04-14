import Foundation
import GRDB

final class AssignmentRepository: Sendable {
    private let dbPool: DatabasePool

    init(dbPool: DatabasePool) {
        self.dbPool = dbPool
    }

    // MARK: - Reads

    func findById(_ id: UUID) async throws -> Assignment? {
        try await dbPool.read { db in
            try Assignment.fetchOne(db, key: id)
        }
    }

    func findByPosting(_ postingId: UUID) async throws -> [Assignment] {
        try await dbPool.read { db in
            try Assignment
                .filter(Assignment.Columns.postingId == postingId)
                .order(Assignment.Columns.createdAt)
                .fetchAll(db)
        }
    }

    func findByTechnician(_ technicianId: UUID) async throws -> [Assignment] {
        try await dbPool.read { db in
            try Assignment
                .filter(Assignment.Columns.technicianId == technicianId)
                .order(Assignment.Columns.createdAt.desc)
                .fetchAll(db)
        }
    }

    // MARK: - Transactional

    func findAcceptedForPostingInTransaction(db: Database, postingId: UUID) throws -> Assignment? {
        try Assignment
            .filter(Assignment.Columns.postingId == postingId)
            .filter(Assignment.Columns.status == AssignmentStatus.accepted.rawValue)
            .fetchOne(db)
    }

    func findByPostingAndTechnicianInTransaction(db: Database, postingId: UUID, technicianId: UUID) throws -> Assignment? {
        try Assignment
            .filter(Assignment.Columns.postingId == postingId)
            .filter(Assignment.Columns.technicianId == technicianId)
            .fetchOne(db)
    }

    func findByPostingInTransaction(db: Database, _ postingId: UUID) throws -> [Assignment] {
        try Assignment
            .filter(Assignment.Columns.postingId == postingId)
            .fetchAll(db)
    }

    func insertInTransaction(db: Database, _ assignment: Assignment) throws {
        try assignment.insert(db)
    }

    func insertOrIgnoreInTransaction(db: Database, _ assignment: Assignment) throws {
        try assignment.insert(db, onConflict: .ignore)
    }

    func updateWithLocking(db: Database, assignment: inout Assignment) throws {
        let current = try Assignment.fetchOne(db, key: assignment.id)
        guard current?.version == assignment.version else {
            throw StaleRecordError(entityType: "Assignment", entityId: assignment.id)
        }
        assignment.version += 1
        assignment.updatedAt = Date()
        try assignment.update(db)
    }
}
