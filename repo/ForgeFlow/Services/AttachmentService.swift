import Foundation
import GRDB
import os.log

final class AttachmentService: Sendable {
    private let dbPool: DatabasePool
    private let attachmentRepository: AttachmentRepository
    private let auditService: AuditService
    private let userRepository: UserRepository?
    private let postingRepository: PostingRepository?
    private let assignmentRepository: AssignmentRepository?

    static let maxFileSizeBytes = 250 * 1024 * 1024 // 250 MB
    static let chunkingThreshold = 50 * 1024 * 1024 // 50 MB — large files deferred to FileChunkingTask

    init(dbPool: DatabasePool, attachmentRepository: AttachmentRepository, auditService: AuditService,
         userRepository: UserRepository? = nil, postingRepository: PostingRepository? = nil,
         assignmentRepository: AssignmentRepository? = nil) {
        self.dbPool = dbPool
        self.attachmentRepository = attachmentRepository
        self.auditService = auditService
        self.userRepository = userRepository
        self.postingRepository = postingRepository
        self.assignmentRepository = assignmentRepository
    }

    /// Verifies actor is a participant on the posting (creator, assigned tech, or admin/coordinator).
    private func requireUploadAccess(actorId: UUID, postingId: UUID?) async throws {
        guard let postingId else { return } // No posting context = general upload
        if let userRepo = userRepository, let actor = try await userRepo.findById(actorId) {
            if actor.role == .admin || actor.role == .coordinator { return }
        }
        if let pr = postingRepository, let posting = try await pr.findById(postingId) {
            if posting.createdBy == actorId { return }
        }
        if let ar = assignmentRepository {
            let assignments = try await ar.findByPosting(postingId)
            if assignments.contains(where: { $0.technicianId == actorId && $0.status == .accepted }) { return }
        }
        ForgeLogger.attachments.warning("Upload denied: actor \(actorId, privacy: .public) is not an accepted participant on posting \(postingId, privacy: .public)")
        throw AttachmentError.notAuthorized
    }

    /// Full upload pipeline: validate, checksum, quota, compress, thumbnail, watermark, save.
    func upload(
        fileData: Data,
        fileName: String,
        postingId: UUID?,
        commentId: UUID?,
        taskId: UUID?,
        uploadedBy: UUID,
        watermarkEnabled: Bool = false,
        watermarkUsername: String? = nil
    ) async throws -> Attachment {
        // 0. Authorization: actor must be a posting participant
        ForgeLogger.attachments.info("Upload started: actor=\(uploadedBy, privacy: .public) file=\(fileName, privacy: .private) size=\(fileData.count, privacy: .public)B posting=\(postingId?.uuidString ?? "none", privacy: .public)")
        try await requireUploadAccess(actorId: uploadedBy, postingId: postingId)

        // 1. Validate magic bytes (ATT-01)
        guard let mimeType = MagicBytesValidator.detectMimeType(from: fileData) else {
            throw AttachmentError.invalidMagicBytes
        }

        // 2. Check file size ≤ 250 MB (ATT-02)
        guard fileData.count <= Self.maxFileSizeBytes else {
            throw AttachmentError.fileTooLarge(maxMB: 250)
        }

        // 3. Compute SHA-256 checksum (ATT-08)
        let checksum = HashValidator.sha256Hex(data: fileData)

        // Reject duplicate for same posting
        if let postingId {
            if let existing = try await attachmentRepository.findByChecksum(checksum, postingId: postingId) {
                throw AttachmentError.duplicateFile
            }
        }

        // 4. Check user quota (ATT-04)
        let withinQuota = try await FileQuotaManager.checkQuota(
            userId: uploadedBy, fileSizeBytes: fileData.count, dbPool: dbPool
        )
        guard withinQuota else {
            throw AttachmentError.quotaExceeded
        }

        // 5. Prepare file paths
        let fileManager = FileManager.default
        let documentsURL = try fileManager.url(for: .documentDirectory, in: .userDomainMask,
                                                appropriateFor: nil, create: true)
        let attachmentsDir = documentsURL.appendingPathComponent("attachments")
        if let postingId {
            let postingDir = attachmentsDir.appendingPathComponent(postingId.uuidString)
            try fileManager.createDirectory(at: postingDir, withIntermediateDirectories: true)
        } else {
            try fileManager.createDirectory(at: attachmentsDir, withIntermediateDirectories: true)
        }

        let fileId = UUID()
        let ext = fileExtension(for: mimeType)
        let baseDir = postingId != nil
            ? attachmentsDir.appendingPathComponent(postingId!.uuidString)
            : attachmentsDir

        var finalData = fileData
        var isCompressed = false
        var thumbnailPath: String?
        var originalEncryptedPath: String?

        // 6. If image: thumbnail inline; compression always deferred to ImageCompressionTask (ATT-03)
        // Compression is never run inline — even small images are queued for BG processing so
        // the upload call returns quickly and heavy CPU work does not block the foreground thread.
        if isImageType(mimeType) {
            if let thumbData = ThumbnailGenerator.generate(from: fileData) {
                let thumbURL = baseDir.appendingPathComponent("\(fileId.uuidString)_thumb.jpg")
                try thumbData.write(to: thumbURL)
                thumbnailPath = thumbURL.lastPathComponent
            }
        }

        // 7. Watermark (ATT-07)
        if watermarkEnabled, isImageType(mimeType), let username = watermarkUsername {
            // Encrypt original with AES-256-GCM before storing
            let encryptedData = try AttachmentEncryptor.encrypt(data: fileData, fileId: fileId)
            let origURL = baseDir.appendingPathComponent("\(fileId.uuidString)_original.enc")
            try encryptedData.write(to: origURL)
            originalEncryptedPath = origURL.lastPathComponent

            // Render watermarked preview as the main file
            if let watermarked = WatermarkRenderer.render(imageData: finalData, username: username) {
                finalData = watermarked
            }
        }

        // 8. Save file to disk (ATT-06)
        // Large files (> chunkingThreshold): write to temp, enqueue FileChunkingTask — the BG
        // task copies to fileURL in resumable chunks so the foreground call is not blocked.
        // Smaller files are written inline (a single small write is acceptable foreground work).
        let fileURL = baseDir.appendingPathComponent("\(fileId.uuidString).\(ext)")
        let savedInline: Bool
        if finalData.count > Self.chunkingThreshold {
            let tempURL = FileManager.default.temporaryDirectory
                .appendingPathComponent(UUID().uuidString + ".\(ext)")
            try finalData.write(to: tempURL)
            // FileChunkingTask owns cleanup of tempURL on successful copy
            FileChunkingTask.enqueue(sourceURL: tempURL, destinationURL: fileURL)
            savedInline = false
        } else {
            try finalData.write(to: fileURL)
            savedInline = true
        }

        // Enqueue compression for all images written to their final path.
        // Compression is never inline — ImageCompressionTask runs it during a background
        // BGProcessingTask window to avoid blocking the foreground thread.
        // Skip files handled by FileChunkingTask: fileURL does not exist yet, so we enqueue
        // compression only once the file is confirmed present (savedInline path).
        if isImageType(mimeType) && savedInline {
            // Use a distinct temp path so the compressor never reads and removes the same file.
            let compressionTempURL = fileURL.deletingLastPathComponent()
                .appendingPathComponent(".\(fileURL.lastPathComponent).tmp")
            ImageCompressionTask.enqueue(inputURL: fileURL, outputURL: compressionTempURL)
        }

        // 9. Create attachment record
        let attachment = Attachment(
            id: fileId,
            commentId: commentId,
            postingId: postingId,
            taskId: taskId,
            fileName: fileName,
            filePath: fileURL.lastPathComponent,
            fileSizeBytes: fileData.count,
            mimeType: mimeType,
            checksumSha256: checksum,
            thumbnailPath: thumbnailPath,
            isCompressed: isCompressed,
            originalEncryptedPath: originalEncryptedPath,
            uploadedBy: uploadedBy,
            createdAt: Date()
        )

        try await dbPool.write { [self] db in
            try attachmentRepository.insertInTransaction(db: db, attachment)

            try auditService.record(
                db: db, actorId: uploadedBy, action: "FILE_UPLOADED",
                entityType: "Attachment", entityId: attachment.id,
                afterData: "{\"fileName\":\"\(fileName)\",\"mimeType\":\"\(mimeType.rawValue)\",\"size\":\(fileData.count)}"
            )
        }

        ForgeLogger.attachments.info("Upload completed: attachmentId=\(attachment.id, privacy: .public) mimeType=\(mimeType.rawValue, privacy: .public) compressed=\(isCompressed, privacy: .public) watermarked=\(originalEncryptedPath != nil, privacy: .public)")
        return attachment
    }

    func listAttachments(postingId: UUID, actorId: UUID) async throws -> [Attachment] {
        try await requireUploadAccess(actorId: actorId, postingId: postingId)
        return try await attachmentRepository.findByPosting(postingId)
    }

    func listAttachments(commentId: UUID, postingId: UUID, actorId: UUID) async throws -> [Attachment] {
        try await requireUploadAccess(actorId: actorId, postingId: postingId)
        return try await attachmentRepository.findByComment(commentId)
    }

    func getAttachment(id: UUID, actorId: UUID) async throws -> Attachment {
        guard let attachment = try await attachmentRepository.findById(id) else {
            throw AttachmentError.fileNotFound
        }
        try await requireUploadAccess(actorId: actorId, postingId: attachment.postingId)
        return attachment
    }

    func getQuotaUsage(userId: UUID) async throws -> (used: Int, quota: Int) {
        try await FileQuotaManager.getUsage(userId: userId, dbPool: dbPool)
    }

    /// Returns the decrypted original for a watermarked attachment. Requires admin role. Audited.
    func downloadOriginal(id: UUID, actorId: UUID) async throws -> Data {
        guard let attachment = try await attachmentRepository.findById(id) else {
            throw AttachmentError.fileNotFound
        }
        guard let userRepo = userRepository,
              let actor = try await userRepo.findById(actorId),
              actor.role == .admin else {
            throw AttachmentError.notAuthorized
        }
        guard let origPath = attachment.originalEncryptedPath else {
            throw AttachmentError.fileNotFound
        }
        let fileManager = FileManager.default
        let documentsURL = try fileManager.url(
            for: .documentDirectory, in: .userDomainMask, appropriateFor: nil, create: false
        )
        let attachmentsDir = documentsURL.appendingPathComponent("attachments")
        let fullURL: URL
        if let postingId = attachment.postingId {
            fullURL = attachmentsDir
                .appendingPathComponent(postingId.uuidString)
                .appendingPathComponent(origPath)
        } else {
            fullURL = attachmentsDir.appendingPathComponent(origPath)
        }
        let encryptedData = try Data(contentsOf: fullURL)
        let plainData = try AttachmentEncryptor.decrypt(combinedData: encryptedData, fileId: attachment.id)
        try await dbPool.write { [self] db in
            try auditService.record(
                db: db, actorId: actorId, action: "ORIGINAL_ACCESSED",
                entityType: "Attachment", entityId: attachment.id,
                afterData: "{\"fileName\":\"\(attachment.fileName)\"}"
            )
        }
        return plainData
    }

    /// Returns attachment file data for export. Enforces participant access and audits. (ATT-DL)
    func downloadAttachment(id: UUID, actorId: UUID) async throws -> Data {
        let attachment = try await getAttachment(id: id, actorId: actorId)
        let fileManager = FileManager.default
        let documentsURL = try fileManager.url(
            for: .documentDirectory, in: .userDomainMask, appropriateFor: nil, create: false
        )
        let attachmentsDir = documentsURL.appendingPathComponent("attachments")
        let fullURL: URL
        if let postingId = attachment.postingId {
            fullURL = attachmentsDir
                .appendingPathComponent(postingId.uuidString)
                .appendingPathComponent(attachment.filePath)
        } else {
            fullURL = attachmentsDir.appendingPathComponent(attachment.filePath)
        }
        let data = try Data(contentsOf: fullURL)
        try await dbPool.write { [self] db in
            try auditService.record(
                db: db, actorId: actorId, action: "FILE_DOWNLOADED",
                entityType: "Attachment", entityId: attachment.id,
                afterData: "{\"fileName\":\"\(attachment.fileName)\"}"
            )
        }
        return data
    }

    // MARK: - Private

    private func isImageType(_ mimeType: AttachmentMimeType) -> Bool {
        [.jpg, .png, .heic].contains(mimeType)
    }

    private func fileExtension(for mimeType: AttachmentMimeType) -> String {
        switch mimeType {
        case .pdf: return "pdf"
        case .jpg: return "jpg"
        case .png: return "png"
        case .heic: return "heic"
        case .mov: return "mov"
        }
    }
}
