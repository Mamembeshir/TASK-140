import Foundation
import GRDB

final class TaskRepository: Sendable {
    private let dbPool: DatabasePool

    init(dbPool: DatabasePool) {
        self.dbPool = dbPool
    }

    // MARK: - Reads

    func findById(_ id: UUID) async throws -> ForgeTask? {
        try await dbPool.read { db in
            try ForgeTask.fetchOne(db, key: id)
        }
    }

    func findByPosting(_ postingId: UUID) async throws -> [ForgeTask] {
        try await dbPool.read { db in
            try ForgeTask
                .filter(ForgeTask.Columns.postingId == postingId)
                .order(ForgeTask.Columns.sortOrder)
                .fetchAll(db)
        }
    }

    func findByAssignee(_ userId: UUID) async throws -> [ForgeTask] {
        try await dbPool.read { db in
            try ForgeTask
                .filter(ForgeTask.Columns.assignedTo == userId)
                .order(ForgeTask.Columns.priority)
                .fetchAll(db)
        }
    }

    // MARK: - Transactional

    func findByIdInTransaction(db: Database, _ id: UUID) throws -> ForgeTask? {
        try ForgeTask.fetchOne(db, key: id)
    }

    func findByPostingInTransaction(db: Database, _ postingId: UUID) throws -> [ForgeTask] {
        try ForgeTask
            .filter(ForgeTask.Columns.postingId == postingId)
            .order(ForgeTask.Columns.sortOrder)
            .fetchAll(db)
    }

    func findSubtasksInTransaction(db: Database, parentId: UUID) throws -> [ForgeTask] {
        try ForgeTask
            .filter(ForgeTask.Columns.parentTaskId == parentId)
            .order(ForgeTask.Columns.sortOrder)
            .fetchAll(db)
    }

    func insertInTransaction(db: Database, _ task: ForgeTask) throws {
        try task.insert(db)
    }

    func updateWithLocking(db: Database, task: inout ForgeTask) throws {
        let current = try ForgeTask.fetchOne(db, key: task.id)
        guard current?.version == task.version else {
            throw StaleRecordError(entityType: "Task", entityId: task.id)
        }
        task.version += 1
        task.updatedAt = Date()
        try task.update(db)
    }

    func updateSortOrders(db: Database, taskIds: [UUID]) throws {
        for (index, taskId) in taskIds.enumerated() {
            try db.execute(
                sql: "UPDATE tasks SET sortOrder = ?, updatedAt = ? WHERE id = ?",
                arguments: [index, Date(), taskId.uuidString]
            )
        }
    }
}
