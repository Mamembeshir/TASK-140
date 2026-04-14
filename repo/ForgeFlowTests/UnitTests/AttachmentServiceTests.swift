import Foundation
import Testing
import GRDB
@testable import ForgeFlow

@Suite("AttachmentService Tests")
struct AttachmentServiceTests {

    // MARK: - Minimal magic-byte fixtures

    /// 12-byte JPEG header that passes MagicBytesValidator but carries no real image pixels.
    private static let minimalJpegData = Data([
        0xFF, 0xD8, 0xFF, 0xE0,
        0x00, 0x10, 0x4A, 0x46,
        0x49, 0x46, 0x00, 0x01
    ])

    /// 12-byte PDF header that passes MagicBytesValidator.
    private static let minimalPdfData = Data([
        0x25, 0x50, 0x44, 0x46,  // %PDF
        0x2D, 0x31, 0x2E, 0x34,  // -1.4
        0x0A, 0x25, 0xE2, 0xE3
    ])

    // MARK: - Test fixture helpers

    private func makeService() throws -> (AttachmentService, DatabasePool) {
        let dbManager = try DatabaseManager(inMemory: true)
        let dbPool = dbManager.dbPool
        let service = AttachmentService(
            dbPool: dbPool,
            attachmentRepository: AttachmentRepository(dbPool: dbPool),
            auditService: AuditService(dbPool: dbPool),
            userRepository: UserRepository(dbPool: dbPool),
            postingRepository: PostingRepository(dbPool: dbPool),
            assignmentRepository: AssignmentRepository(dbPool: dbPool)
        )
        return (service, dbPool)
    }

    private func seedUserAndPosting(dbPool: DatabasePool) async throws -> (User, ServicePosting) {
        let now = Date()
        let user = User(
            id: UUID(), username: "alice", role: .admin, status: .active,
            failedLoginCount: 0, lockedUntil: nil, biometricEnabled: false,
            dndStartTime: nil, dndEndTime: nil,
            storageQuotaBytes: 2_147_483_648,
            version: 1, createdAt: now, updatedAt: now
        )
        let posting = ServicePosting(
            id: UUID(), title: "Fix HVAC", siteAddress: "123 Main St",
            dueDate: Date().addingTimeInterval(86400), budgetCapCents: 50000,
            status: .open, acceptanceMode: .open,
            createdBy: user.id, watermarkEnabled: false,
            version: 1, createdAt: now, updatedAt: now
        )
        try await dbPool.write { db in
            try user.insert(db)
            try posting.insert(db)
        }
        return (user, posting)
    }

    // MARK: - WatermarkRenderer unit tests

    @Test("WatermarkRenderer.render returns nil for non-image bytes")
    func watermarkRendererWithInvalidDataReturnsNil() {
        let result = WatermarkRenderer.render(imageData: Data(repeating: 0x00, count: 100), username: "alice")
        #expect(result == nil)
    }

    // MARK: - AttachmentEncryptor unit tests

    @Test("AttachmentEncryptor encrypt/decrypt round-trip recovers original data")
    func encryptDecryptRoundTrip() throws {
        let original = Data("ForgeFlow watermark test payload".utf8)
        let fileId = UUID()
        let encrypted = try AttachmentEncryptor.encrypt(data: original, fileId: fileId)
        let decrypted = try AttachmentEncryptor.decrypt(combinedData: encrypted, fileId: fileId)
        #expect(decrypted == original)
    }

    @Test("AttachmentEncryptor produces distinct ciphertext for different fileIds")
    func encryptProducesDifferentCiphertextPerFileId() throws {
        let data = Data("same data".utf8)
        let enc1 = try AttachmentEncryptor.encrypt(data: data, fileId: UUID())
        let enc2 = try AttachmentEncryptor.encrypt(data: data, fileId: UUID())
        #expect(enc1 != enc2)
    }

    // MARK: - Watermark path integration tests

    @Test("upload with watermarkEnabled=false: originalEncryptedPath is nil")
    func uploadNoWatermarkLeavesOriginalEncryptedPathNil() async throws {
        let (service, dbPool) = try makeService()
        let (user, posting) = try await seedUserAndPosting(dbPool: dbPool)

        let attachment = try await service.upload(
            fileData: Self.minimalPdfData,
            fileName: "test.pdf",
            postingId: posting.id,
            commentId: nil, taskId: nil,
            uploadedBy: user.id,
            watermarkEnabled: false
        )

        #expect(attachment.originalEncryptedPath == nil)
    }

    @Test("upload with watermarkEnabled=true but watermarkUsername=nil: originalEncryptedPath is nil")
    func uploadWatermarkEnabledWithoutUsernameSuppressesWatermarkPath() async throws {
        let (service, dbPool) = try makeService()
        let (user, posting) = try await seedUserAndPosting(dbPool: dbPool)

        let attachment = try await service.upload(
            fileData: Self.minimalJpegData,
            fileName: "photo.jpg",
            postingId: posting.id,
            commentId: nil, taskId: nil,
            uploadedBy: user.id,
            watermarkEnabled: true,
            watermarkUsername: nil
        )

        #expect(attachment.originalEncryptedPath == nil)
    }

    @Test("upload with watermarkEnabled=true + username on PDF (non-image): originalEncryptedPath is nil")
    func uploadWatermarkOnNonImageSkipsEncryptedOriginal() async throws {
        let (service, dbPool) = try makeService()
        let (user, posting) = try await seedUserAndPosting(dbPool: dbPool)

        let attachment = try await service.upload(
            fileData: Self.minimalPdfData,
            fileName: "document.pdf",
            postingId: posting.id,
            commentId: nil, taskId: nil,
            uploadedBy: user.id,
            watermarkEnabled: true,
            watermarkUsername: "alice"
        )

        #expect(attachment.originalEncryptedPath == nil)
    }

    @Test("upload with watermarkEnabled=true + username on JPEG: originalEncryptedPath is set")
    func uploadWatermarkOnJpegSetsEncryptedOriginalPath() async throws {
        let (service, dbPool) = try makeService()
        let (user, posting) = try await seedUserAndPosting(dbPool: dbPool)

        let attachment = try await service.upload(
            fileData: Self.minimalJpegData,
            fileName: "photo.jpg",
            postingId: posting.id,
            commentId: nil, taskId: nil,
            uploadedBy: user.id,
            watermarkEnabled: true,
            watermarkUsername: "alice"
        )

        #expect(attachment.originalEncryptedPath != nil)
    }
}
