import Foundation
import Testing
import GRDB
@testable import ForgeFlow

// MARK: - Helpers

private func makeDB() throws -> DatabaseManager {
    try DatabaseManager(inMemory: true)
}

private func makeUser(pool: DatabasePool, role: Role = .admin) async throws -> User {
    let now = Date()
    let u = User(
        id: UUID(), username: UUID().uuidString, role: role,
        status: .active, failedLoginCount: 0, lockedUntil: nil,
        biometricEnabled: false, dndStartTime: nil, dndEndTime: nil,
        storageQuotaBytes: 2_147_483_648, version: 1, createdAt: now, updatedAt: now
    )
    try await pool.write { db in try u.insert(db) }
    return u
}

private func makePostingService(_ pool: DatabasePool) -> PostingService {
    PostingService(
        dbPool: pool,
        postingRepository: PostingRepository(dbPool: pool),
        taskRepository: TaskRepository(dbPool: pool),
        userRepository: UserRepository(dbPool: pool),
        auditService: AuditService(dbPool: pool)
    )
}

private func makePluginService(_ pool: DatabasePool) -> PluginService {
    PluginService(
        dbPool: pool,
        pluginRepository: PluginRepository(dbPool: pool),
        postingRepository: PostingRepository(dbPool: pool),
        auditService: AuditService(dbPool: pool),
        userRepository: UserRepository(dbPool: pool)
    )
}

private func makeSyncService(_ pool: DatabasePool) -> SyncService {
    SyncService(
        dbPool: pool,
        syncRepository: SyncRepository(dbPool: pool),
        postingRepository: PostingRepository(dbPool: pool),
        auditService: AuditService(dbPool: pool),
        taskRepository: TaskRepository(dbPool: pool),
        assignmentRepository: AssignmentRepository(dbPool: pool),
        commentRepository: CommentRepository(dbPool: pool),
        dependencyRepository: DependencyRepository(dbPool: pool),
        userRepository: UserRepository(dbPool: pool)
    )
}

// MARK: - DependencyRepository Tests

@Suite("DependencyRepository", .serialized)
struct DependencyRepositoryTests {

    @Test func insertAndFindByTask() async throws {
        let db = try makeDB()
        let pool = db.dbPool
        let admin = try await makeUser(pool: pool)
        let ps = makePostingService(pool)
        let posting = try await ps.create(
            actorId: admin.id, title: "Dep Test", siteAddress: "123 St",
            dueDate: Date().addingTimeInterval(86400), budgetCents: 5000,
            acceptanceMode: .inviteOnly, watermarkEnabled: false
        )
        let tasks = try await TaskRepository(dbPool: pool).findByPosting(posting.id)
        let rootTask = tasks[0]

        let now = Date()
        let task2 = ForgeTask(
            id: UUID(), postingId: posting.id, parentTaskId: nil,
            title: "T2", taskDescription: nil, priority: .p2,
            status: .notStarted, blockedComment: nil, assignedTo: nil,
            sortOrder: 1, version: 1, createdAt: now, updatedAt: now
        )
        try await pool.write { db in try task2.insert(db) }

        let depRepo = DependencyRepository(dbPool: pool)
        let dep = Dependency(id: UUID(), taskId: task2.id, dependsOnTaskId: rootTask.id, type: .finishToStart)
        try await pool.write { db in try depRepo.insertInTransaction(db: db, dep) }

        let found = try await depRepo.findByTask(task2.id)
        #expect(found.count == 1)
        #expect(found[0].dependsOnTaskId == rootTask.id)
    }

    @Test func findDependents() async throws {
        let db = try makeDB()
        let pool = db.dbPool
        let admin = try await makeUser(pool: pool)
        let posting = try await makePostingService(pool).create(
            actorId: admin.id, title: "Deps", siteAddress: "A",
            dueDate: Date().addingTimeInterval(86400), budgetCents: 1000,
            acceptanceMode: .inviteOnly, watermarkEnabled: false
        )
        let rootTask = try await TaskRepository(dbPool: pool).findByPosting(posting.id)[0]
        let now = Date()
        let task2 = ForgeTask(
            id: UUID(), postingId: posting.id, parentTaskId: nil,
            title: "T2", taskDescription: nil, priority: .p2,
            status: .notStarted, blockedComment: nil, assignedTo: nil,
            sortOrder: 1, version: 1, createdAt: now, updatedAt: now
        )
        try await pool.write { db in try task2.insert(db) }

        let depRepo = DependencyRepository(dbPool: pool)
        let dep = Dependency(id: UUID(), taskId: task2.id, dependsOnTaskId: rootTask.id, type: .finishToStart)
        try await pool.write { db in try depRepo.insertInTransaction(db: db, dep) }

        let dependents = try await depRepo.findDependents(of: rootTask.id)
        #expect(dependents.count == 1)
        #expect(dependents[0].taskId == task2.id)
    }

    @Test func deleteInTransaction() async throws {
        let db = try makeDB()
        let pool = db.dbPool
        let admin = try await makeUser(pool: pool)
        let posting = try await makePostingService(pool).create(
            actorId: admin.id, title: "Del Dep", siteAddress: "B",
            dueDate: Date().addingTimeInterval(86400), budgetCents: 1000,
            acceptanceMode: .inviteOnly, watermarkEnabled: false
        )
        let rootTask = try await TaskRepository(dbPool: pool).findByPosting(posting.id)[0]
        let now = Date()
        let task2 = ForgeTask(
            id: UUID(), postingId: posting.id, parentTaskId: nil,
            title: "T2", taskDescription: nil, priority: .p2,
            status: .notStarted, blockedComment: nil, assignedTo: nil,
            sortOrder: 1, version: 1, createdAt: now, updatedAt: now
        )
        try await pool.write { db in try task2.insert(db) }

        let depRepo = DependencyRepository(dbPool: pool)
        let dep = Dependency(id: UUID(), taskId: task2.id, dependsOnTaskId: rootTask.id, type: .finishToStart)
        try await pool.write { db in try depRepo.insertInTransaction(db: db, dep) }

        // Delete it
        try await pool.write { db in try depRepo.deleteInTransaction(db: db, dep.id) }

        let found = try await depRepo.findByTask(task2.id)
        #expect(found.isEmpty)
    }

    @Test func findByTaskInTransaction() async throws {
        let db = try makeDB()
        let pool = db.dbPool
        let admin = try await makeUser(pool: pool)
        let posting = try await makePostingService(pool).create(
            actorId: admin.id, title: "TX Dep", siteAddress: "C",
            dueDate: Date().addingTimeInterval(86400), budgetCents: 1000,
            acceptanceMode: .inviteOnly, watermarkEnabled: false
        )
        let rootTask = try await TaskRepository(dbPool: pool).findByPosting(posting.id)[0]
        let now = Date()
        let task2 = ForgeTask(
            id: UUID(), postingId: posting.id, parentTaskId: nil,
            title: "T2", taskDescription: nil, priority: .p2,
            status: .notStarted, blockedComment: nil, assignedTo: nil,
            sortOrder: 1, version: 1, createdAt: now, updatedAt: now
        )
        try await pool.write { db in try task2.insert(db) }

        let depRepo = DependencyRepository(dbPool: pool)
        let dep = Dependency(id: UUID(), taskId: task2.id, dependsOnTaskId: rootTask.id, type: .finishToStart)
        try await pool.write { db in try depRepo.insertInTransaction(db: db, dep) }

        let found = try await pool.read { db in
            try depRepo.findByTaskInTransaction(db: db, task2.id)
        }
        #expect(found.count == 1)
    }
}

// MARK: - ChunkingService Tests

@Suite("ChunkingService", .serialized)
struct ChunkingServiceTests {

    private func makeTempFile(size: Int) throws -> URL {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString + ".bin")
        let data = Data(repeating: 0xAB, count: size)
        try data.write(to: url)
        return url
    }

    @Test func defaultChunkSizeIs5MB() {
        #expect(ChunkingService.defaultChunkSize == 5 * 1024 * 1024)
    }

    @Test func smallFileCopied() async throws {
        let src = try makeTempFile(size: 30_000)
        let dst = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString + ".bin")
        defer {
            try? FileManager.default.removeItem(at: src)
            try? FileManager.default.removeItem(at: dst)
        }

        let service = ChunkingService()
        let bytesCopied = try await service.copyInChunks(
            sourceURL: src, destinationURL: dst, chunkSize: 10_000
        )
        #expect(bytesCopied == 30_000)

        let written = try Data(contentsOf: dst)
        #expect(written.count == 30_000)
    }

    @Test func emptyFileCopied() async throws {
        let src = try makeTempFile(size: 0)
        let dst = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString + ".bin")
        defer {
            try? FileManager.default.removeItem(at: src)
            try? FileManager.default.removeItem(at: dst)
        }

        let service = ChunkingService()
        let bytesCopied = try await service.copyInChunks(
            sourceURL: src, destinationURL: dst
        )
        #expect(bytesCopied == 0)
    }

    @Test func resumeFromChunkIncludesSkippedOffset() async throws {
        let totalSize = 50_000
        let chunkSize = 10_000
        let src = try makeTempFile(size: totalSize)
        let dst = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString + ".bin")
        defer {
            try? FileManager.default.removeItem(at: src)
            try? FileManager.default.removeItem(at: dst)
        }

        let service = ChunkingService()
        let bytesCopied = try await service.copyInChunks(
            sourceURL: src, destinationURL: dst,
            chunkSize: chunkSize, resumeFromChunk: 2
        )
        // ChunkingService returns total bytes including the resume offset:
        // resumeOffset(20000) + remaining(30000) = 50000
        #expect(bytesCopied == totalSize)
    }
}

// MARK: - CleanupService Tests

@Suite("CleanupService", .serialized)
struct CleanupServiceTests {

    @Test func cleanOrphansEmptyDatabaseReturnsZero() async throws {
        let db = try makeDB()
        let pool = db.dbPool
        let service = CleanupService(
            dbPool: pool,
            attachmentRepository: AttachmentRepository(dbPool: pool)
        )
        let count = try await service.cleanOrphans()
        #expect(count == 0)
    }

    @Test func cleanOrphansReturnsInt() async throws {
        let db = try makeDB()
        let pool = db.dbPool
        let service = CleanupService(
            dbPool: pool,
            attachmentRepository: AttachmentRepository(dbPool: pool)
        )
        let count = try await service.cleanOrphans()
        #expect(count >= 0)
    }
}

// MARK: - SyncService Tests

@Suite("SyncService", .serialized)
struct SyncServiceCoverageTests {

    @Test func exportEmptyDatabaseReturnsZeroCount() async throws {
        let db = try makeDB()
        let pool = db.dbPool
        let admin = try await makeUser(pool: pool)
        let syncService = makeSyncService(pool)

        let export = try await syncService.export(
            entityTypes: ["postings"],
            startDate: Date().addingTimeInterval(-86400 * 7),
            endDate: Date().addingTimeInterval(86400),
            exportedBy: admin.id
        )
        #expect(export.recordCount == 0)
    }

    @Test func exportWithPostingsIncludesRecord() async throws {
        let db = try makeDB()
        let pool = db.dbPool
        let admin = try await makeUser(pool: pool)
        _ = try await makePostingService(pool).create(
            actorId: admin.id, title: "Sync Test", siteAddress: "123",
            dueDate: Date().addingTimeInterval(86400), budgetCents: 5000,
            acceptanceMode: .inviteOnly, watermarkEnabled: false
        )

        let syncService = makeSyncService(pool)
        let export = try await syncService.export(
            entityTypes: ["postings"],
            startDate: nil,
            endDate: nil,
            exportedBy: admin.id
        )
        #expect(export.recordCount >= 1)
    }

    @Test func exportChecksumIsNonEmpty() async throws {
        let db = try makeDB()
        let pool = db.dbPool
        let admin = try await makeUser(pool: pool)
        let syncService = makeSyncService(pool)

        let export = try await syncService.export(
            entityTypes: ["postings"],
            startDate: nil, endDate: nil,
            exportedBy: admin.id
        )
        #expect(!export.checksumSha256.isEmpty)
        #expect(export.checksumSha256.count >= 40)
    }

    @Test func nonAdminCannotExport() async throws {
        let db = try makeDB()
        let pool = db.dbPool
        let tech = try await makeUser(pool: pool, role: .technician)
        let syncService = makeSyncService(pool)

        do {
            _ = try await syncService.export(
                entityTypes: ["postings"],
                startDate: nil, endDate: nil,
                exportedBy: tech.id
            )
            Issue.record("Expected authorization error but export succeeded")
        } catch {
            // Expected
        }
    }

    @Test func listExportsAfterExport() async throws {
        let db = try makeDB()
        let pool = db.dbPool
        let admin = try await makeUser(pool: pool)
        let syncService = makeSyncService(pool)

        _ = try await syncService.export(
            entityTypes: ["postings"],
            startDate: nil, endDate: nil,
            exportedBy: admin.id
        )

        let exports = try await syncService.listExports(actorId: admin.id)
        #expect(exports.count >= 1)
    }

    @Test func deltaExportSucceeds() async throws {
        let db = try makeDB()
        let pool = db.dbPool
        let admin = try await makeUser(pool: pool)
        let syncService = makeSyncService(pool)
        let peerId = UUID().uuidString

        let export = try await syncService.exportDelta(
            peerId: peerId,
            entityTypes: ["postings"],
            exportedBy: admin.id
        )
        #expect(export.recordCount >= 0)
    }

    @Test func confirmExportDeliveredSucceeds() async throws {
        let db = try makeDB()
        let pool = db.dbPool
        let admin = try await makeUser(pool: pool)
        let syncService = makeSyncService(pool)
        let peerId = UUID().uuidString
        let exportedAt = Date()

        _ = try await syncService.exportDelta(
            peerId: peerId, entityTypes: ["postings"],
            exportedBy: admin.id
        )

        // Confirm delivery — should not throw
        try await syncService.confirmExportDelivered(
            peerId: peerId,
            entityTypes: ["postings"],
            exportedAt: exportedAt,
            actorId: admin.id
        )
    }

    @Test func exportMultipleEntityTypes() async throws {
        let db = try makeDB()
        let pool = db.dbPool
        let admin = try await makeUser(pool: pool)
        let syncService = makeSyncService(pool)

        let export = try await syncService.export(
            entityTypes: ["postings", "tasks", "assignments"],
            startDate: nil, endDate: nil,
            exportedBy: admin.id
        )
        #expect(export.recordCount >= 0)
    }
}

// MARK: - PluginService Tests

@Suite("PluginService", .serialized)
struct PluginServiceCoverageTests {

    @Test func createPluginAsAdmin() async throws {
        let db = try makeDB()
        let pool = db.dbPool
        let admin = try await makeUser(pool: pool)
        let service = makePluginService(pool)

        let plugin = try await service.create(
            name: "Safety Check", description: "Verifies safety", category: "safety",
            createdBy: admin.id
        )
        #expect(plugin.status == .draft)
        #expect(plugin.name == "Safety Check")
    }

    @Test func nonAdminCannotCreatePlugin() async throws {
        let db = try makeDB()
        let pool = db.dbPool
        let tech = try await makeUser(pool: pool, role: .technician)
        let service = makePluginService(pool)

        do {
            _ = try await service.create(
                name: "Bad", description: "nope", category: "cat",
                createdBy: tech.id
            )
            Issue.record("Expected auth error")
        } catch {
            // Expected
        }
    }

    @Test func addFieldToPlugin() async throws {
        let db = try makeDB()
        let pool = db.dbPool
        let admin = try await makeUser(pool: pool)
        let service = makePluginService(pool)

        let plugin = try await service.create(
            name: "Field Test", description: "desc", category: "test",
            createdBy: admin.id
        )
        let field = try await service.addField(
            pluginId: plugin.id, fieldName: "score",
            fieldType: .number, unit: nil,
            validationRules: "{\"min\":0,\"max\":100}",
            actorId: admin.id
        )
        #expect(field.fieldType == .number)
        #expect(field.fieldName == "score")
    }

    @Test func validateFieldValues_numberInRange() async throws {
        let db = try makeDB()
        let pool = db.dbPool
        let admin = try await makeUser(pool: pool)
        let service = makePluginService(pool)
        let plugin = try await service.create(
            name: "Num Test", description: "d", category: "c", createdBy: admin.id
        )
        let field = try await service.addField(
            pluginId: plugin.id, fieldName: "score", fieldType: .number, unit: nil,
            validationRules: "{\"min\":0,\"max\":100}", actorId: admin.id
        )
        let errors = service.validateFieldValues(fields: [field], values: [field.id: "50"])
        #expect(errors.isEmpty)
    }

    @Test func validateFieldValues_numberOutOfRange() async throws {
        let db = try makeDB()
        let pool = db.dbPool
        let admin = try await makeUser(pool: pool)
        let service = makePluginService(pool)
        let plugin = try await service.create(
            name: "Num Out", description: "d", category: "c", createdBy: admin.id
        )
        let field = try await service.addField(
            pluginId: plugin.id, fieldName: "score", fieldType: .number, unit: nil,
            validationRules: "{\"min\":0,\"max\":100}", actorId: admin.id
        )
        let errors = service.validateFieldValues(fields: [field], values: [field.id: "150"])
        #expect(!errors.isEmpty)
    }

    @Test func validateFieldValues_textTooShort() async throws {
        let db = try makeDB()
        let pool = db.dbPool
        let admin = try await makeUser(pool: pool)
        let service = makePluginService(pool)
        let plugin = try await service.create(
            name: "Text Short", description: "d", category: "c", createdBy: admin.id
        )
        let field = try await service.addField(
            pluginId: plugin.id, fieldName: "label", fieldType: .text, unit: nil,
            validationRules: "{\"minLength\":5}", actorId: admin.id
        )
        let errors = service.validateFieldValues(fields: [field], values: [field.id: "hi"])
        #expect(!errors.isEmpty)
    }

    @Test func validateFieldValues_textValidRegex() async throws {
        let db = try makeDB()
        let pool = db.dbPool
        let admin = try await makeUser(pool: pool)
        let service = makePluginService(pool)
        let plugin = try await service.create(
            name: "Text Regex", description: "d", category: "c", createdBy: admin.id
        )
        let field = try await service.addField(
            pluginId: plugin.id, fieldName: "code", fieldType: .text, unit: nil,
            validationRules: "{\"pattern\":\"^[A-Z]+$\"}", actorId: admin.id
        )
        let errors = service.validateFieldValues(fields: [field], values: [field.id: "HELLO"])
        #expect(errors.isEmpty)
    }

    @Test func validateFieldValues_textInvalidRegex() async throws {
        let db = try makeDB()
        let pool = db.dbPool
        let admin = try await makeUser(pool: pool)
        let service = makePluginService(pool)
        let plugin = try await service.create(
            name: "Text RegexFail", description: "d", category: "c", createdBy: admin.id
        )
        let field = try await service.addField(
            pluginId: plugin.id, fieldName: "code", fieldType: .text, unit: nil,
            validationRules: "{\"pattern\":\"^[A-Z]+$\"}", actorId: admin.id
        )
        let errors = service.validateFieldValues(fields: [field], values: [field.id: "hello"])
        #expect(!errors.isEmpty)
    }

    @Test func getActivePluginsWithFieldsEmptyDB() async throws {
        let db = try makeDB()
        let pool = db.dbPool
        let service = makePluginService(pool)
        let result = try await service.getActivePluginsWithFields()
        #expect(result.isEmpty)
    }

    @Test func setFieldValueSucceeds() async throws {
        let db = try makeDB()
        let pool = db.dbPool
        let admin = try await makeUser(pool: pool)
        let pluginService = makePluginService(pool)
        let postingService = makePostingService(pool)

        let posting = try await postingService.create(
            actorId: admin.id, title: "Plug Posting", siteAddress: "Addr",
            dueDate: Date().addingTimeInterval(86400), budgetCents: 1000,
            acceptanceMode: .inviteOnly, watermarkEnabled: false
        )
        let plugin = try await pluginService.create(
            name: "Set Field", description: "d", category: "c", createdBy: admin.id
        )
        let field = try await pluginService.addField(
            pluginId: plugin.id, fieldName: "rating", fieldType: .number, unit: nil,
            validationRules: nil, actorId: admin.id
        )

        // setFieldValue should not throw and should write to the DB
        try await pluginService.setFieldValue(
            postingId: posting.id, pluginFieldId: field.id,
            value: "42", actorId: admin.id
        )

        // Verify via raw SQL
        let storedValue = try await pool.read { db -> String? in
            let sql = "SELECT value FROM posting_field_values WHERE postingId = ? AND pluginFieldId = ?"
            return try String.fetchOne(db, sql: sql, arguments: [posting.id, field.id])
        }
        #expect(storedValue == "42")
    }
}
