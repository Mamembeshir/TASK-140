import Foundation
import GRDB

final class SyncRepository: Sendable {
    private let dbPool: DatabasePool

    init(dbPool: DatabasePool) {
        self.dbPool = dbPool
    }

    // MARK: - Exports

    func findExportById(_ id: UUID) async throws -> SyncExport? {
        try await dbPool.read { db in
            try SyncExport.fetchOne(db, key: id)
        }
    }

    func findAllExports() async throws -> [SyncExport] {
        try await dbPool.read { db in
            try SyncExport
                .order(SyncExport.Columns.exportedAt.desc)
                .fetchAll(db)
        }
    }

    func latestExport() async throws -> SyncExport? {
        try await dbPool.read { db in
            try SyncExport
                .order(SyncExport.Columns.exportedAt.desc)
                .fetchOne(db)
        }
    }

    func insertExportInTransaction(db: Database, _ export: SyncExport) throws {
        try export.insert(db)
    }

    // MARK: - Imports

    func findImportById(_ id: UUID) async throws -> SyncImport? {
        try await dbPool.read { db in
            try SyncImport.fetchOne(db, key: id)
        }
    }

    func findAllImports() async throws -> [SyncImport] {
        try await dbPool.read { db in
            try SyncImport
                .order(SyncImport.Columns.importedAt.desc)
                .fetchAll(db)
        }
    }

    func latestImport() async throws -> SyncImport? {
        try await dbPool.read { db in
            try SyncImport
                .order(SyncImport.Columns.importedAt.desc)
                .fetchOne(db)
        }
    }

    func insertImportInTransaction(db: Database, _ syncImport: SyncImport) throws {
        var i = syncImport
        try i.insert(db)
    }

    func updateImportInTransaction(db: Database, _ syncImport: inout SyncImport) throws {
        try syncImport.update(db)
    }

    // MARK: - Cursors

    func findCursor(peerId: String, entityType: String) async throws -> SyncCursor? {
        try await dbPool.read { db in
            try SyncCursor
                .filter(SyncCursor.Columns.peerId == peerId)
                .filter(SyncCursor.Columns.entityType == entityType)
                .fetchOne(db)
        }
    }

    func upsertCursor(peerId: String, entityType: String, lastSyncedAt: Date) async throws {
        let now = Date()
        try await dbPool.write { db in
            if var existing = try SyncCursor
                .filter(SyncCursor.Columns.peerId == peerId)
                .filter(SyncCursor.Columns.entityType == entityType)
                .fetchOne(db) {
                existing.lastSyncedAt = lastSyncedAt
                existing.updatedAt = now
                try existing.update(db)
            } else {
                var cursor = SyncCursor(
                    id: UUID(), peerId: peerId, entityType: entityType,
                    lastSyncedAt: lastSyncedAt, updatedAt: now
                )
                try cursor.insert(db)
            }
        }
    }

    func listCursors(peerId: String) async throws -> [SyncCursor] {
        try await dbPool.read { db in
            try SyncCursor
                .filter(SyncCursor.Columns.peerId == peerId)
                .fetchAll(db)
        }
    }
}
