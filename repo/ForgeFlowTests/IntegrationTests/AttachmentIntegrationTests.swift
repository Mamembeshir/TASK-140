import Foundation
import Testing
import GRDB
@testable import ForgeFlow

// MARK: - Attachment Service Integration Tests
//
// Covers: upload pipeline (magic-byte validation, size limit, quota, duplicate
// detection), list/get/download round-trips, admin-only original download,
// authorization matrix, and quota tracking.

@Suite("Attachment Integration Tests", .serialized)
struct AttachmentIntegrationTests {

    // MARK: - Minimal valid file fixtures

    /// JPEG magic bytes (first 12 bytes) — passes MagicBytesValidator.
    private static let jpeg12 = Data([
        0xFF, 0xD8, 0xFF, 0xE0, 0x00, 0x10,
        0x4A, 0x46, 0x49, 0x46, 0x00, 0x01
    ])

    /// PDF magic bytes — passes MagicBytesValidator.
    private static let pdf12 = Data([
        0x25, 0x50, 0x44, 0x46, 0x2D, 0x31,
        0x2E, 0x34, 0x0A, 0x25, 0xE2, 0xE3
    ])

    /// PNG magic bytes.
    private static let png12 = Data([
        0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A,
        0x1A, 0x0A, 0x00, 0x00, 0x00, 0x0D
    ])

    /// Truly random bytes — no valid magic header — should be rejected.
    private static let garbage = Data(repeating: 0xAB, count: 32)

    // MARK: - Fixture factory

    private struct Services {
        let dbPool: DatabasePool
        let attachmentService: AttachmentService
        let postingService: PostingService
        let assignmentService: AssignmentService
        let auditService: AuditService
    }

    private func makeServices() throws -> Services {
        let db = try DatabaseManager(inMemory: true)
        let pool = db.dbPool
        let auditSvc     = AuditService(dbPool: pool)
        let userRepo     = UserRepository(dbPool: pool)
        let postingRepo  = PostingRepository(dbPool: pool)
        let assignRepo   = AssignmentRepository(dbPool: pool)
        let taskRepo     = TaskRepository(dbPool: pool)
        let attachRepo   = AttachmentRepository(dbPool: pool)
        let attSvc = AttachmentService(
            dbPool: pool, attachmentRepository: attachRepo, auditService: auditSvc,
            userRepository: userRepo, postingRepository: postingRepo,
            assignmentRepository: assignRepo
        )
        let postingSvc = PostingService(
            dbPool: pool, postingRepository: postingRepo,
            taskRepository: taskRepo, userRepository: userRepo, auditService: auditSvc
        )
        let assignSvc = AssignmentService(
            dbPool: pool, assignmentRepository: assignRepo, postingRepository: postingRepo,
            userRepository: userRepo, auditService: auditSvc
        )
        return Services(
            dbPool: pool, attachmentService: attSvc,
            postingService: postingSvc, assignmentService: assignSvc, auditService: auditSvc
        )
    }

    private func makeUser(_ pool: DatabasePool, username: String, role: Role,
                          quotaBytes: Int = 2_147_483_648) async throws -> User {
        let now = Date()
        let user = User(
            id: UUID(), username: username, role: role, status: .active,
            failedLoginCount: 0, lockedUntil: nil, biometricEnabled: false,
            dndStartTime: nil, dndEndTime: nil,
            storageQuotaBytes: quotaBytes,
            version: 1, createdAt: now, updatedAt: now
        )
        try await pool.write { db in try user.insert(db) }
        return user
    }

    private func makeOpenPosting(_ s: Services, creatorId: UUID) async throws -> ServicePosting {
        let p = try await s.postingService.create(
            actorId: creatorId, title: "Plumbing Fix", siteAddress: "42 Pine St",
            dueDate: Date().addingTimeInterval(86400), budgetCents: 50_000,
            acceptanceMode: .open, watermarkEnabled: false
        )
        return try await s.postingService.publish(actorId: creatorId, postingId: p.id)
    }

    // MARK: - Magic-byte validation

    @Test("Upload with invalid magic bytes is rejected with invalidMagicBytes")
    func invalidMagicBytesRejected() async throws {
        let s = try makeServices()
        let admin = try await makeUser(s.dbPool, username: "a1", role: .admin)
        let posting = try await makeOpenPosting(s, creatorId: admin.id)

        await #expect(throws: AttachmentError.self) {
            _ = try await s.attachmentService.upload(
                fileData: Self.garbage, fileName: "bad.jpg",
                postingId: posting.id, commentId: nil, taskId: nil,
                uploadedBy: admin.id, watermarkEnabled: false
            )
        }
    }

    @Test("Upload with valid JPEG magic bytes succeeds")
    func validJpegUploads() async throws {
        let s = try makeServices()
        let admin = try await makeUser(s.dbPool, username: "a2", role: .admin)
        let posting = try await makeOpenPosting(s, creatorId: admin.id)

        let att = try await s.attachmentService.upload(
            fileData: Self.jpeg12, fileName: "photo.jpg",
            postingId: posting.id, commentId: nil, taskId: nil,
            uploadedBy: admin.id, watermarkEnabled: false
        )
        #expect(att.fileName == "photo.jpg")
        #expect(att.postingId == posting.id)
        #expect(att.uploadedBy == admin.id)
    }

    @Test("Upload with valid PDF magic bytes succeeds")
    func validPdfUploads() async throws {
        let s = try makeServices()
        let admin = try await makeUser(s.dbPool, username: "a3", role: .admin)
        let posting = try await makeOpenPosting(s, creatorId: admin.id)

        let att = try await s.attachmentService.upload(
            fileData: Self.pdf12, fileName: "report.pdf",
            postingId: posting.id, commentId: nil, taskId: nil,
            uploadedBy: admin.id, watermarkEnabled: false
        )
        #expect(att.mimeType == .pdf)
    }

    // MARK: - Duplicate detection

    @Test("Uploading the same file content twice to the same posting is rejected")
    func duplicateFileRejected() async throws {
        let s = try makeServices()
        let admin = try await makeUser(s.dbPool, username: "a4", role: .admin)
        let posting = try await makeOpenPosting(s, creatorId: admin.id)

        _ = try await s.attachmentService.upload(
            fileData: Self.pdf12, fileName: "first.pdf",
            postingId: posting.id, commentId: nil, taskId: nil,
            uploadedBy: admin.id
        )

        await #expect(throws: AttachmentError.self) {
            _ = try await s.attachmentService.upload(
                fileData: Self.pdf12, fileName: "duplicate.pdf",
                postingId: posting.id, commentId: nil, taskId: nil,
                uploadedBy: admin.id
            )
        }
    }

    @Test("Same file content on a different posting is accepted (checksum is per-posting)")
    func sameFileOnDifferentPostingAccepted() async throws {
        let s = try makeServices()
        let coord = try await makeUser(s.dbPool, username: "c1", role: .coordinator)
        let p1 = try await makeOpenPosting(s, creatorId: coord.id)
        let p2 = try await makeOpenPosting(s, creatorId: coord.id)

        _ = try await s.attachmentService.upload(
            fileData: Self.pdf12, fileName: "doc.pdf",
            postingId: p1.id, commentId: nil, taskId: nil,
            uploadedBy: coord.id
        )
        let att2 = try await s.attachmentService.upload(
            fileData: Self.pdf12, fileName: "doc.pdf",
            postingId: p2.id, commentId: nil, taskId: nil,
            uploadedBy: coord.id
        )
        #expect(att2.postingId == p2.id)
    }

    // MARK: - File-size limit

    @Test("File exceeding 250 MB is rejected")
    func oversizedFileRejected() async throws {
        let s = try makeServices()
        let admin = try await makeUser(s.dbPool, username: "a5", role: .admin)
        let posting = try await makeOpenPosting(s, creatorId: admin.id)

        // Build a data blob that exceeds the 250 MB limit.
        // We only need to exceed the byte-count check; we patch a valid PDF header on front.
        let oversized = Self.pdf12 + Data(
            repeating: 0x00,
            count: AttachmentService.maxFileSizeBytes + 1 - Self.pdf12.count
        )

        await #expect(throws: AttachmentError.self) {
            _ = try await s.attachmentService.upload(
                fileData: oversized, fileName: "huge.pdf",
                postingId: posting.id, commentId: nil, taskId: nil,
                uploadedBy: admin.id
            )
        }
    }

    // MARK: - Quota enforcement

    @Test("Upload is rejected when user has insufficient storage quota")
    func quotaExceededRejected() async throws {
        let s = try makeServices()
        // Give the user exactly 1 byte of quota — any real file will exceed it.
        let tinyUser = try await makeUser(s.dbPool, username: "tiny", role: .admin, quotaBytes: 1)
        let posting = try await makeOpenPosting(s, creatorId: tinyUser.id)

        await #expect(throws: AttachmentError.self) {
            _ = try await s.attachmentService.upload(
                fileData: Self.pdf12, fileName: "any.pdf",
                postingId: posting.id, commentId: nil, taskId: nil,
                uploadedBy: tinyUser.id
            )
        }
    }

    @Test("getQuotaUsage returns correct used/quota tuple after upload")
    func quotaUsageAfterUpload() async throws {
        let s = try makeServices()
        let admin = try await makeUser(s.dbPool, username: "a6", role: .admin)
        let posting = try await makeOpenPosting(s, creatorId: admin.id)

        let (usedBefore, quota) = try await s.attachmentService.getQuotaUsage(userId: admin.id)
        #expect(usedBefore == 0)
        #expect(quota == 2_147_483_648)

        _ = try await s.attachmentService.upload(
            fileData: Self.jpeg12, fileName: "img.jpg",
            postingId: posting.id, commentId: nil, taskId: nil,
            uploadedBy: admin.id
        )

        let (usedAfter, _) = try await s.attachmentService.getQuotaUsage(userId: admin.id)
        #expect(usedAfter == Self.jpeg12.count)
    }

    // MARK: - List and get

    @Test("listAttachments(postingId:) returns only the posting's attachments")
    func listByPosting() async throws {
        let s = try makeServices()
        let admin = try await makeUser(s.dbPool, username: "a7", role: .admin)
        let p1 = try await makeOpenPosting(s, creatorId: admin.id)
        let p2 = try await makeOpenPosting(s, creatorId: admin.id)

        _ = try await s.attachmentService.upload(
            fileData: Self.jpeg12, fileName: "p1img.jpg",
            postingId: p1.id, commentId: nil, taskId: nil,
            uploadedBy: admin.id
        )
        _ = try await s.attachmentService.upload(
            fileData: Self.pdf12, fileName: "p2doc.pdf",
            postingId: p2.id, commentId: nil, taskId: nil,
            uploadedBy: admin.id
        )

        let p1Atts = try await s.attachmentService.listAttachments(postingId: p1.id, actorId: admin.id)
        #expect(p1Atts.count == 1)
        #expect(p1Atts[0].fileName == "p1img.jpg")

        let p2Atts = try await s.attachmentService.listAttachments(postingId: p2.id, actorId: admin.id)
        #expect(p2Atts.count == 1)
        #expect(p2Atts[0].fileName == "p2doc.pdf")
    }

    @Test("getAttachment returns the correct record for a known id")
    func getAttachmentById() async throws {
        let s = try makeServices()
        let admin = try await makeUser(s.dbPool, username: "a8", role: .admin)
        let posting = try await makeOpenPosting(s, creatorId: admin.id)

        let uploaded = try await s.attachmentService.upload(
            fileData: Self.pdf12, fileName: "lookup.pdf",
            postingId: posting.id, commentId: nil, taskId: nil,
            uploadedBy: admin.id
        )

        let fetched = try await s.attachmentService.getAttachment(id: uploaded.id, actorId: admin.id)
        #expect(fetched.id == uploaded.id)
        #expect(fetched.fileName == "lookup.pdf")
    }

    @Test("getAttachment throws fileNotFound for unknown id")
    func getAttachmentUnknownId() async throws {
        let s = try makeServices()
        let admin = try await makeUser(s.dbPool, username: "a9", role: .admin)

        await #expect(throws: AttachmentError.self) {
            _ = try await s.attachmentService.getAttachment(id: UUID(), actorId: admin.id)
        }
    }

    // MARK: - Authorization

    @Test("Uninvited technician cannot upload to a posting")
    func uninvitedTechCannotUpload() async throws {
        let s = try makeServices()
        let coord = try await makeUser(s.dbPool, username: "c2", role: .coordinator)
        let stranger = try await makeUser(s.dbPool, username: "stranger", role: .technician)
        let posting = try await makeOpenPosting(s, creatorId: coord.id)

        await #expect(throws: AttachmentError.self) {
            _ = try await s.attachmentService.upload(
                fileData: Self.pdf12, fileName: "sneak.pdf",
                postingId: posting.id, commentId: nil, taskId: nil,
                uploadedBy: stranger.id
            )
        }
    }

    @Test("Accepted technician can upload to a posting")
    func acceptedTechCanUpload() async throws {
        let s = try makeServices()
        let coord = try await makeUser(s.dbPool, username: "c3", role: .coordinator)
        let tech = try await makeUser(s.dbPool, username: "t1", role: .technician)
        let posting = try await makeOpenPosting(s, creatorId: coord.id)
        _ = try await s.assignmentService.accept(actorId: tech.id, postingId: posting.id, technicianId: tech.id)

        let att = try await s.attachmentService.upload(
            fileData: Self.pdf12, fileName: "fieldnotes.pdf",
            postingId: posting.id, commentId: nil, taskId: nil,
            uploadedBy: tech.id
        )
        #expect(att.uploadedBy == tech.id)
    }

    @Test("Non-admin cannot download the watermarked original")
    func nonAdminCannotDownloadOriginal() async throws {
        let s = try makeServices()
        let admin = try await makeUser(s.dbPool, username: "a10", role: .admin)
        let tech  = try await makeUser(s.dbPool, username: "t2", role: .technician)
        let posting = try await makeOpenPosting(s, creatorId: admin.id)
        _ = try await s.assignmentService.accept(actorId: tech.id, postingId: posting.id, technicianId: tech.id)

        let att = try await s.attachmentService.upload(
            fileData: Self.jpeg12, fileName: "site.jpg",
            postingId: posting.id, commentId: nil, taskId: nil,
            uploadedBy: tech.id, watermarkEnabled: true, watermarkUsername: "t2"
        )
        // att.originalEncryptedPath may be nil if WatermarkRenderer can't render
        // the 12-byte stub. Either way, a non-admin must be rejected.
        await #expect(throws: AttachmentError.self) {
            _ = try await s.attachmentService.downloadOriginal(id: att.id, actorId: tech.id)
        }
    }

    // MARK: - Checksum & integrity

    @Test("Uploaded attachment stores a non-empty SHA-256 checksum")
    func checksumIsStored() async throws {
        let s = try makeServices()
        let admin = try await makeUser(s.dbPool, username: "a11", role: .admin)
        let posting = try await makeOpenPosting(s, creatorId: admin.id)

        let att = try await s.attachmentService.upload(
            fileData: Self.jpeg12, fileName: "integrity.jpg",
            postingId: posting.id, commentId: nil, taskId: nil,
            uploadedBy: admin.id
        )

        #expect(!att.checksumSha256.isEmpty)
        #expect(att.checksumSha256 == HashValidator.sha256Hex(data: Self.jpeg12))
    }

    // MARK: - Download round-trip

    @Test("downloadAttachment retrieves the exact bytes that were uploaded")
    func downloadRoundTrip() async throws {
        let s = try makeServices()
        let admin = try await makeUser(s.dbPool, username: "a12", role: .admin)
        let posting = try await makeOpenPosting(s, creatorId: admin.id)

        // Use a payload with distinguishable content beyond the header
        var payload = Self.pdf12
        payload.append(Data("unique-payload-\(UUID().uuidString)".utf8))

        let att = try await s.attachmentService.upload(
            fileData: payload, fileName: "roundtrip.pdf",
            postingId: posting.id, commentId: nil, taskId: nil,
            uploadedBy: admin.id
        )

        let downloaded = try await s.attachmentService.downloadAttachment(id: att.id, actorId: admin.id)
        #expect(downloaded == payload)
    }
}
