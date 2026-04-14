import Testing
import Foundation
import GRDB
@testable import ForgeFlow

struct SyncIntegrationTests {

    private func makeDB() throws -> (DatabaseManager, SyncService, PostingService, UserRepository) {
        let db = try DatabaseManager(inMemory: true)
        let userRepo = UserRepository(dbPool: db.dbPool)
        let auditService = AuditService(dbPool: db.dbPool)
        let postingRepo = PostingRepository(dbPool: db.dbPool)
        let taskRepo = TaskRepository(dbPool: db.dbPool)
        let syncRepo = SyncRepository(dbPool: db.dbPool)
        let postingService = PostingService(
            dbPool: db.dbPool, postingRepository: postingRepo,
            taskRepository: taskRepo, userRepository: userRepo, auditService: auditService
        )
        let syncService = SyncService(
            dbPool: db.dbPool, syncRepository: syncRepo,
            postingRepository: postingRepo, auditService: auditService,
            userRepository: userRepo
        )
        return (db, syncService, postingService, userRepo)
    }

    private func makeUser(userRepo: UserRepository) async throws -> User {
        let now = Date()
        let user = User(
            id: UUID(), username: "sync_test_\(UUID().uuidString.prefix(6))",
            role: .admin, status: .active,
            failedLoginCount: 0, lockedUntil: nil, biometricEnabled: false,
            dndStartTime: nil, dndEndTime: nil,
            storageQuotaBytes: 2_147_483_648,
            version: 1, createdAt: now, updatedAt: now
        )
        try await userRepo.insert(user)
        return user
    }

    @Test("Sync: export → import → conflicts detected → resolve → applied")
    func fullSyncCycle() async throws {
        let (db, syncService, postingService, userRepo) = try makeDB()
        let user = try await makeUser(userRepo: userRepo)

        // Create some data
        _ = try await postingService.create(
            actorId: user.id, title: "Export Test Posting",
            siteAddress: "456 Sync Ave", dueDate: Date().addingTimeInterval(86400),
            budgetCents: 50000, acceptanceMode: .open, watermarkEnabled: false
        )

        // Export
        let export = try await syncService.export(
            entityTypes: ["postings"],
            startDate: nil, endDate: nil,
            exportedBy: user.id
        )
        #expect(export.recordCount >= 1)
        #expect(!export.checksumSha256.isEmpty)
        #expect(FileManager.default.fileExists(atPath: export.filePath))

        // Import the exported file (simulating different device)
        let importURL = URL(fileURLWithPath: export.filePath)
        let (syncImport, conflicts) = try await syncService.importFile(
            fileURL: importURL, importedBy: user.id
        )
        #expect(syncImport.recordCount >= 1)

        // Since same data, conflicts come from version mismatch (same version = no conflict)
        // Verify import was recorded
        let latestImport = try await syncService.latestImport(actorId: user.id)
        #expect(latestImport?.id == syncImport.id)

        // If there are conflicts, resolve them
        if !conflicts.isEmpty {
            try await syncService.resolveConflicts(
                importId: syncImport.id,
                decisions: conflicts.map { (entityId: $0.entityId, decision: SyncConflictDecision.keepLocal) },
                actorId: user.id
            )
        }

        // Clean up exported file
        try? FileManager.default.removeItem(atPath: export.filePath)
    }

    @Test("Sync: export creates file with SHA-256 checksum")
    func exportChecksum() async throws {
        let (db, syncService, postingService, userRepo) = try makeDB()
        let user = try await makeUser(userRepo: userRepo)

        let export = try await syncService.export(
            entityTypes: ["postings"], startDate: nil, endDate: nil, exportedBy: user.id
        )
        #expect(export.checksumSha256.count == 64) // SHA-256 hex = 64 chars
        try? FileManager.default.removeItem(atPath: export.filePath)
    }

    // MARK: - Delta / Cursor Lifecycle

    @Test("Delta: first sync with no cursor exports all records (full export)")
    func deltaFirstSyncIsFullExport() async throws {
        let (_, syncService, postingService, userRepo) = try makeDB()
        let user = try await makeUser(userRepo: userRepo)

        _ = try await postingService.create(
            actorId: user.id, title: "First Posting", siteAddress: "1 Main St",
            dueDate: Date().addingTimeInterval(86400), budgetCents: 1000,
            acceptanceMode: .open, watermarkEnabled: false
        )

        // No cursor for this peer yet — should be a full export
        let delta = try await syncService.exportDelta(
            peerId: "peer-first-sync", entityTypes: ["postings"], exportedBy: user.id
        )
        #expect(delta.recordCount == 1)

        // Cursor must NOT be advanced — no confirmation yet
        let cursors = try await syncService.listCursors(peerId: "peer-first-sync", actorId: user.id)
        #expect(cursors.isEmpty)

        try? FileManager.default.removeItem(atPath: delta.filePath)
    }

    @Test("Delta: cursor not advanced by exportDelta — only by confirmExportDelivered")
    func cursorNotAdvancedUntilConfirmed() async throws {
        let (_, syncService, postingService, userRepo) = try makeDB()
        let user = try await makeUser(userRepo: userRepo)

        _ = try await postingService.create(
            actorId: user.id, title: "Test Posting", siteAddress: "2 Side St",
            dueDate: Date().addingTimeInterval(86400), budgetCents: 500,
            acceptanceMode: .open, watermarkEnabled: false
        )

        let export = try await syncService.exportDelta(
            peerId: "peer-no-confirm", entityTypes: ["postings"], exportedBy: user.id
        )

        // Cursor still absent — not advanced by export generation alone
        let before = try await syncService.listCursors(peerId: "peer-no-confirm", actorId: user.id)
        #expect(before.isEmpty)

        // Confirm delivery → cursor advances to exportedAt
        try await syncService.confirmExportDelivered(
            peerId: "peer-no-confirm", entityTypes: ["postings"],
            exportedAt: export.exportedAt, actorId: user.id
        )

        let after = try await syncService.listCursors(peerId: "peer-no-confirm", actorId: user.id)
        #expect(after.count == 1)
        #expect(after.first?.entityType == "postings")
        // Compare within 1s tolerance — SQLite date round-trip may lose sub-second precision
        if let storedAt = after.first?.lastSyncedAt {
            #expect(abs(storedAt.timeIntervalSince(export.exportedAt)) < 1.0)
        }

        try? FileManager.default.removeItem(atPath: export.filePath)
    }

    @Test("Delta: unconfirmed export retried — same records re-exported, no data skipped")
    func retryWithoutConfirmationExportsSameRecords() async throws {
        let (_, syncService, postingService, userRepo) = try makeDB()
        let user = try await makeUser(userRepo: userRepo)

        _ = try await postingService.create(
            actorId: user.id, title: "Retry Test", siteAddress: "3 Retry Rd",
            dueDate: Date().addingTimeInterval(86400), budgetCents: 200,
            acceptanceMode: .open, watermarkEnabled: false
        )

        let first = try await syncService.exportDelta(
            peerId: "peer-retry", entityTypes: ["postings"], exportedBy: user.id
        )
        // Transfer fails — no confirmExportDelivered call

        // Retry: cursor not advanced so same delta is produced
        let retry = try await syncService.exportDelta(
            peerId: "peer-retry", entityTypes: ["postings"], exportedBy: user.id
        )
        #expect(retry.recordCount == first.recordCount)

        try? FileManager.default.removeItem(atPath: first.filePath)
        try? FileManager.default.removeItem(atPath: retry.filePath)
    }

    @Test("Delta: second sync after confirmation only exports records updated after cursor")
    func secondSyncAfterConfirmationIsIncremental() async throws {
        let (_, syncService, postingService, userRepo) = try makeDB()
        let user = try await makeUser(userRepo: userRepo)

        _ = try await postingService.create(
            actorId: user.id, title: "Before Cursor", siteAddress: "4 Old St",
            dueDate: Date().addingTimeInterval(86400), budgetCents: 100,
            acceptanceMode: .open, watermarkEnabled: false
        )

        // First sync: export and confirm
        let firstExport = try await syncService.exportDelta(
            peerId: "peer-incremental", entityTypes: ["postings"], exportedBy: user.id
        )
        #expect(firstExport.recordCount == 1)
        try await syncService.confirmExportDelivered(
            peerId: "peer-incremental", entityTypes: ["postings"],
            exportedAt: firstExport.exportedAt, actorId: user.id
        )

        // Brief pause to ensure new posting has a strictly later updatedAt
        try await Task.sleep(nanoseconds: 20_000_000) // 20ms

        // Create a new posting after cursor was set
        _ = try await postingService.create(
            actorId: user.id, title: "After Cursor", siteAddress: "5 New St",
            dueDate: Date().addingTimeInterval(86400), budgetCents: 300,
            acceptanceMode: .open, watermarkEnabled: false
        )

        // Second delta should only contain the new posting
        let secondExport = try await syncService.exportDelta(
            peerId: "peer-incremental", entityTypes: ["postings"], exportedBy: user.id
        )
        #expect(secondExport.recordCount == 1)

        try? FileManager.default.removeItem(atPath: firstExport.filePath)
        try? FileManager.default.removeItem(atPath: secondExport.filePath)
    }

    @Test("Delta: recordImportedFrom advances import-side cursor per entity type")
    func recordImportedFromAdvancesCursor() async throws {
        let (_, syncService, _, userRepo) = try makeDB()
        let user = try await makeUser(userRepo: userRepo)

        let syncedAt = Date()
        try await syncService.recordImportedFrom(
            peerId: "remote-peer",
            entityTypes: ["postings", "tasks"],
            syncedAt: syncedAt,
            actorId: user.id
        )

        let cursors = try await syncService.listCursors(peerId: "remote-peer", actorId: user.id)
        #expect(cursors.count == 2)
        let entityTypeSet = Set(cursors.map { $0.entityType })
        #expect(entityTypeSet == ["postings", "tasks"])
        for cursor in cursors {
            // Compare within 1s tolerance — SQLite date round-trip may lose sub-second precision
            #expect(abs(cursor.lastSyncedAt.timeIntervalSince(syncedAt)) < 1.0)
        }
    }

    @Test("Delta: per-entity cursors are independent — stale task cursor does not over-export postings")
    func perEntityCursorsAreIndependent() async throws {
        let (_, syncService, postingService, userRepo) = try makeDB()
        let user = try await makeUser(userRepo: userRepo)

        _ = try await postingService.create(
            actorId: user.id, title: "Posting A", siteAddress: "6 Independent Ave",
            dueDate: Date().addingTimeInterval(86400), budgetCents: 100,
            acceptanceMode: .open, watermarkEnabled: false
        )

        // Sync only postings and confirm — postings cursor advances
        let postingsExport = try await syncService.exportDelta(
            peerId: "peer-independent", entityTypes: ["postings"], exportedBy: user.id
        )
        try await syncService.confirmExportDelivered(
            peerId: "peer-independent", entityTypes: ["postings"],
            exportedAt: postingsExport.exportedAt, actorId: user.id
        )

        // Brief pause to ensure new posting has later updatedAt
        try await Task.sleep(nanoseconds: 20_000_000)

        _ = try await postingService.create(
            actorId: user.id, title: "Posting B", siteAddress: "7 Later Ave",
            dueDate: Date().addingTimeInterval(86400), budgetCents: 200,
            acceptanceMode: .open, watermarkEnabled: false
        )

        // Multi-entity delta: tasks have no cursor (nil = full), postings have cursor
        let multiExport = try await syncService.exportDelta(
            peerId: "peer-independent", entityTypes: ["postings", "tasks"], exportedBy: user.id
        )
        // Postings: only Posting B (after cursor); tasks: full export (no cursor = 0 tasks)
        #expect(multiExport.recordCount == 1) // only Posting B

        try? FileManager.default.removeItem(atPath: postingsExport.filePath)
        try? FileManager.default.removeItem(atPath: multiExport.filePath)
    }

    // MARK: - Import Cursor / Manifest Watermark

    @Test("Import: SyncImport record stores source manifest exportedAt and entityTypes")
    func importStoresManifestMetadata() async throws {
        let (_, syncService, postingService, userRepo) = try makeDB()
        let user = try await makeUser(userRepo: userRepo)

        _ = try await postingService.create(
            actorId: user.id, title: "Manifest Test", siteAddress: "8 Meta St",
            dueDate: Date().addingTimeInterval(86400), budgetCents: 100,
            acceptanceMode: .open, watermarkEnabled: false
        )

        // Export with a known set of entity types
        let export = try await syncService.export(
            entityTypes: ["postings"], startDate: nil, endDate: nil, exportedBy: user.id
        )
        let sourceExportedAt = export.exportedAt

        // Import the file — manifest fields should be captured on the SyncImport record
        let importURL = URL(fileURLWithPath: export.filePath)
        let (syncImport, _) = try await syncService.importFile(fileURL: importURL, importedBy: user.id)

        // sourceExportedAt must equal the export's exportedAt (within 1s for SQLite precision)
        #expect(syncImport.sourceExportedAt != nil)
        if let stored = syncImport.sourceExportedAt {
            #expect(abs(stored.timeIntervalSince(sourceExportedAt)) < 1.0,
                    "Import cursor watermark should match source exportedAt, not local clock")
        }

        // sourceEntityTypes must contain the manifest's entity types
        #expect(syncImport.sourceEntityTypes != nil)
        if let json = syncImport.sourceEntityTypes,
           let data = json.data(using: .utf8),
           let parsed = try? JSONSerialization.jsonObject(with: data) as? [String] {
            #expect(parsed.contains("postings"))
            #expect(parsed.count == 1)
        }

        try? FileManager.default.removeItem(atPath: export.filePath)
    }

    @Test("Import cursor uses manifest exportedAt — not local importedAt — as watermark")
    func importCursorWatermarkIsManifestExportedAt() async throws {
        let (_, syncService, postingService, userRepo) = try makeDB()
        let user = try await makeUser(userRepo: userRepo)

        _ = try await postingService.create(
            actorId: user.id, title: "Watermark Test", siteAddress: "9 Clock Ave",
            dueDate: Date().addingTimeInterval(86400), budgetCents: 200,
            acceptanceMode: .open, watermarkEnabled: false
        )

        // Export — capture its exportedAt as the expected watermark
        let export = try await syncService.export(
            entityTypes: ["postings"], startDate: nil, endDate: nil, exportedBy: user.id
        )
        let expectedWatermark = export.exportedAt

        // Simulate delay before importing (local importedAt will be later than exportedAt)
        try await Task.sleep(nanoseconds: 30_000_000) // 30 ms

        let importURL = URL(fileURLWithPath: export.filePath)
        let (syncImport, _) = try await syncService.importFile(fileURL: importURL, importedBy: user.id)

        // importedAt should be strictly later than sourceExportedAt
        #expect(syncImport.importedAt > syncImport.sourceExportedAt ?? syncImport.importedAt,
                "importedAt should be after exportedAt due to deliberate delay")

        // Simulate what the ViewModel does: advance cursor to sourceExportedAt (not importedAt)
        let watermark = syncImport.sourceExportedAt ?? syncImport.importedAt
        try await syncService.recordImportedFrom(
            peerId: "source-peer-watermark",
            entityTypes: ["postings"],
            syncedAt: watermark,
            actorId: user.id
        )

        // The cursor should be at the manifest's exportedAt, not the later importedAt
        let cursors = try await syncService.listCursors(peerId: "source-peer-watermark", actorId: user.id)
        #expect(cursors.count == 1)
        if let cursor = cursors.first {
            #expect(abs(cursor.lastSyncedAt.timeIntervalSince(expectedWatermark)) < 1.0,
                    "Cursor should be at source exportedAt, not local importedAt")
            // Confirm cursor is strictly earlier than local importedAt
            #expect(cursor.lastSyncedAt <= syncImport.importedAt)
        }

        try? FileManager.default.removeItem(atPath: export.filePath)
    }

    @Test("Import cursor entity scope uses manifest entityTypes — not caller entity types")
    func importCursorEntityScopeIsFromManifest() async throws {
        let (_, syncService, postingService, userRepo) = try makeDB()
        let user = try await makeUser(userRepo: userRepo)

        _ = try await postingService.create(
            actorId: user.id, title: "Scope Test", siteAddress: "10 Scope Rd",
            dueDate: Date().addingTimeInterval(86400), budgetCents: 300,
            acceptanceMode: .open, watermarkEnabled: false
        )

        // Export only "postings" — the manifest entityTypes is ["postings"]
        let export = try await syncService.export(
            entityTypes: ["postings"], startDate: nil, endDate: nil, exportedBy: user.id
        )

        let importURL = URL(fileURLWithPath: export.filePath)
        let (syncImport, _) = try await syncService.importFile(fileURL: importURL, importedBy: user.id)

        // Parse manifest entityTypes from the import record
        var manifestEntityTypes: [String] = []
        if let json = syncImport.sourceEntityTypes,
           let data = json.data(using: .utf8),
           let parsed = try? JSONSerialization.jsonObject(with: data) as? [String] {
            manifestEntityTypes = parsed
        }

        // The manifest only includes "postings" — even if caller also wants "tasks"
        #expect(manifestEntityTypes == ["postings"],
                "Cursor scope must match manifest entity types, not caller-supplied list")
        #expect(!manifestEntityTypes.contains("tasks"),
                "Cursor for 'tasks' should NOT be created from a postings-only export")

        // Advance cursor using only manifest types
        let watermark = syncImport.sourceExportedAt ?? syncImport.importedAt
        try await syncService.recordImportedFrom(
            peerId: "source-peer-scope",
            entityTypes: manifestEntityTypes,
            syncedAt: watermark,
            actorId: user.id
        )

        let cursors = try await syncService.listCursors(peerId: "source-peer-scope", actorId: user.id)
        #expect(cursors.count == 1) // only "postings", not "tasks"
        #expect(cursors.first?.entityType == "postings")

        try? FileManager.default.removeItem(atPath: export.filePath)
    }
}
