import Foundation
import GRDB

final class UserRepository: Sendable {
    private let dbPool: DatabasePool

    init(dbPool: DatabasePool) {
        self.dbPool = dbPool
    }

    // MARK: - Reads

    func findById(_ id: UUID) async throws -> User? {
        try await dbPool.read { db in
            try User.fetchOne(db, key: id)
        }
    }

    func findByUsername(_ username: String) async throws -> User? {
        try await dbPool.read { db in
            try User.filter(User.Columns.username == username).fetchOne(db)
        }
    }

    func fetchAll() async throws -> [User] {
        try await dbPool.read { db in
            try User.order(User.Columns.username).fetchAll(db)
        }
    }

    // MARK: - Writes (async, with optimistic locking)

    func insert(_ user: User) async throws {
        try await dbPool.write { db in
            try user.insert(db)
        }
    }

    func update(_ user: User) async throws -> User {
        var mutableUser = user
        try await dbPool.write { db in
            try self.updateWithLocking(db: db, user: &mutableUser)
        }
        return mutableUser
    }

    // MARK: - Transactional variants (for use inside dbPool.write blocks)

    func insertInTransaction(db: Database, _ user: User) throws {
        try user.insert(db)
    }

    /// Updates the user with optimistic locking. Mutates user.version and user.updatedAt.
    func updateWithLocking(db: Database, user: inout User) throws {
        let current = try User.fetchOne(db, key: user.id)
        guard current?.version == user.version else {
            throw StaleRecordError(entityType: "User", entityId: user.id)
        }

        user.version += 1
        user.updatedAt = Date()
        try user.update(db)
    }

    func findByIdInTransaction(db: Database, _ id: UUID) throws -> User? {
        try User.fetchOne(db, key: id)
    }

    func findByUsernameInTransaction(db: Database, _ username: String) throws -> User? {
        try User.filter(User.Columns.username == username).fetchOne(db)
    }

    func deleteInTransaction(db: Database, userId: UUID) throws {
        try db.execute(sql: "DELETE FROM users WHERE id = ?", arguments: [userId])
    }
}
