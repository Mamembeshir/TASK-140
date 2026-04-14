import Foundation
import Testing
import GRDB
@testable import ForgeFlow

@Suite("Integration Tests")
struct IntegrationTests {
    @Test("Database manager initializes with in-memory database")
    func databaseManagerInMemory() async throws {
        let dbManager = try DatabaseManager(inMemory: true)
        let count = try await dbManager.dbPool.read { db in
            try Int.fetchOne(db, sql: "SELECT COUNT(*) FROM users")
        }
        #expect(count == 0)
    }

    @Test("All 18 schema tables are present after all 9 migrations run")
    func allExpectedTablesExistAfterMigration() async throws {
        let dbManager = try DatabaseManager(inMemory: true)
        let tables = try await dbManager.dbPool.read { db in
            try String.fetchAll(db, sql:
                "SELECT name FROM sqlite_master WHERE type='table' ORDER BY name"
            )
        }
        let expected: [String] = [
            // 001_InitialSchema
            "audit_entries", "sync_exports", "sync_imports", "users",
            // 002_PostingsSchema
            "assignments", "dependencies", "service_postings", "tasks",
            // 003_CommentsAttachmentsSchema
            "attachments", "comments",
            // 004_MessagingSchema
            "connector_definitions", "notifications",
            // 005_PluginSyncSchema
            "plugin_approvals", "plugin_definitions", "plugin_fields", "plugin_test_results",
            // 007_PostingFieldValues
            "posting_field_values",
            // 008_SyncCursorSchema
            "sync_cursors",
        ]
        for table in expected {
            #expect(tables.contains(table), "Expected table '\(table)' to exist after migrations")
        }
    }

    @Test("Migration 004 seeds exactly 2 disabled connector rows (EMAIL + SMS)")
    func connectorsSeededByMigration() async throws {
        let dbManager = try DatabaseManager(inMemory: true)
        let (count, enabledCount) = try await dbManager.dbPool.read { db in
            let total = try Int.fetchOne(db, sql: "SELECT COUNT(*) FROM connector_definitions") ?? 0
            let enabled = try Int.fetchOne(db, sql:
                "SELECT COUNT(*) FROM connector_definitions WHERE isEnabled = 1") ?? 0
            return (total, enabled)
        }
        #expect(count == 2, "Expected 2 seeded connectors (EMAIL + SMS)")
        #expect(enabledCount == 0, "Both connectors must be disabled at seed time (MSG-06)")
    }

    @Test("User insert and fetch round-trip preserves all fields")
    func userInsertAndFetchRoundTrip() async throws {
        let dbManager = try DatabaseManager(inMemory: true)
        let now = Date()
        let user = User(
            id: UUID(), username: "roundtrip_test", role: .coordinator, status: .active,
            failedLoginCount: 0, lockedUntil: nil, biometricEnabled: false,
            dndStartTime: "22:00", dndEndTime: "07:00",
            storageQuotaBytes: 1_073_741_824, version: 1,
            createdAt: now, updatedAt: now
        )
        try await dbManager.dbPool.write { db in try user.insert(db) }

        let fetched = try await dbManager.dbPool.read { db in
            try User.filter(User.Columns.username == "roundtrip_test").fetchOne(db)
        }
        #expect(fetched != nil)
        #expect(fetched?.username == "roundtrip_test")
        #expect(fetched?.role == .coordinator)
        #expect(fetched?.dndStartTime == "22:00")
        #expect(fetched?.dndEndTime == "07:00")
        #expect(fetched?.storageQuotaBytes == 1_073_741_824)
    }

    @Test("Foreign key enforcement: attachment referencing unknown posting is rejected")
    func foreignKeyEnforcementPreventsOrphanedAttachment() async throws {
        let dbManager = try DatabaseManager(inMemory: true)
        let now = Date()
        let user = User(
            id: UUID(), username: "fk_test_user", role: .admin, status: .active,
            failedLoginCount: 0, lockedUntil: nil, biometricEnabled: false,
            dndStartTime: nil, dndEndTime: nil,
            storageQuotaBytes: 2_147_483_648, version: 1,
            createdAt: now, updatedAt: now
        )
        try await dbManager.dbPool.write { db in try user.insert(db) }

        let nonExistentPostingId = UUID().uuidString
        do {
            try await dbManager.dbPool.write { db in
                try db.execute(sql: """
                    INSERT INTO attachments
                    (id, postingId, fileName, filePath, fileSizeBytes, mimeType,
                     checksumSha256, isCompressed, uploadedBy, createdAt)
                    VALUES (?, ?, 'test.jpg', 'test.jpg', 1024, 'image/jpeg',
                            'abc123', 0, ?, ?)
                    """,
                    arguments: [UUID().uuidString, nonExistentPostingId,
                                user.id.uuidString, now])
            }
            Issue.record("Expected foreign key violation, but insert succeeded")
        } catch {
            // Expected: GRDB / SQLite should throw a foreign key constraint error
            #expect(String(describing: error).contains("FOREIGN KEY") ||
                    String(describing: error).lowercased().contains("constraint"))
        }
    }
}
