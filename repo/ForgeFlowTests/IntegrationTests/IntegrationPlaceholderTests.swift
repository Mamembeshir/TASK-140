import Foundation
import Testing
import GRDB
@testable import ForgeFlow

// MARK: - Shared helpers

private func makeDB() throws -> DatabaseManager { try DatabaseManager(inMemory: true) }

private func makeUser(
    pool: DatabasePool,
    username: String? = nil,
    role: Role = .admin,
    quota: Int = 2_147_483_648
) async throws -> User {
    let now = Date()
    let u = User(
        id: UUID(),
        username: username ?? UUID().uuidString,
        role: role, status: .active,
        failedLoginCount: 0, lockedUntil: nil,
        biometricEnabled: false, dndStartTime: nil, dndEndTime: nil,
        storageQuotaBytes: quota,
        version: 1, createdAt: now, updatedAt: now
    )
    try await pool.write { db in try u.insert(db) }
    return u
}

private func makePosting(pool: DatabasePool, adminId: UUID) async throws -> ServicePosting {
    let svc = PostingService(
        dbPool: pool,
        postingRepository: PostingRepository(dbPool: pool),
        taskRepository: TaskRepository(dbPool: pool),
        userRepository: UserRepository(dbPool: pool),
        auditService: AuditService(dbPool: pool)
    )
    return try await svc.create(
        actorId: adminId, title: "Test Posting", siteAddress: "123 Main",
        dueDate: Date().addingTimeInterval(86400), budgetCents: 5000,
        acceptanceMode: .inviteOnly, watermarkEnabled: false
    )
}

// MARK: - Schema Integrity Tests

@Suite("Schema Integrity", .serialized)
struct SchemaIntegrityTests {

    @Test func allExpectedTablesExistAfterMigrations() async throws {
        let db = try makeDB()
        let tables = try await db.dbPool.read { db in
            try String.fetchAll(db, sql:
                "SELECT name FROM sqlite_master WHERE type='table' ORDER BY name"
            )
        }
        let expected: [String] = [
            "assignments", "attachments", "audit_entries", "comments",
            "connector_definitions", "dependencies", "notifications",
            "plugin_approvals", "plugin_definitions", "plugin_fields",
            "plugin_test_results", "posting_field_values",
            "service_postings", "sync_cursors", "sync_exports", "sync_imports",
            "tasks", "users"
        ]
        for table in expected {
            #expect(tables.contains(table), "Missing table: \(table)")
        }
    }

    @Test func connectorsSeedExactlyTwoDisabledRows() async throws {
        let db = try makeDB()
        let (count, enabledCount) = try await db.dbPool.read { db -> (Int, Int) in
            let total = try Int.fetchOne(db, sql: "SELECT COUNT(*) FROM connector_definitions") ?? 0
            let enabled = try Int.fetchOne(db, sql:
                "SELECT COUNT(*) FROM connector_definitions WHERE isEnabled = 1") ?? 0
            return (total, enabled)
        }
        #expect(count == 2, "Expected EMAIL + SMS connectors")
        #expect(enabledCount == 0, "Both connectors must start disabled")
    }

    @Test func inMemoryDatabaseStartsEmpty() async throws {
        let db = try makeDB()
        let count = try await db.dbPool.read { db in
            try Int.fetchOne(db, sql: "SELECT COUNT(*) FROM users") ?? 0
        }
        #expect(count == 0)
    }
}

// MARK: - UNIQUE Constraint Tests

@Suite("UNIQUE Constraints", .serialized)
struct UniqueConstraintTests {

    @Test func duplicateUsernameIsRejected() async throws {
        let db = try makeDB()
        let now = Date()
        let user1 = User(
            id: UUID(), username: "duplicate_user", role: .admin, status: .active,
            failedLoginCount: 0, lockedUntil: nil, biometricEnabled: false,
            dndStartTime: nil, dndEndTime: nil,
            storageQuotaBytes: 2_147_483_648, version: 1, createdAt: now, updatedAt: now
        )
        try await db.dbPool.write { dbConn in try user1.insert(dbConn) }

        let user2 = User(
            id: UUID(), username: "duplicate_user", role: .technician, status: .active,
            failedLoginCount: 0, lockedUntil: nil, biometricEnabled: false,
            dndStartTime: nil, dndEndTime: nil,
            storageQuotaBytes: 2_147_483_648, version: 1, createdAt: now, updatedAt: now
        )
        do {
            try await db.dbPool.write { dbConn in try user2.insert(dbConn) }
            Issue.record("Duplicate username should have been rejected")
        } catch {
            // Expected: UNIQUE constraint violation
            let desc = String(describing: error).lowercased()
            #expect(desc.contains("unique") || desc.contains("constraint") || desc.contains("duplicate"))
        }
    }

    @Test func duplicateAssignmentIsRejected() async throws {
        let db = try makeDB()
        let admin = try await makeUser(pool: db.dbPool)
        let tech = try await makeUser(pool: db.dbPool, role: .technician)
        let posting = try await makePosting(pool: db.dbPool, adminId: admin.id)

        let now = Date()
        let a1 = Assignment(
            id: UUID(), postingId: posting.id, technicianId: tech.id,
            status: .invited, acceptedAt: nil, auditNote: nil,
            version: 1, createdAt: now, updatedAt: now
        )
        let a2 = Assignment(
            id: UUID(), postingId: posting.id, technicianId: tech.id,
            status: .invited, acceptedAt: nil, auditNote: nil,
            version: 1, createdAt: now, updatedAt: now
        )
        try await db.dbPool.write { dbConn in try a1.insert(dbConn) }
        do {
            try await db.dbPool.write { dbConn in try a2.insert(dbConn) }
            Issue.record("Duplicate assignment (postingId, technicianId) should fail")
        } catch {
            let desc = String(describing: error).lowercased()
            #expect(desc.contains("unique") || desc.contains("constraint"))
        }
    }

    @Test func duplicateDependencyIsRejected() async throws {
        let db = try makeDB()
        let admin = try await makeUser(pool: db.dbPool)
        let posting = try await makePosting(pool: db.dbPool, adminId: admin.id)
        let rootTask = try await TaskRepository(dbPool: db.dbPool).findByPosting(posting.id)[0]

        let now = Date()
        let task2 = ForgeTask(
            id: UUID(), postingId: posting.id, parentTaskId: nil,
            title: "T2", taskDescription: nil, priority: .p2,
            status: .notStarted, blockedComment: nil, assignedTo: nil,
            sortOrder: 1, version: 1, createdAt: now, updatedAt: now
        )
        try await db.dbPool.write { dbConn in try task2.insert(dbConn) }

        let dep1 = Dependency(id: UUID(), taskId: task2.id, dependsOnTaskId: rootTask.id, type: .finishToStart)
        let dep2 = Dependency(id: UUID(), taskId: task2.id, dependsOnTaskId: rootTask.id, type: .finishToStart)
        try await db.dbPool.write { dbConn in try dep1.insert(dbConn) }
        do {
            try await db.dbPool.write { dbConn in try dep2.insert(dbConn) }
            Issue.record("Duplicate dependency (taskId, dependsOnTaskId) should fail")
        } catch {
            let desc = String(describing: error).lowercased()
            #expect(desc.contains("unique") || desc.contains("constraint"))
        }
    }
}

// MARK: - Cascade Delete Tests
//
// Note: service_postings cascade to tasks via tasks.postingId (CASCADE).
// However tasks.parentTaskId → tasks uses onDelete: .restrict, so deleting a
// posting with a parent-child task tree requires deleting children first.
// These tests use manually-created flat tasks (no parent) to verify cascade
// semantics cleanly, plus a direct subtask hierarchy removal test.

@Suite("Cascade Deletes", .serialized)
struct CascadeDeleteTests {

    /// Helper: inserts a standalone task (no parent) for a given posting.
    private func insertFlatTask(pool: DatabasePool, postingId: UUID) async throws -> ForgeTask {
        let now = Date()
        var task = ForgeTask(
            id: UUID(), postingId: postingId, parentTaskId: nil,
            title: "Flat Task", taskDescription: nil, priority: .p2,
            status: .notStarted, blockedComment: nil, assignedTo: nil,
            sortOrder: 99, version: 1, createdAt: now, updatedAt: now
        )
        try await pool.write { db in try task.insert(db) }
        return task
    }

    @Test func postingHasFiveAutoGeneratedTasks() async throws {
        // Verify PostingService.create generates 1 root + 4 subtasks
        let db = try makeDB()
        let admin = try await makeUser(pool: db.dbPool)
        let posting = try await makePosting(pool: db.dbPool, adminId: admin.id)
        let tasks = try await TaskRepository(dbPool: db.dbPool).findByPosting(posting.id)
        #expect(tasks.count == 5, "1 root + 4 auto-subtasks (Site Assessment, Execute Work, Quality Check, Documentation)")
    }

    @Test func deletingAssignmentClearsItFromPosting() async throws {
        let db = try makeDB()
        let admin = try await makeUser(pool: db.dbPool)
        let tech  = try await makeUser(pool: db.dbPool, role: .technician)
        let posting = try await makePosting(pool: db.dbPool, adminId: admin.id)
        let now = Date()

        var assignment = Assignment(
            id: UUID(), postingId: posting.id, technicianId: tech.id,
            status: .invited, acceptedAt: nil, auditNote: nil,
            version: 1, createdAt: now, updatedAt: now
        )
        try await db.dbPool.write { dbConn in try assignment.insert(dbConn) }

        let before = try await AssignmentRepository(dbPool: db.dbPool).findByPosting(posting.id)
        #expect(before.count == 1)

        // Delete the assignment directly
        try await db.dbPool.write { dbConn in try assignment.delete(dbConn) }

        let after = try await AssignmentRepository(dbPool: db.dbPool).findByPosting(posting.id)
        #expect(after.isEmpty)
    }

    @Test func deletingFlatTaskCascadesToItsDependencies() async throws {
        let db = try makeDB()
        let admin = try await makeUser(pool: db.dbPool)
        let posting = try await makePosting(pool: db.dbPool, adminId: admin.id)

        // Two flat tasks: no parent-child relationship, so neither has RESTRICT constraints
        var task1 = try await insertFlatTask(pool: db.dbPool, postingId: posting.id)
        let task2 = try await insertFlatTask(pool: db.dbPool, postingId: posting.id)

        let depRepo = DependencyRepository(dbPool: db.dbPool)
        let dep = Dependency(id: UUID(), taskId: task1.id, dependsOnTaskId: task2.id, type: .finishToStart)
        try await db.dbPool.write { dbConn in try depRepo.insertInTransaction(db: dbConn, dep) }

        // Delete task1 — its dependencies (taskId = task1) must cascade
        try await db.dbPool.write { dbConn in try task1.delete(dbConn) }

        let remaining = try await depRepo.findByTask(task1.id)
        #expect(remaining.isEmpty, "Deleting a task cascades to its dependency rows")
    }

    @Test func deletingCommentCascadesToReplies() async throws {
        let db = try makeDB()
        let admin = try await makeUser(pool: db.dbPool)
        let posting = try await makePosting(pool: db.dbPool, adminId: admin.id)
        let now = Date()

        var parent = Comment(
            id: UUID(), postingId: posting.id, taskId: nil,
            authorId: admin.id, body: "parent", parentCommentId: nil, createdAt: now
        )
        let reply = Comment(
            id: UUID(), postingId: posting.id, taskId: nil,
            authorId: admin.id, body: "reply", parentCommentId: parent.id, createdAt: now
        )
        try await db.dbPool.write { dbConn in
            try parent.insert(dbConn)
            try reply.insert(dbConn)
        }

        // Deleting the parent should cascade to the reply
        try await db.dbPool.write { dbConn in try parent.delete(dbConn) }

        let comments = try await CommentRepository(dbPool: db.dbPool).findByPosting(posting.id)
        #expect(comments.isEmpty, "Replies cascade when parent comment is deleted")
    }

    @Test func deletingPostingWithFlatTaskSucceeds() async throws {
        // A posting with only flat (non-parent) tasks can be cascade-deleted
        let db = try makeDB()
        let admin = try await makeUser(pool: db.dbPool)
        let now = Date()

        // Create posting directly (without PostingService) so no subtasks are generated
        var posting = ServicePosting(
            id: UUID(), title: "Direct Post", siteAddress: "Test",
            dueDate: Date().addingTimeInterval(86400), budgetCapCents: 1000,
            status: .draft, acceptanceMode: .inviteOnly, createdBy: admin.id,
            watermarkEnabled: false, version: 1, createdAt: now, updatedAt: now
        )
        try await db.dbPool.write { dbConn in try posting.insert(dbConn) }

        let flatTask = try await insertFlatTask(pool: db.dbPool, postingId: posting.id)

        // Delete the posting — since task has no parent, no RESTRICT blocks cascade
        try await db.dbPool.write { dbConn in try posting.delete(dbConn) }

        let remaining = try await TaskRepository(dbPool: db.dbPool).findByPosting(posting.id)
        #expect(remaining.isEmpty, "Flat task is cascade-deleted with posting")
    }
}

// MARK: - Optimistic Locking Tests

@Suite("Optimistic Locking", .serialized)
struct OptimisticLockingTests {

    @Test func updateWithLockingIncrementsVersion() async throws {
        let db = try makeDB()
        let pool = db.dbPool
        var user = try await makeUser(pool: pool)
        let originalVersion = user.version

        try await pool.write { dbConn in
            let repo = UserRepository(dbPool: pool)
            try repo.updateWithLocking(db: dbConn, user: &user)
        }

        let fetched = try await pool.read { dbConn in
            try User.filter(User.Columns.id == user.id).fetchOne(dbConn)
        }
        #expect(fetched?.version == originalVersion + 1)
        #expect(user.version == originalVersion + 1)
    }

    @Test func staleVersionThrowsStaleRecordError() async throws {
        let db = try makeDB()
        let pool = db.dbPool
        var user = try await makeUser(pool: pool)

        // Simulate a concurrent update by bumping the DB version ahead
        try await pool.write { dbConn in
            try dbConn.execute(
                sql: "UPDATE users SET version = version + 1 WHERE id = ?",
                arguments: [user.id]
            )
        }

        // Now our in-memory user.version is stale
        do {
            try await pool.write { dbConn in
                let repo = UserRepository(dbPool: pool)
                try repo.updateWithLocking(db: dbConn, user: &user)
            }
            Issue.record("Expected StaleRecordError but update succeeded")
        } catch let err as StaleRecordError {
            #expect(err.entityType == "User")
            #expect(err.entityId == user.id)
        } catch {
            Issue.record("Expected StaleRecordError, got: \(error)")
        }
    }

    @Test func postingUpdateWithLockingIncrementsVersion() async throws {
        let db = try makeDB()
        let pool = db.dbPool
        let admin = try await makeUser(pool: pool)
        var posting = try await makePosting(pool: pool, adminId: admin.id)
        let originalVersion = posting.version

        try await pool.write { dbConn in
            let repo = PostingRepository(dbPool: pool)
            try repo.updateWithLocking(db: dbConn, posting: &posting)
        }
        #expect(posting.version == originalVersion + 1)
    }

    @Test func taskUpdateWithLockingIncrementsVersion() async throws {
        let db = try makeDB()
        let pool = db.dbPool
        let admin = try await makeUser(pool: pool)
        let posting = try await makePosting(pool: pool, adminId: admin.id)
        var task = try await TaskRepository(dbPool: pool).findByPosting(posting.id)[0]
        let originalVersion = task.version

        try await pool.write { dbConn in
            let repo = TaskRepository(dbPool: pool)
            try repo.updateWithLocking(db: dbConn, task: &task)
        }
        #expect(task.version == originalVersion + 1)
    }
}

// MARK: - Audit Service Integration Tests

@Suite("AuditService Integration", .serialized)
struct AuditServiceIntegrationTests {

    @Test func auditEntryIsWrittenAndReadable() async throws {
        let db = try makeDB()
        let pool = db.dbPool
        // audit_entries.actorId has a FK → users, so actorId must exist in users
        let actor = try await makeUser(pool: pool)
        let entityId = UUID()

        try await pool.write { dbConn in
            try AuditService(dbPool: pool).record(
                db: dbConn, actorId: actor.id,
                action: "TEST_ACTION",
                entityType: "TestEntity",
                entityId: entityId,
                afterData: "{\"key\":\"value\"}"
            )
        }

        let count = try await pool.read { dbConn in
            try Int.fetchOne(dbConn, sql:
                "SELECT COUNT(*) FROM audit_entries WHERE action = 'TEST_ACTION'"
            ) ?? 0
        }
        #expect(count == 1)
    }

    @Test func auditEntryPreservesActorAndEntity() async throws {
        let db = try makeDB()
        let pool = db.dbPool
        let actor = try await makeUser(pool: pool)
        let entityId = UUID()

        try await pool.write { dbConn in
            try AuditService(dbPool: pool).record(
                db: dbConn, actorId: actor.id,
                action: "FIELD_CHECK",
                entityType: "Comment",
                entityId: entityId,
                afterData: nil
            )
        }

        let row = try await pool.read { dbConn -> Row? in
            try Row.fetchOne(dbConn, sql:
                "SELECT entityType FROM audit_entries WHERE action = 'FIELD_CHECK'"
            )
        }
        #expect(row != nil)
        #expect(row?["entityType"] as? String == "Comment")
    }

    @Test func multipleAuditEntriesStackCorrectly() async throws {
        let db = try makeDB()
        let pool = db.dbPool
        // actorId must reference a real user (audit_entries.actorId FK → users)
        let actor = try await makeUser(pool: pool)

        try await pool.write { dbConn in
            let svc = AuditService(dbPool: pool)
            for i in 0..<5 {
                try svc.record(
                    db: dbConn, actorId: actor.id,
                    action: "ACTION_\(i)",
                    entityType: "Entity", entityId: UUID(),
                    afterData: nil
                )
            }
        }

        // Count the 5 entries we just inserted (actor.id is unique per test)
        let count = try await pool.read { dbConn in
            try Int.fetchOne(dbConn, sql:
                "SELECT COUNT(*) FROM audit_entries WHERE action LIKE 'ACTION_%'"
            ) ?? 0
        }
        #expect(count == 5)
    }
}

// MARK: - Entity Round-Trip Tests

@Suite("Entity Round-Trips", .serialized)
struct EntityRoundTripTests {

    @Test func userRoundTripPreservesAllFields() async throws {
        let db = try makeDB()
        let now = Date(timeIntervalSince1970: Date().timeIntervalSince1970.rounded())
        let user = User(
            id: UUID(), username: "roundtrip_user", role: .coordinator, status: .active,
            failedLoginCount: 3, lockedUntil: nil, biometricEnabled: true,
            dndStartTime: "22:00", dndEndTime: "07:00",
            storageQuotaBytes: 1_073_741_824, version: 2, createdAt: now, updatedAt: now
        )
        try await db.dbPool.write { dbConn in try user.insert(dbConn) }

        let fetched = try await db.dbPool.read { dbConn in
            try User.filter(User.Columns.username == "roundtrip_user").fetchOne(dbConn)
        }
        #expect(fetched != nil)
        #expect(fetched?.role == .coordinator)
        #expect(fetched?.failedLoginCount == 3)
        #expect(fetched?.biometricEnabled == true)
        #expect(fetched?.dndStartTime == "22:00")
        #expect(fetched?.dndEndTime == "07:00")
        #expect(fetched?.storageQuotaBytes == 1_073_741_824)
        #expect(fetched?.version == 2)
    }

    @Test func taskRoundTripPreservesAllFields() async throws {
        let db = try makeDB()
        let admin = try await makeUser(pool: db.dbPool)
        let posting = try await makePosting(pool: db.dbPool, adminId: admin.id)
        let now = Date(timeIntervalSince1970: Date().timeIntervalSince1970.rounded())

        let task = ForgeTask(
            id: UUID(), postingId: posting.id, parentTaskId: nil,
            title: "Round-Trip Task", taskDescription: "some description",
            priority: .p1, status: .notStarted,
            blockedComment: nil, assignedTo: admin.id,
            sortOrder: 5, version: 1, createdAt: now, updatedAt: now
        )
        try await db.dbPool.write { dbConn in try task.insert(dbConn) }

        let fetched = try await TaskRepository(dbPool: db.dbPool).findById(task.id)
        #expect(fetched != nil)
        #expect(fetched?.title == "Round-Trip Task")
        #expect(fetched?.taskDescription == "some description")
        #expect(fetched?.priority == .p1)
        #expect(fetched?.assignedTo == admin.id)
        #expect(fetched?.sortOrder == 5)
    }

    @Test func assignmentRoundTripPreservesAllFields() async throws {
        let db = try makeDB()
        let admin = try await makeUser(pool: db.dbPool)
        let tech = try await makeUser(pool: db.dbPool, role: .technician)
        let posting = try await makePosting(pool: db.dbPool, adminId: admin.id)
        let now = Date(timeIntervalSince1970: Date().timeIntervalSince1970.rounded())
        let acceptedAt = now.addingTimeInterval(60)

        let assignment = Assignment(
            id: UUID(), postingId: posting.id, technicianId: tech.id,
            status: .accepted, acceptedAt: acceptedAt,
            auditNote: "First accepted", version: 2,
            createdAt: now, updatedAt: now
        )
        try await db.dbPool.write { dbConn in try assignment.insert(dbConn) }

        let fetched = try await AssignmentRepository(dbPool: db.dbPool)
            .findById(assignment.id)
        #expect(fetched != nil)
        #expect(fetched?.status == .accepted)
        #expect(fetched?.auditNote == "First accepted")
        #expect(fetched?.version == 2)
        #expect(fetched?.technicianId == tech.id)
    }

    @Test func commentRoundTripPreservesAllFields() async throws {
        let db = try makeDB()
        let admin = try await makeUser(pool: db.dbPool)
        let posting = try await makePosting(pool: db.dbPool, adminId: admin.id)
        let now = Date(timeIntervalSince1970: Date().timeIntervalSince1970.rounded())

        let parent = Comment(
            id: UUID(), postingId: posting.id, taskId: nil,
            authorId: admin.id, body: "parent comment",
            parentCommentId: nil, createdAt: now
        )
        let reply = Comment(
            id: UUID(), postingId: posting.id, taskId: nil,
            authorId: admin.id, body: "child reply",
            parentCommentId: parent.id, createdAt: now
        )
        try await db.dbPool.write { dbConn in
            try parent.insert(dbConn)
            try reply.insert(dbConn)
        }

        let fetched = try await CommentRepository(dbPool: db.dbPool).findById(reply.id)
        #expect(fetched?.body == "child reply")
        #expect(fetched?.parentCommentId == parent.id)
        #expect(fetched?.postingId == posting.id)
    }

    @Test func notificationRoundTripPreservesAllFields() async throws {
        let db = try makeDB()
        let admin = try await makeUser(pool: db.dbPool)
        let posting = try await makePosting(pool: db.dbPool, adminId: admin.id)
        let now = Date(timeIntervalSince1970: Date().timeIntervalSince1970.rounded())

        var notification = ForgeNotification(
            id: UUID(), recipientId: admin.id,
            eventType: .commentAdded, postingId: posting.id,
            title: "Test Title", body: "Test Body",
            status: .pending, createdAt: now, updatedAt: now
        )
        try await db.dbPool.write { dbConn in try notification.insert(dbConn) }

        let fetched = try await NotificationRepository(dbPool: db.dbPool)
            .findById(notification.id)
        #expect(fetched != nil)
        #expect(fetched?.title == "Test Title")
        #expect(fetched?.body == "Test Body")
        #expect(fetched?.eventType == .commentAdded)
        #expect(fetched?.status == .pending)
        #expect(fetched?.postingId == posting.id)
    }
}

// MARK: - Foreign Key Enforcement Tests

@Suite("Foreign Key Enforcement", .serialized)
struct ForeignKeyEnforcementTests {

    @Test func attachmentWithUnknownPostingIsRejected() async throws {
        let db = try makeDB()
        let user = try await makeUser(pool: db.dbPool)
        let now = Date()
        let fakePostingId = UUID()

        do {
            try await db.dbPool.write { dbConn in
                try dbConn.execute(sql: """
                    INSERT INTO attachments
                    (id, postingId, fileName, filePath, fileSizeBytes, mimeType,
                     checksumSha256, isCompressed, uploadedBy, createdAt)
                    VALUES (?, ?, 'f.jpg', 'f.jpg', 1024, 'image/jpeg', 'abc123', 0, ?, ?)
                    """,
                    arguments: [UUID(), fakePostingId, user.id, now])
            }
            Issue.record("Expected FK violation but insert succeeded")
        } catch {
            let desc = String(describing: error).lowercased()
            #expect(desc.contains("foreign key") || desc.contains("constraint"))
        }
    }

    @Test func commentWithUnknownPostingIsRejected() async throws {
        let db = try makeDB()
        let user = try await makeUser(pool: db.dbPool)
        let now = Date()

        do {
            try await db.dbPool.write { dbConn in
                try dbConn.execute(sql: """
                    INSERT INTO comments
                    (id, postingId, authorId, body, createdAt)
                    VALUES (?, ?, ?, 'body text', ?)
                    """,
                    arguments: [UUID(), UUID(), user.id, now])
            }
            Issue.record("Expected FK violation but insert succeeded")
        } catch {
            let desc = String(describing: error).lowercased()
            #expect(desc.contains("foreign key") || desc.contains("constraint"))
        }
    }

    @Test func taskWithUnknownPostingIsRejected() async throws {
        let db = try makeDB()
        let now = Date()

        do {
            try await db.dbPool.write { dbConn in
                try dbConn.execute(sql: """
                    INSERT INTO tasks
                    (id, postingId, title, priority, status, sortOrder, version, createdAt, updatedAt)
                    VALUES (?, ?, 'Bad Task', 'P2', 'NOT_STARTED', 0, 1, ?, ?)
                    """,
                    arguments: [UUID(), UUID(), now, now])
            }
            Issue.record("Expected FK violation but insert succeeded")
        } catch {
            let desc = String(describing: error).lowercased()
            #expect(desc.contains("foreign key") || desc.contains("constraint"))
        }
    }
}
