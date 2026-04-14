import Foundation
import Testing
import GRDB
@testable import ForgeFlow

/// Integration tests that assert authorization denials across all service layers.
/// Every test here verifies that a caller with insufficient role or object access is
/// explicitly rejected — not silently permitted.
@Suite("Authorization and Role Boundary Tests")
struct AuthorizationTests {

    // MARK: - Context

    private struct Context {
        let dbPool: DatabasePool
        let authService: AuthService
        let postingService: PostingService
        let assignmentService: AssignmentService
        let taskService: TaskService
        let commentService: CommentService
        let attachmentService: AttachmentService
        let syncService: SyncService
        let userRepo: UserRepository
    }

    private func makeContext() throws -> Context {
        let db = try DatabaseManager(inMemory: true)
        let dbPool = db.dbPool
        let userRepo = UserRepository(dbPool: dbPool)
        let auditService = AuditService(dbPool: dbPool)
        let postingRepo = PostingRepository(dbPool: dbPool)
        let assignmentRepo = AssignmentRepository(dbPool: dbPool)
        let taskRepo = TaskRepository(dbPool: dbPool)
        let depRepo = DependencyRepository(dbPool: dbPool)
        let commentRepo = CommentRepository(dbPool: dbPool)
        let attachmentRepo = AttachmentRepository(dbPool: dbPool)
        let syncRepo = SyncRepository(dbPool: dbPool)

        let postingService = PostingService(
            dbPool: dbPool, postingRepository: postingRepo,
            taskRepository: taskRepo, userRepository: userRepo, auditService: auditService
        )
        let assignmentService = AssignmentService(
            dbPool: dbPool, assignmentRepository: assignmentRepo,
            postingRepository: postingRepo, userRepository: userRepo, auditService: auditService
        )
        let taskService = TaskService(
            dbPool: dbPool, taskRepository: taskRepo,
            dependencyRepository: depRepo, postingRepository: postingRepo,
            auditService: auditService, userRepository: userRepo
        )
        let commentService = CommentService(
            dbPool: dbPool, commentRepository: commentRepo, auditService: auditService,
            postingRepository: postingRepo, assignmentRepository: assignmentRepo,
            userRepository: userRepo
        )
        let attachmentService = AttachmentService(
            dbPool: dbPool, attachmentRepository: attachmentRepo, auditService: auditService,
            userRepository: userRepo, postingRepository: postingRepo,
            assignmentRepository: assignmentRepo
        )
        let authService = AuthService(
            dbPool: dbPool, userRepository: userRepo, auditService: auditService
        )
        let syncService = SyncService(
            dbPool: dbPool, syncRepository: syncRepo,
            postingRepository: postingRepo, auditService: auditService,
            userRepository: userRepo
        )
        return Context(
            dbPool: dbPool, authService: authService, postingService: postingService,
            assignmentService: assignmentService, taskService: taskService,
            commentService: commentService, attachmentService: attachmentService,
            syncService: syncService, userRepo: userRepo
        )
    }

    private func seedUser(_ userRepo: UserRepository, role: Role) async throws -> User {
        let now = Date()
        let user = User(
            id: UUID(), username: "\(role.rawValue.lowercased())_\(UUID().uuidString.prefix(6))",
            role: role, status: .active,
            failedLoginCount: 0, lockedUntil: nil, biometricEnabled: false,
            dndStartTime: nil, dndEndTime: nil,
            storageQuotaBytes: 2_147_483_648,
            version: 1, createdAt: now, updatedAt: now
        )
        try await userRepo.insert(user)
        return user
    }

    // MARK: - AuthService: admin-only operations

    @Test("Authz: technician cannot create a user (admin-only)")
    func technicianCannotCreateUser() async throws {
        let ctx = try makeContext()
        let tech = try await seedUser(ctx.userRepo, role: .technician)

        do {
            _ = try await ctx.authService.createUser(
                actorId: tech.id, username: "newuser", password: "password123", role: .technician
            )
            Issue.record("Expected notAuthorized")
        } catch let e as AuthError {
            if case .notAuthorized = e { /* expected */ }
            else { Issue.record("Expected .notAuthorized, got \(e)") }
        }
    }

    @Test("Authz: coordinator cannot create a user (admin-only)")
    func coordinatorCannotCreateUser() async throws {
        let ctx = try makeContext()
        let coord = try await seedUser(ctx.userRepo, role: .coordinator)

        do {
            _ = try await ctx.authService.createUser(
                actorId: coord.id, username: "newuser", password: "password123", role: .technician
            )
            Issue.record("Expected notAuthorized")
        } catch let e as AuthError {
            if case .notAuthorized = e { /* expected */ }
            else { Issue.record("Expected .notAuthorized, got \(e)") }
        }
    }

    @Test("Authz: technician cannot list all users (admin-only)")
    func technicianCannotListUsers() async throws {
        let ctx = try makeContext()
        let tech = try await seedUser(ctx.userRepo, role: .technician)

        do {
            _ = try await ctx.authService.listUsers(actorId: tech.id)
            Issue.record("Expected notAuthorized")
        } catch let e as AuthError {
            if case .notAuthorized = e { /* expected */ }
            else { Issue.record("Expected .notAuthorized, got \(e)") }
        }
    }

    @Test("Authz: technician cannot deactivate another user (admin-only)")
    func technicianCannotUpdateUserStatus() async throws {
        let ctx = try makeContext()
        let tech = try await seedUser(ctx.userRepo, role: .technician)
        let other = try await seedUser(ctx.userRepo, role: .coordinator)

        do {
            _ = try await ctx.authService.updateUserStatus(
                actorId: tech.id, userId: other.id, status: .deactivated
            )
            Issue.record("Expected notAuthorized")
        } catch let e as AuthError {
            if case .notAuthorized = e { /* expected */ }
            else { Issue.record("Expected .notAuthorized, got \(e)") }
        }
    }

    @Test("Authz: technician cannot toggle ANOTHER user's biometric (self-or-admin)")
    func technicianCannotToggleOtherBiometric() async throws {
        let ctx = try makeContext()
        let tech = try await seedUser(ctx.userRepo, role: .technician)
        let other = try await seedUser(ctx.userRepo, role: .technician)

        do {
            _ = try await ctx.authService.toggleBiometric(
                actorId: tech.id, userId: other.id, enabled: true
            )
            Issue.record("Expected notAuthorized")
        } catch let e as AuthError {
            if case .notAuthorized = e { /* expected */ }
            else { Issue.record("Expected .notAuthorized, got \(e)") }
        }
    }

    @Test("Authz: technician CAN toggle their OWN biometric (self-access)")
    func technicianCanToggleOwnBiometric() async throws {
        let ctx = try makeContext()
        let tech = try await seedUser(ctx.userRepo, role: .technician)

        let updated = try await ctx.authService.toggleBiometric(
            actorId: tech.id, userId: tech.id, enabled: true
        )
        #expect(updated.biometricEnabled == true)
    }

    // MARK: - PostingService: role boundaries

    @Test("Authz: technician cannot create a posting")
    func technicianCannotCreatePosting() async throws {
        let ctx = try makeContext()
        let tech = try await seedUser(ctx.userRepo, role: .technician)

        do {
            _ = try await ctx.postingService.create(
                actorId: tech.id, title: "Test", siteAddress: "123 Main",
                dueDate: Date().addingTimeInterval(86400), budgetCents: 1000,
                acceptanceMode: .open, watermarkEnabled: false
            )
            Issue.record("Expected notAuthorized")
        } catch let e as PostingError {
            if case .notAuthorized = e { /* expected */ }
            else { Issue.record("Expected .notAuthorized, got \(e)") }
        }
    }

    @Test("Authz: unassigned technician cannot view an IN_PROGRESS posting")
    func nonParticipantCannotGetInProgressPosting() async throws {
        let ctx = try makeContext()
        let coord = try await seedUser(ctx.userRepo, role: .coordinator)
        let tech1 = try await seedUser(ctx.userRepo, role: .technician)
        let tech2 = try await seedUser(ctx.userRepo, role: .technician)

        // Create and publish an OPEN posting
        let posting = try await ctx.postingService.create(
            actorId: coord.id, title: "In-Progress Posting", siteAddress: "456 Oak",
            dueDate: Date().addingTimeInterval(86400), budgetCents: 5000,
            acceptanceMode: .open, watermarkEnabled: false
        )
        _ = try await ctx.postingService.publish(actorId: coord.id, postingId: posting.id)

        // tech1 accepts → posting moves to IN_PROGRESS; tech2 has no assignment
        _ = try await ctx.assignmentService.accept(
            actorId: tech1.id, postingId: posting.id, technicianId: tech1.id
        )

        // tech2 (no assignment) should be denied access to the now-IN_PROGRESS posting
        do {
            _ = try await ctx.postingService.getPosting(id: posting.id, actorId: tech2.id)
            Issue.record("Expected notAuthorized for unassigned tech on IN_PROGRESS posting")
        } catch let e as PostingError {
            if case .notAuthorized = e { /* expected */ }
            else { Issue.record("Expected .notAuthorized, got \(e)") }
        }
    }

    // MARK: - CommentService: participant access

    @Test("Authz: unassigned technician cannot post a comment")
    func unassignedTechCannotComment() async throws {
        let ctx = try makeContext()
        let coord = try await seedUser(ctx.userRepo, role: .coordinator)
        let tech = try await seedUser(ctx.userRepo, role: .technician)

        let posting = try await ctx.postingService.create(
            actorId: coord.id, title: "Comment Test", siteAddress: "789 Pine",
            dueDate: Date().addingTimeInterval(86400), budgetCents: 5000,
            acceptanceMode: .open, watermarkEnabled: false
        )
        _ = try await ctx.postingService.publish(actorId: coord.id, postingId: posting.id)

        do {
            _ = try await ctx.commentService.create(
                postingId: posting.id, authorId: tech.id,
                body: "I should not be able to post this"
            )
            Issue.record("Expected notAuthorized")
        } catch let e as PostingError {
            if case .notAuthorized = e { /* expected */ }
            else { Issue.record("Expected .notAuthorized, got \(e)") }
        }
    }

    @Test("Authz: invited-but-not-accepted technician cannot post a comment")
    func invitedOnlyTechCannotComment() async throws {
        let ctx = try makeContext()
        let coord = try await seedUser(ctx.userRepo, role: .coordinator)
        let tech = try await seedUser(ctx.userRepo, role: .technician)

        let posting = try await ctx.postingService.create(
            actorId: coord.id, title: "Invite Test", siteAddress: "321 Elm",
            dueDate: Date().addingTimeInterval(86400), budgetCents: 5000,
            acceptanceMode: .inviteOnly, watermarkEnabled: false
        )
        _ = try await ctx.postingService.publish(actorId: coord.id, postingId: posting.id)
        _ = try await ctx.assignmentService.invite(
            actorId: coord.id, postingId: posting.id, technicianIds: [tech.id]
        )
        // Deliberately NOT accepting — tech is INVITED but not ACCEPTED

        do {
            _ = try await ctx.commentService.create(
                postingId: posting.id, authorId: tech.id,
                body: "I was only invited, not accepted"
            )
            Issue.record("Expected notAuthorized")
        } catch let e as PostingError {
            if case .notAuthorized = e { /* expected */ }
            else { Issue.record("Expected .notAuthorized, got \(e)") }
        }
    }

    // MARK: - AttachmentService: participant access

    @Test("Authz: unassigned technician cannot upload an attachment")
    func unassignedTechCannotUpload() async throws {
        let ctx = try makeContext()
        let coord = try await seedUser(ctx.userRepo, role: .coordinator)
        let tech = try await seedUser(ctx.userRepo, role: .technician)

        let posting = try await ctx.postingService.create(
            actorId: coord.id, title: "Upload Test", siteAddress: "555 Maple",
            dueDate: Date().addingTimeInterval(86400), budgetCents: 5000,
            acceptanceMode: .open, watermarkEnabled: false
        )
        _ = try await ctx.postingService.publish(actorId: coord.id, postingId: posting.id)

        do {
            _ = try await ctx.attachmentService.upload(
                fileData: Data([0xFF, 0xD8, 0xFF, 0xE0]), // JPEG magic bytes
                fileName: "test.jpg", postingId: posting.id,
                commentId: nil, taskId: nil, uploadedBy: tech.id
            )
            Issue.record("Expected notAuthorized")
        } catch let e as AttachmentError {
            if case .notAuthorized = e { /* expected */ }
            else { Issue.record("Expected .notAuthorized, got \(e)") }
        }
    }

    @Test("Authz: invited-only technician cannot upload (accepted status required)")
    func invitedOnlyTechCannotUpload() async throws {
        let ctx = try makeContext()
        let coord = try await seedUser(ctx.userRepo, role: .coordinator)
        let tech = try await seedUser(ctx.userRepo, role: .technician)

        let posting = try await ctx.postingService.create(
            actorId: coord.id, title: "Upload Invite Test", siteAddress: "666 Cedar",
            dueDate: Date().addingTimeInterval(86400), budgetCents: 5000,
            acceptanceMode: .inviteOnly, watermarkEnabled: false
        )
        _ = try await ctx.postingService.publish(actorId: coord.id, postingId: posting.id)
        _ = try await ctx.assignmentService.invite(
            actorId: coord.id, postingId: posting.id, technicianIds: [tech.id]
        )
        // Deliberately NOT accepting

        do {
            _ = try await ctx.attachmentService.upload(
                fileData: Data([0xFF, 0xD8, 0xFF, 0xE0]),
                fileName: "test.jpg", postingId: posting.id,
                commentId: nil, taskId: nil, uploadedBy: tech.id
            )
            Issue.record("Expected notAuthorized")
        } catch let e as AttachmentError {
            if case .notAuthorized = e { /* expected */ }
            else { Issue.record("Expected .notAuthorized, got \(e)") }
        }
    }

    // MARK: - TaskService: participant access

    @Test("Authz: unassigned technician cannot list tasks for a posting")
    func unassignedTechCannotListTasks() async throws {
        let ctx = try makeContext()
        let coord = try await seedUser(ctx.userRepo, role: .coordinator)
        let tech = try await seedUser(ctx.userRepo, role: .technician)

        let posting = try await ctx.postingService.create(
            actorId: coord.id, title: "Task List Test", siteAddress: "777 Birch",
            dueDate: Date().addingTimeInterval(86400), budgetCents: 5000,
            acceptanceMode: .inviteOnly, watermarkEnabled: false
        )
        _ = try await ctx.postingService.publish(actorId: coord.id, postingId: posting.id)

        do {
            _ = try await ctx.taskService.listTasks(postingId: posting.id, actorId: tech.id)
            Issue.record("Expected notAuthorized")
        } catch let e as TaskError {
            if case .notAuthorized = e { /* expected */ }
            else { Issue.record("Expected .notAuthorized, got \(e)") }
        }
    }

    @Test("Authz: unassigned technician cannot update task status")
    func unassignedTechCannotUpdateTaskStatus() async throws {
        let ctx = try makeContext()
        let coord = try await seedUser(ctx.userRepo, role: .coordinator)
        let tech = try await seedUser(ctx.userRepo, role: .technician)

        let posting = try await ctx.postingService.create(
            actorId: coord.id, title: "Task Status Test", siteAddress: "888 Walnut",
            dueDate: Date().addingTimeInterval(86400), budgetCents: 5000,
            acceptanceMode: .open, watermarkEnabled: false
        )
        _ = try await ctx.postingService.publish(actorId: coord.id, postingId: posting.id)
        let tasks = try await ctx.taskService.listTasks(postingId: posting.id, actorId: coord.id)
        let leaf = tasks.first { $0.parentTaskId != nil }!

        do {
            _ = try await ctx.taskService.updateStatus(
                actorId: tech.id, taskId: leaf.id, newStatus: .inProgress
            )
            Issue.record("Expected notAuthorized")
        } catch let e as TaskError {
            if case .notAuthorized = e { /* expected */ }
            else { Issue.record("Expected .notAuthorized, got \(e)") }
        }
    }

    // MARK: - SyncService: admin/coordinator only

    @Test("Authz: technician cannot trigger a sync export")
    func technicianCannotExport() async throws {
        let ctx = try makeContext()
        let tech = try await seedUser(ctx.userRepo, role: .technician)

        do {
            _ = try await ctx.syncService.export(
                entityTypes: ["postings"], startDate: nil, endDate: nil,
                exportedBy: tech.id
            )
            Issue.record("Expected authorization error")
        } catch let e as SyncError {
            // Expect exportFailed(reason: "Not authorized") or notAuthorized
            switch e {
            case .exportFailed, .notAuthorized: break // expected
            default: Issue.record("Expected auth-related SyncError, got \(e)")
            }
        }
    }

    @Test("Authz: technician cannot list sync exports")
    func technicianCannotListExports() async throws {
        let ctx = try makeContext()
        let tech = try await seedUser(ctx.userRepo, role: .technician)

        do {
            _ = try await ctx.syncService.listExports(actorId: tech.id)
            Issue.record("Expected notAuthorized")
        } catch let e as SyncError {
            if case .notAuthorized = e { /* expected */ }
            else { Issue.record("Expected .notAuthorized, got \(e)") }
        }
    }

    // MARK: - AssignmentService: identity and role checks

    @Test("Authz: technician cannot invite others to a posting (coordinator-only)")
    func technicianCannotInviteOthers() async throws {
        let ctx = try makeContext()
        let coord = try await seedUser(ctx.userRepo, role: .coordinator)
        let tech = try await seedUser(ctx.userRepo, role: .technician)
        let target = try await seedUser(ctx.userRepo, role: .technician)

        let posting = try await ctx.postingService.create(
            actorId: coord.id, title: "Invite Auth Test", siteAddress: "999 Oak",
            dueDate: Date().addingTimeInterval(86400), budgetCents: 5000,
            acceptanceMode: .inviteOnly, watermarkEnabled: false
        )
        _ = try await ctx.postingService.publish(actorId: coord.id, postingId: posting.id)

        do {
            _ = try await ctx.assignmentService.invite(
                actorId: tech.id, postingId: posting.id, technicianIds: [target.id]
            )
            Issue.record("Expected notAuthorized")
        } catch let e as AssignmentError {
            if case .notAuthorized = e { /* expected */ }
            else { Issue.record("Expected .notAuthorized, got \(e)") }
        }
    }

    @Test("Authz: technician cannot accept on behalf of another technician")
    func technicianCannotAcceptForOther() async throws {
        let ctx = try makeContext()
        let coord = try await seedUser(ctx.userRepo, role: .coordinator)
        let tech1 = try await seedUser(ctx.userRepo, role: .technician)
        let tech2 = try await seedUser(ctx.userRepo, role: .technician)

        let posting = try await ctx.postingService.create(
            actorId: coord.id, title: "Accept Auth Test", siteAddress: "100 Spruce",
            dueDate: Date().addingTimeInterval(86400), budgetCents: 5000,
            acceptanceMode: .open, watermarkEnabled: false
        )
        _ = try await ctx.postingService.publish(actorId: coord.id, postingId: posting.id)

        // tech1 tries to accept the posting as if they were tech2
        do {
            _ = try await ctx.assignmentService.accept(
                actorId: tech1.id, postingId: posting.id, technicianId: tech2.id
            )
            Issue.record("Expected notAuthorized")
        } catch let e as AssignmentError {
            if case .notAuthorized = e { /* expected */ }
            else { Issue.record("Expected .notAuthorized, got \(e)") }
        }
    }
}
