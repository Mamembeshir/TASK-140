import Foundation
import GRDB

final class DependencyRepository: Sendable {
    private let dbPool: DatabasePool

    init(dbPool: DatabasePool) {
        self.dbPool = dbPool
    }

    // MARK: - Reads

    func findByTask(_ taskId: UUID) async throws -> [Dependency] {
        try await dbPool.read { db in
            try Dependency
                .filter(Dependency.Columns.taskId == taskId)
                .fetchAll(db)
        }
    }

    func findDependents(of taskId: UUID) async throws -> [Dependency] {
        try await dbPool.read { db in
            try Dependency
                .filter(Dependency.Columns.dependsOnTaskId == taskId)
                .fetchAll(db)
        }
    }

    // MARK: - Transactional

    func findByTaskInTransaction(db: Database, _ taskId: UUID) throws -> [Dependency] {
        try Dependency
            .filter(Dependency.Columns.taskId == taskId)
            .fetchAll(db)
    }

    func findAllForPostingInTransaction(db: Database, postingId: UUID) throws -> [Dependency] {
        let sql = """
            SELECT d.* FROM dependencies d
            JOIN tasks t ON d.taskId = t.id
            WHERE t.postingId = ?
            """
        return try Dependency.fetchAll(db, sql: sql, arguments: [postingId.uuidString])
    }

    func insertInTransaction(db: Database, _ dependency: Dependency) throws {
        try dependency.insert(db)
    }

    func deleteInTransaction(db: Database, _ id: UUID) throws {
        try db.execute(sql: "DELETE FROM dependencies WHERE id = ?", arguments: [id])
    }
}
