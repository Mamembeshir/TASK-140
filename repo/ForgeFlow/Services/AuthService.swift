import Foundation
import GRDB
import os.log

final class AuthService: Sendable {
    private let dbPool: DatabasePool
    private let userRepository: UserRepository
    private let auditService: AuditService

    init(dbPool: DatabasePool, userRepository: UserRepository, auditService: AuditService) {
        self.dbPool = dbPool
        self.userRepository = userRepository
        self.auditService = auditService
    }

    // MARK: - Validation

    static func validateUsername(_ username: String) throws {
        guard username.count >= 3 else { throw AuthError.usernameInvalid }
        guard username.count <= 100 else { throw AuthError.usernameInvalid }
        let pattern = "^[a-zA-Z0-9._-]+$"
        guard username.range(of: pattern, options: .regularExpression) != nil else {
            throw AuthError.usernameInvalid
        }
    }

    static func validatePassword(_ password: String) throws {
        guard password.count >= 10 else { throw AuthError.passwordTooShort }
        guard password.count <= 128 else { throw AuthError.passwordTooShort }
        guard password.range(of: "[0-9]", options: .regularExpression) != nil else {
            throw AuthError.passwordMissingNumber
        }
    }

    // MARK: - Login

    func login(username: String, password: String) async throws -> User {
        // Use Result to separate DB commit from error throwing.
        // The write transaction must commit even on failed login (to persist failedLoginCount).
        let result: Result<User, Error> = try await dbPool.write { [self] db in
            guard var user = try userRepository.findByUsernameInTransaction(db: db, username) else {
                return .failure(AuthError.invalidCredentials)
            }

            if user.status == .deactivated {
                return .failure(AuthError.accountDeactivated)
            }

            // Check lockout
            if let lockedUntil = user.lockedUntil {
                if lockedUntil > Date() {
                    // Still locked — do NOT increment count (AUTH-02)
                    return .failure(AuthError.accountLocked(until: lockedUntil))
                } else {
                    // Lock expired — clear it
                    user.lockedUntil = nil
                    user.status = .active
                    user.failedLoginCount = 0
                }
            }

            // Verify password (supports PBKDF2 and legacy SHA-256)
            let storedHash = loadPasswordHash(userId: user.id)

            guard let stored = storedHash, verifyPassword(password, storedHash: stored) else {
                // Failed login — update and commit, then return failure
                user.failedLoginCount += 1

                if user.failedLoginCount >= 5 {
                    user.lockedUntil = Date().addingTimeInterval(15 * 60)
                    user.status = .locked
                    try userRepository.updateWithLocking(db: db, user: &user)

                    ForgeLogger.auth.error("Account locked after \(user.failedLoginCount, privacy: .public) failed attempts for user \(user.id, privacy: .public)")

                    try auditService.record(
                        db: db,
                        actorId: user.id,
                        action: "ACCOUNT_LOCKED",
                        entityType: "User",
                        entityId: user.id,
                        afterData: "{\"reason\":\"5 failed login attempts\"}"
                    )
                    return .failure(AuthError.accountLocked(until: user.lockedUntil!))
                } else {
                    try userRepository.updateWithLocking(db: db, user: &user)

                    ForgeLogger.auth.warning("Login failed for user \(user.id, privacy: .public), failedCount=\(user.failedLoginCount, privacy: .public)")

                    try auditService.record(
                        db: db,
                        actorId: user.id,
                        action: "LOGIN_FAILED",
                        entityType: "User",
                        entityId: user.id,
                        afterData: "{\"failedCount\":\(user.failedLoginCount)}"
                    )
                    return .failure(AuthError.invalidCredentials)
                }
            }

            // Successful login — reset lockout state (AUTH-03)
            user.failedLoginCount = 0
            user.lockedUntil = nil
            if user.status == .locked {
                user.status = .active
            }
            try userRepository.updateWithLocking(db: db, user: &user)

            try auditService.record(
                db: db,
                actorId: user.id,
                action: "LOGIN_SUCCESS",
                entityType: "User",
                entityId: user.id
            )

            ForgeLogger.auth.info("Login succeeded for user \(user.id, privacy: .public) role=\(user.role.rawValue, privacy: .public)")
            return .success(user)
        }

        return try result.get()
    }

    // MARK: - Biometric Unlock

    func biometricUnlock(userId: UUID) async throws -> User {
        try await BiometricHelper.authenticate(reason: "Unlock ForgeFlow")

        guard let user = try await userRepository.findById(userId) else {
            throw AuthError.invalidCredentials
        }

        try await auditService.record(
            actorId: userId,
            action: "BIOMETRIC_UNLOCK",
            entityType: "User",
            entityId: userId
        )

        return user
    }

    // MARK: - Password Unlock (for lock screen)

    func passwordUnlock(userId: UUID, password: String) async throws -> User {
        guard let user = try await userRepository.findById(userId) else {
            throw AuthError.invalidCredentials
        }

        let storedHash = loadPasswordHash(userId: userId)

        guard let stored = storedHash, verifyPassword(password, storedHash: stored) else {
            throw AuthError.invalidCredentials
        }

        try await auditService.record(
            actorId: userId,
            action: "PASSWORD_UNLOCK",
            entityType: "User",
            entityId: userId
        )

        return user
    }

    // MARK: - Authorization

    /// Verifies the actor has the required role. Throws AuthError.notAuthorized if not.
    func requireRole(actorId: UUID, allowedRoles: Set<Role>) async throws {
        guard let actor = try await userRepository.findById(actorId) else {
            ForgeLogger.auth.warning("Authorization denied: actor \(actorId, privacy: .public) not found")
            throw AuthError.invalidCredentials
        }
        guard allowedRoles.contains(actor.role) else {
            ForgeLogger.auth.warning("Authorization denied: actor \(actorId, privacy: .public) role=\(actor.role.rawValue, privacy: .public) not in allowed=\(allowedRoles.map(\.rawValue).sorted().joined(separator: ","), privacy: .public)")
            throw AuthError.notAuthorized
        }
    }

    /// Verifies the actor is an admin.
    func requireAdmin(actorId: UUID) async throws {
        try await requireRole(actorId: actorId, allowedRoles: [.admin])
    }

    /// Verifies the actor is an admin or coordinator.
    func requireAdminOrCoordinator(actorId: UUID) async throws {
        try await requireRole(actorId: actorId, allowedRoles: [.admin, .coordinator])
    }

    /// Verifies the actor is either the target user themselves or an admin.
    func requireSelfOrAdmin(actorId: UUID, userId: UUID) async throws {
        if actorId == userId { return }
        try await requireAdmin(actorId: actorId)
    }

    // MARK: - User Management (Admin only)

    func createUser(actorId: UUID, username: String, password: String, role: Role) async throws -> User {
        ForgeLogger.auth.info("createUser requested by actor \(actorId, privacy: .public) for role=\(role.rawValue, privacy: .public)")
        try await requireAdmin(actorId: actorId)
        try Self.validateUsername(username)
        try Self.validatePassword(password)

        let user = try await dbPool.write { [self] db in
            // Check uniqueness
            if try userRepository.findByUsernameInTransaction(db: db, username) != nil {
                throw AuthError.usernameTaken
            }

            let now = Date()
            let newUser = User(
                id: UUID(),
                username: username,
                role: role,
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

            try userRepository.insertInTransaction(db: db, newUser)

            try auditService.record(
                db: db,
                actorId: actorId,
                action: "USER_CREATED",
                entityType: "User",
                entityId: newUser.id,
                afterData: "{\"username\":\"\(username)\",\"role\":\"\(role.rawValue)\"}"
            )

            return newUser
        }

        // Store password hash in Keychain (outside transaction — Keychain is not DB).
        // If this fails the DB row already committed, so compensate by deleting the
        // user to avoid an account with no usable password hash.
        let hash = hashPassword(password)
        do {
            try storePasswordHash(hash, userId: user.id)
        } catch {
            try? await dbPool.write { [self] db in
                try userRepository.deleteInTransaction(db: db, userId: user.id)
            }
            throw AuthError.keychainStoreFailed
        }

        return user
    }

    func updateUserStatus(actorId: UUID, userId: UUID, status: UserStatus) async throws -> User {
        try await requireAdmin(actorId: actorId)
        return try await dbPool.write { [self] db in
            guard var user = try userRepository.findByIdInTransaction(db: db, userId) else {
                throw AuthError.invalidCredentials
            }

            let beforeStatus = user.status.rawValue
            user.status = status

            if status == .active {
                user.failedLoginCount = 0
                user.lockedUntil = nil
            }

            try userRepository.updateWithLocking(db: db, user: &user)

            try auditService.record(
                db: db,
                actorId: actorId,
                action: "USER_STATUS_CHANGED",
                entityType: "User",
                entityId: userId,
                beforeData: "{\"status\":\"\(beforeStatus)\"}",
                afterData: "{\"status\":\"\(status.rawValue)\"}"
            )

            return user
        }
    }

    func toggleBiometric(actorId: UUID, userId: UUID, enabled: Bool) async throws -> User {
        try await requireSelfOrAdmin(actorId: actorId, userId: userId)
        return try await dbPool.write { [self] db in
            guard var user = try userRepository.findByIdInTransaction(db: db, userId) else {
                throw AuthError.invalidCredentials
            }
            user.biometricEnabled = enabled
            try userRepository.updateWithLocking(db: db, user: &user)

            return user
        }
    }

    func listUsers(actorId: UUID) async throws -> [User] {
        try await requireAdmin(actorId: actorId)
        return try await userRepository.fetchAll()
    }

    /// Coordinator-safe: returns active technicians only. Requires admin or coordinator role.
    func listActiveTechnicians(actorId: UUID) async throws -> [User] {
        try await requireAdminOrCoordinator(actorId: actorId)
        let all = try await userRepository.fetchAll()
        return all.filter { $0.role == .technician && $0.status == .active }
    }

    // MARK: - User reads

    func getUser(actorId: UUID, id: UUID) async throws -> User? {
        try await requireSelfOrAdmin(actorId: actorId, userId: id)
        return try await userRepository.findById(id)
    }

    // MARK: - DND Settings

    func updateDNDSettings(actorId: UUID, userId: UUID, startTime: String?, endTime: String?) async throws {
        try await requireSelfOrAdmin(actorId: actorId, userId: userId)
        try await dbPool.write { [self] db in
            guard var user = try userRepository.findByIdInTransaction(db: db, userId) else { return }
            user.dndStartTime = startTime
            user.dndEndTime = endTime
            try userRepository.updateWithLocking(db: db, user: &user)

            try auditService.record(
                db: db, actorId: userId, action: "DND_SETTINGS_UPDATED",
                entityType: "User", entityId: userId,
                afterData: "{\"startTime\":\"\(startTime ?? "nil")\",\"endTime\":\"\(endTime ?? "nil")\"}"
            )
        }
    }

    // MARK: - Storage Policy (Admin only)

    /// Admin updates a user's storage quota. Audited.
    func updateStorageQuota(actorId: UUID, userId: UUID, quotaBytes: Int) async throws -> User {
        try await requireAdmin(actorId: actorId)
        return try await dbPool.write { [self] db in
            guard var user = try userRepository.findByIdInTransaction(db: db, userId) else {
                throw AuthError.invalidCredentials
            }
            let before = user.storageQuotaBytes
            user.storageQuotaBytes = quotaBytes
            try userRepository.updateWithLocking(db: db, user: &user)

            try auditService.record(
                db: db, actorId: actorId, action: "STORAGE_QUOTA_UPDATED",
                entityType: "User", entityId: userId,
                beforeData: "{\"storageQuotaBytes\":\(before)}",
                afterData: "{\"storageQuotaBytes\":\(quotaBytes)}"
            )
            return user
        }
    }

    // MARK: - Password Hashing (private)

    /// Hashes a new password using salted PBKDF2-SHA256.
    private func hashPassword(_ password: String) -> String {
        PasswordHasher.hash(password)
    }

    /// Verifies a password against the stored hash.
    /// Supports both new PBKDF2 format and legacy plain SHA-256.
    private func verifyPassword(_ password: String, storedHash: String) -> Bool {
        PasswordHasher.verify(password, against: storedHash)
    }

    private func loadPasswordHash(userId: UUID) -> String? {
        guard let data = KeychainHelper.load(forKey: "forgeflow.password.\(userId.uuidString)") else {
            return nil
        }
        return String(data: data, encoding: .utf8)
    }

    private func storePasswordHash(_ hash: String, userId: UUID) throws {
        try KeychainHelper.save(
            data: hash.data(using: .utf8)!,
            forKey: "forgeflow.password.\(userId.uuidString)"
        )
    }
}
