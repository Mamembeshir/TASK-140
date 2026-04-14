import Foundation
import Testing
import GRDB
@testable import ForgeFlow

@Suite("Auth Integration Tests")
struct AuthIntegrationTests {
    private func makeServices() throws -> (AuthService, DatabasePool) {
        let dbManager = try DatabaseManager(inMemory: true)
        let dbPool = dbManager.dbPool
        let userRepo = UserRepository(dbPool: dbPool)
        let auditService = AuditService(dbPool: dbPool)
        let authService = AuthService(dbPool: dbPool, userRepository: userRepo, auditService: auditService)
        return (authService, dbPool)
    }

    private func seedAdmin(_ authService: AuthService, dbPool: DatabasePool) async throws -> User {
        // Create an initial admin to act as the creator
        let adminId = UUID()
        let now = Date()
        let admin = User(
            id: adminId,
            username: "seedadmin",
            role: .admin,
            status: .active,
            failedLoginCount: 0,
            lockedUntil: nil,
            biometricEnabled: false,
            dndStartTime: nil,
            dndEndTime: nil,
            storageQuotaBytes: 2_147_483_648,
            version: 1,
            createdAt: now,
            updatedAt: now
        )
        try await dbPool.write { db in try admin.insert(db) }
        let hash = HashValidator.sha256Hex(data: "AdminPass1".data(using: .utf8)!)
        try KeychainHelper.save(data: hash.data(using: .utf8)!, forKey: "forgeflow.password.\(adminId.uuidString)")
        return admin
    }

    @Test("Create user then login succeeds")
    func createAndLogin() async throws {
        let (authService, dbPool) = try makeServices()
        let admin = try await seedAdmin(authService, dbPool: dbPool)

        let newUser = try await authService.createUser(
            actorId: admin.id,
            username: "testuser",
            password: "TestPassword1",
            role: .technician
        )

        let loggedIn = try await authService.login(username: "testuser", password: "TestPassword1")
        #expect(loggedIn.id == newUser.id)
        #expect(loggedIn.role == .technician)
        #expect(loggedIn.failedLoginCount == 0)
    }

    @Test("Wrong password increments failed count")
    func wrongPasswordIncrementsCount() async throws {
        let (authService, dbPool) = try makeServices()
        let admin = try await seedAdmin(authService, dbPool: dbPool)
        _ = try await authService.createUser(actorId: admin.id, username: "testuser", password: "TestPassword1", role: .technician)

        do {
            _ = try await authService.login(username: "testuser", password: "WrongPassword1")
            Issue.record("Should have thrown")
        } catch {
            // expected
        }

        let user = try await dbPool.read { db in
            try User.filter(User.Columns.username == "testuser").fetchOne(db)
        }
        #expect(user?.failedLoginCount == 1)
    }

    @Test("5 failed logins locks account for 15 minutes")
    func lockoutAfterFiveFailures() async throws {
        let (authService, dbPool) = try makeServices()
        let admin = try await seedAdmin(authService, dbPool: dbPool)
        _ = try await authService.createUser(actorId: admin.id, username: "locktest", password: "TestPassword1", role: .technician)

        for _ in 0..<5 {
            do {
                _ = try await authService.login(username: "locktest", password: "Wrong12345")
            } catch {}
        }

        let user = try await dbPool.read { db in
            try User.filter(User.Columns.username == "locktest").fetchOne(db)
        }
        #expect(user?.status == .locked)
        #expect(user?.lockedUntil != nil)
        #expect(user?.failedLoginCount == 5)
    }

    @Test("Login during lockout does not increment count")
    func lockoutDoesNotIncrementCount() async throws {
        let (authService, dbPool) = try makeServices()
        let admin = try await seedAdmin(authService, dbPool: dbPool)
        _ = try await authService.createUser(actorId: admin.id, username: "locktest2", password: "TestPassword1", role: .technician)

        // Lock the account
        for _ in 0..<5 {
            do { _ = try await authService.login(username: "locktest2", password: "Wrong12345") } catch {}
        }

        // Try login during lockout
        do {
            _ = try await authService.login(username: "locktest2", password: "TestPassword1")
            Issue.record("Should have thrown accountLocked")
        } catch let error as AuthError {
            if case .accountLocked = error { /* expected */ }
            else { Issue.record("Expected accountLocked, got \(error)") }
        }

        let user = try await dbPool.read { db in
            try User.filter(User.Columns.username == "locktest2").fetchOne(db)
        }
        // Count should still be 5, not 6
        #expect(user?.failedLoginCount == 5)
    }

    @Test("Successful login resets failed count")
    func successResetsCount() async throws {
        let (authService, dbPool) = try makeServices()
        let admin = try await seedAdmin(authService, dbPool: dbPool)
        _ = try await authService.createUser(actorId: admin.id, username: "resettest", password: "TestPassword1", role: .technician)

        // Fail a few times
        for _ in 0..<3 {
            do { _ = try await authService.login(username: "resettest", password: "Wrong12345") } catch {}
        }

        // Succeed
        let user = try await authService.login(username: "resettest", password: "TestPassword1")
        #expect(user.failedLoginCount == 0)
        #expect(user.status == .active)
    }

    @Test("Deactivated user cannot login")
    func deactivatedUserRejected() async throws {
        let (authService, dbPool) = try makeServices()
        let admin = try await seedAdmin(authService, dbPool: dbPool)
        let newUser = try await authService.createUser(actorId: admin.id, username: "deactest", password: "TestPassword1", role: .technician)

        _ = try await authService.updateUserStatus(actorId: admin.id, userId: newUser.id, status: .deactivated)

        do {
            _ = try await authService.login(username: "deactest", password: "TestPassword1")
            Issue.record("Should have thrown accountDeactivated")
        } catch let error as AuthError {
            if case .accountDeactivated = error { /* expected */ }
            else { Issue.record("Expected accountDeactivated, got \(error)") }
        }
    }

    @Test("Audit entries recorded for login")
    func auditEntriesRecorded() async throws {
        let (authService, dbPool) = try makeServices()
        let admin = try await seedAdmin(authService, dbPool: dbPool)
        let newUser = try await authService.createUser(actorId: admin.id, username: "audituser", password: "TestPassword1", role: .technician)

        _ = try await authService.login(username: "audituser", password: "TestPassword1")

        let entries = try await dbPool.read { db in
            try AuditEntry
                .filter(AuditEntry.Columns.entityId == newUser.id)
                .order(AuditEntry.Columns.timestamp)
                .fetchAll(db)
        }

        let actions = entries.map { $0.action }
        #expect(actions.contains("USER_CREATED"))
        #expect(actions.contains("LOGIN_SUCCESS"))
    }
}
