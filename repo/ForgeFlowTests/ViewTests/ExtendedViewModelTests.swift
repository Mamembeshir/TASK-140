import Foundation
import Testing
import GRDB
@testable import ForgeFlow

// MARK: - Helpers

private func makeDB() throws -> DatabaseManager {
    try DatabaseManager(inMemory: true)
}

private func makeAdmin(pool: DatabasePool, suffix: String) async throws -> User {
    let now = Date()
    let admin = User(
        id: UUID(),
        username: "admin_\(suffix)",
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
    try await pool.write { db in try admin.insert(db) }
    let hash = PasswordHasher.hash("AdminPass1")
    try KeychainHelper.save(data: hash.data(using: .utf8)!, forKey: "forgeflow.password.\(admin.id.uuidString)")
    return admin
}

private func makeCoordinator(pool: DatabasePool, suffix: String) async throws -> User {
    let now = Date()
    let coord = User(
        id: UUID(),
        username: "coord_\(suffix)",
        role: .coordinator,
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
    try await pool.write { db in try coord.insert(db) }
    return coord
}

private func makePluginService(pool: DatabasePool) -> PluginService {
    PluginService(
        dbPool: pool,
        pluginRepository: PluginRepository(dbPool: pool),
        postingRepository: PostingRepository(dbPool: pool),
        auditService: AuditService(dbPool: pool),
        userRepository: UserRepository(dbPool: pool)
    )
}

private func makePostingService(pool: DatabasePool) -> PostingService {
    PostingService(
        dbPool: pool,
        postingRepository: PostingRepository(dbPool: pool),
        taskRepository: TaskRepository(dbPool: pool),
        userRepository: UserRepository(dbPool: pool),
        auditService: AuditService(dbPool: pool)
    )
}

private func makeAuthService(pool: DatabasePool) -> AuthService {
    AuthService(
        dbPool: pool,
        userRepository: UserRepository(dbPool: pool),
        auditService: AuditService(dbPool: pool)
    )
}

// MARK: - PostingListViewModel Tests

@Suite("PostingListViewModel Tests", .serialized)
struct PostingListViewModelTests {

    @Test("loadPostings populates postings for admin")
    func loadPopulatesPostings() async throws {
        let db = try makeDB()
        let pool = db.dbPool
        let suffix = String(UUID().uuidString.prefix(8))
        let admin = try await makeAdmin(pool: pool, suffix: suffix)
        let postingSvc = makePostingService(pool: pool)

        _ = try await postingSvc.create(
            actorId: admin.id,
            title: "Test Posting \(suffix)",
            siteAddress: "100 Main St",
            dueDate: Date().addingTimeInterval(86400),
            budgetCents: 50000,
            acceptanceMode: .open,
            watermarkEnabled: false
        )

        let appState = AppState()
        appState.login(userId: admin.id, role: .admin)
        let vm = await MainActor.run { PostingListViewModel(postingService: postingSvc, appState: appState) }
        await vm.loadPostings()

        await MainActor.run {
            #expect(vm.postings.count >= 1)
            #expect(vm.isLoading == false)
            #expect(vm.errorMessage == nil)
        }
    }

    @Test("loadPostings does nothing when not authenticated")
    func loadNoopWhenUnauthenticated() async throws {
        let db = try makeDB()
        let pool = db.dbPool
        let postingSvc = makePostingService(pool: pool)
        let appState = AppState() // no login
        let vm = await MainActor.run { PostingListViewModel(postingService: postingSvc, appState: appState) }
        await vm.loadPostings()

        await MainActor.run {
            #expect(vm.postings.isEmpty)
        }
    }

    @Test("filteredPostings returns all when no filter set")
    func filteredPostingsNoFilter() async throws {
        let db = try makeDB()
        let pool = db.dbPool
        let suffix = String(UUID().uuidString.prefix(8))
        let admin = try await makeAdmin(pool: pool, suffix: suffix)
        let postingSvc = makePostingService(pool: pool)

        _ = try await postingSvc.create(
            actorId: admin.id, title: "P1 \(suffix)", siteAddress: "Addr",
            dueDate: Date().addingTimeInterval(86400), budgetCents: 100,
            acceptanceMode: .open, watermarkEnabled: false
        )

        let appState = AppState()
        appState.login(userId: admin.id, role: .admin)
        let vm = await MainActor.run { PostingListViewModel(postingService: postingSvc, appState: appState) }
        await vm.loadPostings()

        await MainActor.run {
            #expect(vm.filteredPostings.count == vm.postings.count)
        }
    }

    @Test("filteredPostings filters by statusFilter")
    func filteredPostingsByStatus() async throws {
        let db = try makeDB()
        let pool = db.dbPool
        let suffix = String(UUID().uuidString.prefix(8))
        let admin = try await makeAdmin(pool: pool, suffix: suffix)
        let postingSvc = makePostingService(pool: pool)

        _ = try await postingSvc.create(
            actorId: admin.id, title: "Draft \(suffix)", siteAddress: "Addr",
            dueDate: Date().addingTimeInterval(86400), budgetCents: 100,
            acceptanceMode: .open, watermarkEnabled: false
        )

        let appState = AppState()
        appState.login(userId: admin.id, role: .admin)
        let vm = await MainActor.run { PostingListViewModel(postingService: postingSvc, appState: appState) }
        await vm.loadPostings()

        await MainActor.run {
            vm.statusFilter = .open
            #expect(vm.filteredPostings.allSatisfy { $0.status == .open })

            vm.statusFilter = .draft
            #expect(vm.filteredPostings.allSatisfy { $0.status == .draft })

            vm.statusFilter = nil
            #expect(vm.filteredPostings.count == vm.postings.count)
        }
    }

    @Test("cancelPosting cancels and reloads")
    func cancelPostingUpdatesState() async throws {
        let db = try makeDB()
        let pool = db.dbPool
        let suffix = String(UUID().uuidString.prefix(8))
        let admin = try await makeAdmin(pool: pool, suffix: suffix)
        let postingSvc = makePostingService(pool: pool)

        let posting = try await postingSvc.create(
            actorId: admin.id, title: "To Cancel \(suffix)", siteAddress: "Addr",
            dueDate: Date().addingTimeInterval(86400), budgetCents: 100,
            acceptanceMode: .open, watermarkEnabled: false
        )

        let appState = AppState()
        appState.login(userId: admin.id, role: .admin)
        let vm = await MainActor.run { PostingListViewModel(postingService: postingSvc, appState: appState) }
        await vm.loadPostings()

        let beforeCount = await MainActor.run { vm.postings.count }
        await vm.cancelPosting(posting.id)

        await MainActor.run {
            #expect(vm.errorMessage == nil)
            let cancelled = vm.postings.first(where: { $0.id == posting.id })
            #expect(cancelled?.status == .cancelled)
            #expect(vm.postings.count == beforeCount)
        }
    }
}

// MARK: - AdminViewModel Tests

@Suite("AdminViewModel Tests", .serialized)
struct AdminViewModelTests {

    @Test("loadUsers populates users list for admin")
    func loadUsersPopulates() async throws {
        let db = try makeDB()
        let pool = db.dbPool
        let suffix = String(UUID().uuidString.prefix(8))
        let admin = try await makeAdmin(pool: pool, suffix: suffix)
        let authSvc = makeAuthService(pool: pool)
        let appState = AppState()
        appState.login(userId: admin.id, role: .admin)

        let vm = await MainActor.run { AdminViewModel(authService: authSvc, appState: appState) }
        await vm.loadUsers()

        await MainActor.run {
            #expect(vm.users.count >= 1)
            #expect(vm.isLoading == false)
            #expect(vm.errorMessage == nil)
        }
    }

    @Test("loadUsers does nothing when unauthenticated")
    func loadUsersNoopWhenUnauthenticated() async throws {
        let db = try makeDB()
        let pool = db.dbPool
        let authSvc = makeAuthService(pool: pool)
        let appState = AppState()
        let vm = await MainActor.run { AdminViewModel(authService: authSvc, appState: appState) }
        await vm.loadUsers()

        await MainActor.run {
            #expect(vm.users.isEmpty)
        }
    }

    @Test("createUser creates and reloads users")
    func createUserCreatesAndReloads() async throws {
        let db = try makeDB()
        let pool = db.dbPool
        let suffix = String(UUID().uuidString.prefix(8))
        let admin = try await makeAdmin(pool: pool, suffix: suffix)
        let authSvc = makeAuthService(pool: pool)
        let appState = AppState()
        appState.login(userId: admin.id, role: .admin)

        let vm = await MainActor.run { AdminViewModel(authService: authSvc, appState: appState) }

        await MainActor.run {
            vm.newUsername = "newtech_\(suffix)"
            vm.newPassword = "SecurePass1"
            vm.newRole = .technician
        }

        await vm.createUser()

        await MainActor.run {
            #expect(vm.errorMessage == nil)
            #expect(vm.newUsername == "")
            #expect(vm.newPassword == "")
            #expect(vm.newRole == .technician)
            #expect(vm.showCreateSheet == false)
            #expect(vm.users.contains(where: { $0.username == "newtech_\(suffix)" }))
        }
    }

    @Test("createUser sets errorMessage on invalid password")
    func createUserSetsErrorOnInvalidPassword() async throws {
        let db = try makeDB()
        let pool = db.dbPool
        let suffix = String(UUID().uuidString.prefix(8))
        let admin = try await makeAdmin(pool: pool, suffix: suffix)
        let authSvc = makeAuthService(pool: pool)
        let appState = AppState()
        appState.login(userId: admin.id, role: .admin)

        let vm = await MainActor.run { AdminViewModel(authService: authSvc, appState: appState) }

        await MainActor.run {
            vm.newUsername = "newtech_\(suffix)"
            vm.newPassword = "short" // too short
            vm.newRole = .technician
        }

        await vm.createUser()

        await MainActor.run {
            #expect(vm.errorMessage != nil)
            #expect(vm.isLoading == false)
        }
    }

    @Test("deactivateUser deactivates and reactivateUser reactivates")
    func deactivateAndReactivate() async throws {
        let db = try makeDB()
        let pool = db.dbPool
        let suffix = String(UUID().uuidString.prefix(8))
        let admin = try await makeAdmin(pool: pool, suffix: suffix)
        let authSvc = makeAuthService(pool: pool)
        let appState = AppState()
        appState.login(userId: admin.id, role: .admin)

        // Create a target user to deactivate
        let targetSuffix = String(UUID().uuidString.prefix(8))
        let target = try await authSvc.createUser(
            actorId: admin.id,
            username: "target_\(targetSuffix)",
            password: "SecurePass1",
            role: .technician
        )

        let vm = await MainActor.run { AdminViewModel(authService: authSvc, appState: appState) }
        await vm.deactivateUser(userId: target.id)
        await vm.loadUsers()

        await MainActor.run {
            let deactivated = vm.users.first(where: { $0.id == target.id })
            #expect(deactivated?.status == .deactivated)
        }

        await vm.reactivateUser(userId: target.id)
        await vm.loadUsers()

        await MainActor.run {
            let reactivated = vm.users.first(where: { $0.id == target.id })
            #expect(reactivated?.status == .active)
            #expect(vm.errorMessage == nil)
        }
    }
}

// MARK: - PluginListViewModel Tests

@Suite("PluginListViewModel Tests", .serialized)
struct PluginListViewModelTests {

    @Test("load populates plugins list")
    func loadPopulatesPlugins() async throws {
        let db = try makeDB()
        let pool = db.dbPool
        let suffix = String(UUID().uuidString.prefix(8))
        let admin = try await makeAdmin(pool: pool, suffix: suffix)
        let pluginSvc = makePluginService(pool: pool)

        _ = try await pluginSvc.create(
            name: "Plugin \(suffix)", description: "Desc", category: "Cat", createdBy: admin.id
        )

        let appState = AppState()
        appState.login(userId: admin.id, role: .admin)
        let vm = await MainActor.run { PluginListViewModel(pluginService: pluginSvc, appState: appState) }
        await vm.load()

        await MainActor.run {
            #expect(vm.plugins.count >= 1)
            #expect(vm.isLoading == false)
            #expect(vm.errorMessage == nil)
        }
    }

    @Test("createPlugin creates plugin and reloads")
    func createPluginAndReload() async throws {
        let db = try makeDB()
        let pool = db.dbPool
        let suffix = String(UUID().uuidString.prefix(8))
        let admin = try await makeAdmin(pool: pool, suffix: suffix)
        let pluginSvc = makePluginService(pool: pool)
        let appState = AppState()
        appState.login(userId: admin.id, role: .admin)

        let vm = await MainActor.run { PluginListViewModel(pluginService: pluginSvc, appState: appState) }
        await vm.createPlugin(name: "NewPlugin \(suffix)", description: "Desc", category: "General")

        await MainActor.run {
            #expect(vm.errorMessage == nil)
            #expect(vm.plugins.contains(where: { $0.name == "NewPlugin \(suffix)" }))
        }
    }

    @Test("createPlugin sets errorMessage when non-admin tries to create")
    func createPluginFailsForNonAdmin() async throws {
        let db = try makeDB()
        let pool = db.dbPool
        let suffix = String(UUID().uuidString.prefix(8))
        let coord = try await makeCoordinator(pool: pool, suffix: suffix)
        let pluginSvc = makePluginService(pool: pool)
        let appState = AppState()
        appState.login(userId: coord.id, role: .coordinator)

        let vm = await MainActor.run { PluginListViewModel(pluginService: pluginSvc, appState: appState) }
        await vm.createPlugin(name: "ShouldFail \(suffix)", description: "Desc", category: "General")

        await MainActor.run {
            #expect(vm.errorMessage != nil)
        }
    }

    @Test("createPlugin does nothing when unauthenticated")
    func createPluginNoopWhenUnauthenticated() async throws {
        let db = try makeDB()
        let pool = db.dbPool
        let pluginSvc = makePluginService(pool: pool)
        let appState = AppState()
        let vm = await MainActor.run { PluginListViewModel(pluginService: pluginSvc, appState: appState) }
        await vm.createPlugin(name: "Test", description: "Desc", category: "Cat")

        await MainActor.run {
            #expect(vm.plugins.isEmpty)
        }
    }
}

// MARK: - PluginEditorViewModel Tests

@Suite("PluginEditorViewModel Tests", .serialized)
struct PluginEditorViewModelTests {

    @Test("load populates plugin and fields")
    func loadPopulatesPlugin() async throws {
        let db = try makeDB()
        let pool = db.dbPool
        let suffix = String(UUID().uuidString.prefix(8))
        let admin = try await makeAdmin(pool: pool, suffix: suffix)
        let pluginSvc = makePluginService(pool: pool)

        let plugin = try await pluginSvc.create(
            name: "EditorPlugin \(suffix)", description: "Desc", category: "Cat", createdBy: admin.id
        )

        let appState = AppState()
        appState.login(userId: admin.id, role: .admin)
        let vm = await MainActor.run { PluginEditorViewModel(pluginService: pluginSvc, appState: appState) }
        await vm.load(pluginId: plugin.id)

        await MainActor.run {
            #expect(vm.plugin?.id == plugin.id)
            #expect(vm.isLoading == false)
            #expect(vm.errorMessage == nil)
        }
    }

    @Test("addField adds a field and reloads")
    func addFieldAddsAndReloads() async throws {
        let db = try makeDB()
        let pool = db.dbPool
        let suffix = String(UUID().uuidString.prefix(8))
        let admin = try await makeAdmin(pool: pool, suffix: suffix)
        let pluginSvc = makePluginService(pool: pool)

        let plugin = try await pluginSvc.create(
            name: "FieldPlugin \(suffix)", description: "Desc", category: "Cat", createdBy: admin.id
        )

        let appState = AppState()
        appState.login(userId: admin.id, role: .admin)
        let vm = await MainActor.run { PluginEditorViewModel(pluginService: pluginSvc, appState: appState) }
        await vm.load(pluginId: plugin.id)

        await MainActor.run {
            vm.newFieldName = "Voltage"
            vm.newFieldType = .number
            vm.newFieldUnit = "V"
        }

        await vm.addField()

        await MainActor.run {
            #expect(vm.errorMessage == nil)
            #expect(vm.fields.contains(where: { $0.fieldName == "Voltage" }))
            #expect(vm.newFieldName == "")
            #expect(vm.newFieldUnit == "")
        }
    }

    @Test("addField does nothing when fieldName is empty")
    func addFieldNoopWhenNameEmpty() async throws {
        let db = try makeDB()
        let pool = db.dbPool
        let suffix = String(UUID().uuidString.prefix(8))
        let admin = try await makeAdmin(pool: pool, suffix: suffix)
        let pluginSvc = makePluginService(pool: pool)

        let plugin = try await pluginSvc.create(
            name: "EmptyFieldPlugin \(suffix)", description: "Desc", category: "Cat", createdBy: admin.id
        )

        let appState = AppState()
        appState.login(userId: admin.id, role: .admin)
        let vm = await MainActor.run { PluginEditorViewModel(pluginService: pluginSvc, appState: appState) }
        await vm.load(pluginId: plugin.id)

        await MainActor.run {
            vm.newFieldName = "" // empty
        }
        await vm.addField()

        await MainActor.run {
            #expect(vm.fields.isEmpty)
        }
    }

    @Test("submitForApproval sets errorMessage when plugin not in testing state")
    func submitForApprovalFailsFromDraft() async throws {
        let db = try makeDB()
        let pool = db.dbPool
        let suffix = String(UUID().uuidString.prefix(8))
        let admin = try await makeAdmin(pool: pool, suffix: suffix)
        let pluginSvc = makePluginService(pool: pool)

        let plugin = try await pluginSvc.create(
            name: "SubPlugin \(suffix)", description: "Desc", category: "Cat", createdBy: admin.id
        )

        let appState = AppState()
        appState.login(userId: admin.id, role: .admin)
        let vm = await MainActor.run { PluginEditorViewModel(pluginService: pluginSvc, appState: appState) }
        await vm.load(pluginId: plugin.id)
        await vm.submitForApproval() // Should fail — still in draft

        await MainActor.run {
            #expect(vm.errorMessage != nil)
        }
    }
}

// MARK: - PluginApprovalViewModel Tests

@Suite("PluginApprovalViewModel Tests", .serialized)
struct PluginApprovalViewModelTests {

    @Test("load populates plugin and approvals")
    func loadPopulatesData() async throws {
        let db = try makeDB()
        let pool = db.dbPool
        let suffix = String(UUID().uuidString.prefix(8))
        let admin = try await makeAdmin(pool: pool, suffix: suffix)
        let pluginSvc = makePluginService(pool: pool)

        let plugin = try await pluginSvc.create(
            name: "ApprovalPlugin \(suffix)", description: "Desc", category: "Cat", createdBy: admin.id
        )

        let appState = AppState()
        appState.login(userId: admin.id, role: .admin)
        let vm = await MainActor.run { PluginApprovalViewModel(pluginService: pluginSvc, appState: appState) }
        await vm.load(pluginId: plugin.id)

        await MainActor.run {
            #expect(vm.plugin?.id == plugin.id)
            #expect(vm.approvals.isEmpty)
            #expect(vm.isLoading == false)
        }
    }

    @Test("currentStep returns 1 when no approvals exist")
    func currentStepIsOneWithNoApprovals() async throws {
        let db = try makeDB()
        let pool = db.dbPool
        let suffix = String(UUID().uuidString.prefix(8))
        let admin = try await makeAdmin(pool: pool, suffix: suffix)
        let pluginSvc = makePluginService(pool: pool)

        let plugin = try await pluginSvc.create(
            name: "StepPlugin \(suffix)", description: "Desc", category: "Cat", createdBy: admin.id
        )

        let appState = AppState()
        appState.login(userId: admin.id, role: .admin)
        let vm = await MainActor.run { PluginApprovalViewModel(pluginService: pluginSvc, appState: appState) }
        await vm.load(pluginId: plugin.id)

        await MainActor.run {
            #expect(vm.currentStep == 1)
        }
    }

    @Test("canApprove is false when plugin is not pendingApproval")
    func canApproveIsFalseWhenNotPending() async throws {
        let db = try makeDB()
        let pool = db.dbPool
        let suffix = String(UUID().uuidString.prefix(8))
        let admin = try await makeAdmin(pool: pool, suffix: suffix)
        let pluginSvc = makePluginService(pool: pool)

        let plugin = try await pluginSvc.create(
            name: "CanApprovePlugin \(suffix)", description: "Desc", category: "Cat", createdBy: admin.id
        )

        let appState = AppState()
        appState.login(userId: admin.id, role: .admin)
        let vm = await MainActor.run { PluginApprovalViewModel(pluginService: pluginSvc, appState: appState) }
        await vm.load(pluginId: plugin.id)

        await MainActor.run {
            // Draft status — canApprove must be false
            #expect(vm.canApprove == false)
        }
    }

    @Test("approve sets errorMessage when plugin is not in pendingApproval state")
    func approveFailsFromDraft() async throws {
        let db = try makeDB()
        let pool = db.dbPool
        let suffix = String(UUID().uuidString.prefix(8))
        let admin = try await makeAdmin(pool: pool, suffix: suffix)
        let pluginSvc = makePluginService(pool: pool)

        let plugin = try await pluginSvc.create(
            name: "ApproveFail \(suffix)", description: "Desc", category: "Cat", createdBy: admin.id
        )

        let appState = AppState()
        appState.login(userId: admin.id, role: .admin)
        let vm = await MainActor.run { PluginApprovalViewModel(pluginService: pluginSvc, appState: appState) }
        await vm.load(pluginId: plugin.id)
        await vm.approve(notes: nil)

        await MainActor.run {
            #expect(vm.errorMessage != nil)
        }
    }

    @Test("reject sets errorMessage when plugin is not in pendingApproval state")
    func rejectFailsFromDraft() async throws {
        let db = try makeDB()
        let pool = db.dbPool
        let suffix = String(UUID().uuidString.prefix(8))
        let admin = try await makeAdmin(pool: pool, suffix: suffix)
        let pluginSvc = makePluginService(pool: pool)

        let plugin = try await pluginSvc.create(
            name: "RejectFail \(suffix)", description: "Desc", category: "Cat", createdBy: admin.id
        )

        let appState = AppState()
        appState.login(userId: admin.id, role: .admin)
        let vm = await MainActor.run { PluginApprovalViewModel(pluginService: pluginSvc, appState: appState) }
        await vm.load(pluginId: plugin.id)
        await vm.reject(notes: "Not ready")

        await MainActor.run {
            #expect(vm.errorMessage != nil)
        }
    }
}

// MARK: - PluginTestViewModel Tests

@Suite("PluginTestViewModel Tests", .serialized)
struct PluginTestViewModelTests {

    @Test("load populates plugin and available postings")
    func loadPopulatesData() async throws {
        let db = try makeDB()
        let pool = db.dbPool
        let suffix = String(UUID().uuidString.prefix(8))
        let admin = try await makeAdmin(pool: pool, suffix: suffix)
        let pluginSvc = makePluginService(pool: pool)
        let postingSvc = makePostingService(pool: pool)

        let plugin = try await pluginSvc.create(
            name: "TestVMPlugin \(suffix)", description: "Desc", category: "Cat", createdBy: admin.id
        )
        _ = try await postingSvc.create(
            actorId: admin.id, title: "Posting \(suffix)", siteAddress: "Addr",
            dueDate: Date().addingTimeInterval(86400), budgetCents: 100,
            acceptanceMode: .open, watermarkEnabled: false
        )

        let appState = AppState()
        appState.login(userId: admin.id, role: .admin)
        let vm = await MainActor.run { PluginTestViewModel(pluginService: pluginSvc, postingService: postingSvc, appState: appState) }
        await vm.load(pluginId: plugin.id)

        await MainActor.run {
            #expect(vm.plugin?.id == plugin.id)
            #expect(vm.availablePostings.count >= 1)
            #expect(vm.errorMessage == nil)
        }
    }

    @Test("togglePosting inserts and removes from selectedPostingIds")
    func togglePostingTogglesSelection() async throws {
        let db = try makeDB()
        let pool = db.dbPool
        let suffix = String(UUID().uuidString.prefix(8))
        let admin = try await makeAdmin(pool: pool, suffix: suffix)
        let pluginSvc = makePluginService(pool: pool)
        let postingSvc = makePostingService(pool: pool)
        let appState = AppState()
        appState.login(userId: admin.id, role: .admin)

        let vm = await MainActor.run { PluginTestViewModel(pluginService: pluginSvc, postingService: postingSvc, appState: appState) }
        let id = UUID()

        await MainActor.run {
            #expect(vm.selectedPostingIds.isEmpty)
            vm.togglePosting(id)
            #expect(vm.selectedPostingIds.contains(id))
            vm.togglePosting(id)
            #expect(!vm.selectedPostingIds.contains(id))
        }
    }

    @Test("runTests does nothing when selectedPostingIds is empty")
    func runTestsNoopWhenNoSelection() async throws {
        let db = try makeDB()
        let pool = db.dbPool
        let suffix = String(UUID().uuidString.prefix(8))
        let admin = try await makeAdmin(pool: pool, suffix: suffix)
        let pluginSvc = makePluginService(pool: pool)
        let postingSvc = makePostingService(pool: pool)

        let plugin = try await pluginSvc.create(
            name: "RunTestNoopPlugin \(suffix)", description: "Desc", category: "Cat", createdBy: admin.id
        )

        let appState = AppState()
        appState.login(userId: admin.id, role: .admin)
        let vm = await MainActor.run { PluginTestViewModel(pluginService: pluginSvc, postingService: postingSvc, appState: appState) }
        await vm.load(pluginId: plugin.id)
        // No selected postings
        await vm.runTests()

        await MainActor.run {
            #expect(vm.testResults.isEmpty)
            #expect(vm.isRunning == false)
        }
    }

    @Test("runTests sets errorMessage when plugin has no fields")
    func runTestsFailsWithNoFields() async throws {
        let db = try makeDB()
        let pool = db.dbPool
        let suffix = String(UUID().uuidString.prefix(8))
        let admin = try await makeAdmin(pool: pool, suffix: suffix)
        let pluginSvc = makePluginService(pool: pool)
        let postingSvc = makePostingService(pool: pool)

        let plugin = try await pluginSvc.create(
            name: "NoFieldsPlugin \(suffix)", description: "Desc", category: "Cat", createdBy: admin.id
        )
        let posting = try await postingSvc.create(
            actorId: admin.id, title: "Posting \(suffix)", siteAddress: "Addr",
            dueDate: Date().addingTimeInterval(86400), budgetCents: 100,
            acceptanceMode: .open, watermarkEnabled: false
        )

        let appState = AppState()
        appState.login(userId: admin.id, role: .admin)
        let vm = await MainActor.run { PluginTestViewModel(pluginService: pluginSvc, postingService: postingSvc, appState: appState) }
        await vm.load(pluginId: plugin.id)

        await MainActor.run {
            vm.selectedPostingIds.insert(posting.id)
        }
        await vm.runTests()

        await MainActor.run {
            #expect(vm.errorMessage != nil)
            #expect(vm.isRunning == false)
        }
    }
}

// MARK: - AttachmentViewModel Tests

@Suite("AttachmentViewModel Tests", .serialized)
struct AttachmentViewModelTests {

    private func makeAttachmentService(pool: DatabasePool) -> AttachmentService {
        AttachmentService(
            dbPool: pool,
            attachmentRepository: AttachmentRepository(dbPool: pool),
            auditService: AuditService(dbPool: pool),
            userRepository: UserRepository(dbPool: pool),
            postingRepository: PostingRepository(dbPool: pool)
        )
    }

    @Test("loadAttachments populates attachments and quota")
    func loadAttachmentsPopulates() async throws {
        let db = try makeDB()
        let pool = db.dbPool
        let suffix = String(UUID().uuidString.prefix(8))
        let admin = try await makeAdmin(pool: pool, suffix: suffix)
        let attachSvc = makeAttachmentService(pool: pool)
        let postingSvc = makePostingService(pool: pool)

        let posting = try await postingSvc.create(
            actorId: admin.id, title: "AttachPosting \(suffix)", siteAddress: "Addr",
            dueDate: Date().addingTimeInterval(86400), budgetCents: 100,
            acceptanceMode: .open, watermarkEnabled: false
        )

        let appState = AppState()
        appState.login(userId: admin.id, role: .admin)
        let vm = await MainActor.run {
            AttachmentViewModel(postingId: posting.id, attachmentService: attachSvc, appState: appState)
        }
        await vm.loadAttachments()

        await MainActor.run {
            #expect(vm.attachments.isEmpty)
            #expect(vm.isLoading == false)
            #expect(vm.errorMessage == nil)
            #expect(vm.quotaTotal > 0)
        }
    }

    @Test("loadAttachments does nothing when unauthenticated")
    func loadAttachmentsNoopWhenUnauthenticated() async throws {
        let db = try makeDB()
        let pool = db.dbPool
        let attachSvc = makeAttachmentService(pool: pool)
        let appState = AppState()
        let vm = await MainActor.run {
            AttachmentViewModel(postingId: UUID(), attachmentService: attachSvc, appState: appState)
        }
        await vm.loadAttachments()

        await MainActor.run {
            #expect(vm.attachments.isEmpty)
            #expect(vm.isLoading == false)
        }
    }

    @Test("quotaPercentage computes correctly")
    func quotaPercentageComputation() async throws {
        let db = try makeDB()
        let pool = db.dbPool
        let attachSvc = makeAttachmentService(pool: pool)
        let appState = AppState()

        let vm = await MainActor.run {
            AttachmentViewModel(postingId: UUID(), attachmentService: attachSvc, appState: appState)
        }

        await MainActor.run {
            vm.quotaUsed = 0
            vm.quotaTotal = 1000
            #expect(vm.quotaPercentage == 0.0)

            vm.quotaUsed = 500
            #expect(vm.quotaPercentage == 0.5)

            vm.quotaUsed = 1000
            #expect(vm.quotaPercentage == 1.0)

            vm.quotaTotal = 0
            #expect(vm.quotaPercentage == 0.0) // Guard against divide-by-zero
        }
    }

    @Test("quotaDisplay formats MB correctly")
    func quotaDisplayFormat() async throws {
        let db = try makeDB()
        let pool = db.dbPool
        let attachSvc = makeAttachmentService(pool: pool)
        let appState = AppState()

        let vm = await MainActor.run {
            AttachmentViewModel(postingId: UUID(), attachmentService: attachSvc, appState: appState)
        }

        await MainActor.run {
            vm.quotaUsed = 10 * 1024 * 1024   // 10 MB
            vm.quotaTotal = 2048 * 1024 * 1024 // 2048 MB
            let display = vm.quotaDisplay
            #expect(display.contains("10.0 MB"))
            #expect(display.contains("2048 MB"))
        }
    }

    @Test("upload sets errorMessage when not authorized")
    func uploadFailsWhenNotAuthorized() async throws {
        let db = try makeDB()
        let pool = db.dbPool
        let suffix = String(UUID().uuidString.prefix(8))
        let coord = try await makeCoordinator(pool: pool, suffix: suffix)
        let postingSvc = makePostingService(pool: pool)
        let attachSvc = makeAttachmentService(pool: pool) // no assignmentRepo

        let posting = try await postingSvc.create(
            actorId: coord.id, title: "AuthPosting \(suffix)", siteAddress: "Addr",
            dueDate: Date().addingTimeInterval(86400), budgetCents: 100,
            acceptanceMode: .open, watermarkEnabled: false
        )

        // Login as a different user who is neither admin/coord nor posting creator
        let now = Date()
        let stranger = User(
            id: UUID(), username: "stranger_\(suffix)", role: .technician, status: .active,
            failedLoginCount: 0, lockedUntil: nil, biometricEnabled: false,
            dndStartTime: nil, dndEndTime: nil, storageQuotaBytes: 2_147_483_648,
            version: 1, createdAt: now, updatedAt: now
        )
        try await pool.write { db in try stranger.insert(db) }

        let appState = AppState()
        appState.login(userId: stranger.id, role: .technician)

        let vm = await MainActor.run {
            AttachmentViewModel(postingId: posting.id, attachmentService: attachSvc, appState: appState)
        }

        let pngHeader = Data([0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A] + [UInt8](repeating: 0, count: 100))
        await vm.upload(data: pngHeader, fileName: "test.png", watermarkEnabled: false)

        await MainActor.run {
            #expect(vm.errorMessage != nil)
            #expect(vm.isUploading == false)
        }
    }
}

// MARK: - CommentListViewModel Tests

@Suite("CommentListViewModel Tests", .serialized)
struct CommentListViewModelTests {

    private func makeCommentService(pool: DatabasePool) -> CommentService {
        CommentService(
            dbPool: pool,
            commentRepository: CommentRepository(dbPool: pool),
            auditService: AuditService(dbPool: pool),
            postingRepository: PostingRepository(dbPool: pool),
            userRepository: UserRepository(dbPool: pool)
        )
    }

    @Test("loadComments populates threads for posting creator")
    func loadCommentsPopulates() async throws {
        let db = try makeDB()
        let pool = db.dbPool
        let suffix = String(UUID().uuidString.prefix(8))
        let admin = try await makeAdmin(pool: pool, suffix: suffix)
        let postingSvc = makePostingService(pool: pool)
        let commentSvc = makeCommentService(pool: pool)

        let posting = try await postingSvc.create(
            actorId: admin.id, title: "CommentPosting \(suffix)", siteAddress: "Addr",
            dueDate: Date().addingTimeInterval(86400), budgetCents: 100,
            acceptanceMode: .open, watermarkEnabled: false
        )

        let appState = AppState()
        appState.login(userId: admin.id, role: .admin)
        let vm = await MainActor.run {
            CommentListViewModel(postingId: posting.id, commentService: commentSvc, appState: appState)
        }
        await vm.loadComments()

        await MainActor.run {
            #expect(vm.threads.isEmpty)
            #expect(vm.isLoading == false)
            #expect(vm.errorMessage == nil)
        }
    }

    @Test("loadComments does nothing when unauthenticated")
    func loadCommentsNoopWhenUnauthenticated() async throws {
        let db = try makeDB()
        let pool = db.dbPool
        let commentSvc = makeCommentService(pool: pool)
        let appState = AppState()

        let vm = await MainActor.run {
            CommentListViewModel(postingId: UUID(), commentService: commentSvc, appState: appState)
        }
        await vm.loadComments()

        await MainActor.run {
            #expect(vm.threads.isEmpty)
            #expect(vm.isLoading == false)
        }
    }

    @Test("addComment adds comment and reloads threads")
    func addCommentAddsAndReloads() async throws {
        let db = try makeDB()
        let pool = db.dbPool
        let suffix = String(UUID().uuidString.prefix(8))
        let admin = try await makeAdmin(pool: pool, suffix: suffix)
        let postingSvc = makePostingService(pool: pool)
        let commentSvc = makeCommentService(pool: pool)

        let posting = try await postingSvc.create(
            actorId: admin.id, title: "AddCommentPosting \(suffix)", siteAddress: "Addr",
            dueDate: Date().addingTimeInterval(86400), budgetCents: 100,
            acceptanceMode: .open, watermarkEnabled: false
        )

        let appState = AppState()
        appState.login(userId: admin.id, role: .admin)
        let vm = await MainActor.run {
            CommentListViewModel(postingId: posting.id, commentService: commentSvc, appState: appState)
        }

        await MainActor.run {
            vm.newCommentBody = "Hello \(suffix)"
        }
        await vm.addComment()

        await MainActor.run {
            #expect(vm.errorMessage == nil)
            #expect(vm.newCommentBody == "")
            #expect(vm.threads.count >= 1)
        }
    }

    @Test("addComment does nothing when body is empty or whitespace")
    func addCommentNoopWhenBodyEmpty() async throws {
        let db = try makeDB()
        let pool = db.dbPool
        let suffix = String(UUID().uuidString.prefix(8))
        let admin = try await makeAdmin(pool: pool, suffix: suffix)
        let postingSvc = makePostingService(pool: pool)
        let commentSvc = makeCommentService(pool: pool)

        let posting = try await postingSvc.create(
            actorId: admin.id, title: "EmptyComment \(suffix)", siteAddress: "Addr",
            dueDate: Date().addingTimeInterval(86400), budgetCents: 100,
            acceptanceMode: .open, watermarkEnabled: false
        )

        let appState = AppState()
        appState.login(userId: admin.id, role: .admin)
        let vm = await MainActor.run {
            CommentListViewModel(postingId: posting.id, commentService: commentSvc, appState: appState)
        }

        await MainActor.run {
            vm.newCommentBody = "   " // whitespace only
        }
        await vm.addComment()

        await MainActor.run {
            #expect(vm.threads.isEmpty)
        }
    }

    @Test("addComment with replyingTo sets parent comment id")
    func addCommentReplyingTo() async throws {
        let db = try makeDB()
        let pool = db.dbPool
        let suffix = String(UUID().uuidString.prefix(8))
        let admin = try await makeAdmin(pool: pool, suffix: suffix)
        let postingSvc = makePostingService(pool: pool)
        let commentSvc = makeCommentService(pool: pool)

        let posting = try await postingSvc.create(
            actorId: admin.id, title: "ReplyPosting \(suffix)", siteAddress: "Addr",
            dueDate: Date().addingTimeInterval(86400), budgetCents: 100,
            acceptanceMode: .open, watermarkEnabled: false
        )

        let appState = AppState()
        appState.login(userId: admin.id, role: .admin)
        let vm = await MainActor.run {
            CommentListViewModel(postingId: posting.id, commentService: commentSvc, appState: appState)
        }

        // Add a root comment first
        await MainActor.run { vm.newCommentBody = "Root comment \(suffix)" }
        await vm.addComment()

        let rootId = await MainActor.run { vm.threads.first?.comment.id }
        guard let rootId else {
            Issue.record("Expected a root comment after addComment")
            return
        }

        // Now reply to it
        await MainActor.run {
            vm.replyingTo = rootId
            vm.newCommentBody = "Reply \(suffix)"
        }
        await vm.addComment()

        await MainActor.run {
            #expect(vm.replyingTo == nil) // Reset after posting
            #expect(vm.newCommentBody == "")
            let rootThread = vm.threads.first(where: { $0.comment.id == rootId })
            #expect(rootThread?.replies.isEmpty == false)
        }
    }
}
