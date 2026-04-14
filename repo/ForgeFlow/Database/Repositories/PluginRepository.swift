import Foundation
import GRDB

final class PluginRepository: Sendable {
    private let dbPool: DatabasePool

    init(dbPool: DatabasePool) {
        self.dbPool = dbPool
    }

    // MARK: - Reads

    func findById(_ id: UUID) async throws -> PluginDefinition? {
        try await dbPool.read { db in
            try PluginDefinition.fetchOne(db, key: id)
        }
    }

    func findAll() async throws -> [PluginDefinition] {
        try await dbPool.read { db in
            try PluginDefinition
                .order(PluginDefinition.Columns.updatedAt.desc)
                .fetchAll(db)
        }
    }

    func findByStatus(_ status: PluginStatus) async throws -> [PluginDefinition] {
        try await dbPool.read { db in
            try PluginDefinition
                .filter(PluginDefinition.Columns.status == status.rawValue)
                .order(PluginDefinition.Columns.updatedAt.desc)
                .fetchAll(db)
        }
    }

    func findActive() async throws -> [PluginDefinition] {
        try await findByStatus(.active)
    }

    // MARK: - Transactional

    func insertInTransaction(db: Database, _ plugin: PluginDefinition) throws {
        var p = plugin
        try p.insert(db)
    }

    func updateInTransaction(db: Database, _ plugin: inout PluginDefinition) throws {
        plugin.updatedAt = Date()
        plugin.version += 1
        try plugin.update(db)
    }

    // MARK: - Fields

    func findFields(pluginId: UUID) async throws -> [PluginField] {
        try await dbPool.read { db in
            try PluginField
                .filter(PluginField.Columns.pluginId == pluginId)
                .order(PluginField.Columns.sortOrder.asc)
                .fetchAll(db)
        }
    }

    func insertFieldInTransaction(db: Database, _ field: PluginField) throws {
        var f = field
        try f.insert(db)
    }

    func deleteFieldInTransaction(db: Database, _ fieldId: UUID) throws {
        _ = try PluginField.deleteOne(db, key: fieldId)
    }

    // MARK: - Test Results

    func findTestResults(pluginId: UUID) async throws -> [PluginTestResult] {
        try await dbPool.read { db in
            try PluginTestResult
                .filter(PluginTestResult.Columns.pluginId == pluginId)
                .order(PluginTestResult.Columns.testedAt.desc)
                .fetchAll(db)
        }
    }

    func insertTestResultInTransaction(db: Database, _ result: PluginTestResult) throws {
        var r = result
        try r.insert(db)
    }

    func deleteTestResultsInTransaction(db: Database, pluginId: UUID) throws {
        try PluginTestResult
            .filter(PluginTestResult.Columns.pluginId == pluginId)
            .deleteAll(db)
    }

    // MARK: - Approvals

    func findApprovals(pluginId: UUID) async throws -> [PluginApproval] {
        try await dbPool.read { db in
            try PluginApproval
                .filter(PluginApproval.Columns.pluginId == pluginId)
                .order(PluginApproval.Columns.step.asc)
                .fetchAll(db)
        }
    }

    func insertApprovalInTransaction(db: Database, _ approval: PluginApproval) throws {
        var a = approval
        try a.insert(db)
    }

    func deleteApprovalsInTransaction(db: Database, pluginId: UUID) throws {
        try PluginApproval
            .filter(PluginApproval.Columns.pluginId == pluginId)
            .deleteAll(db)
    }
}
