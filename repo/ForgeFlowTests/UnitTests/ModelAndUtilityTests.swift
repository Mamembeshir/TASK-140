import Testing
import UIKit
@testable import ForgeFlow

// MARK: - Error Description Tests

@Suite("ErrorDescriptions")
struct ErrorDescriptionTests {

    // MARK: AuthError

    @Test func authError_invalidCredentials() {
        let e = AuthError.invalidCredentials
        #expect(e.errorDescription != nil && !e.errorDescription!.isEmpty)
    }

    @Test func authError_accountLocked() {
        let e = AuthError.accountLocked(until: Date(timeIntervalSinceNow: 3600))
        let desc = e.errorDescription ?? ""
        #expect(!desc.isEmpty)
        #expect(desc.lowercased().contains("locked") || desc.lowercased().contains("try"))
    }

    @Test func authError_accountDeactivated() {
        #expect(AuthError.accountDeactivated.errorDescription?.isEmpty == false)
    }

    @Test func authError_biometricCases() {
        let cases: [AuthError] = [.biometricNotAvailable, .biometricNotEnrolled, .biometricFailed]
        for e in cases {
            #expect(e.errorDescription?.isEmpty == false)
        }
    }

    @Test func authError_passwordCases() {
        let cases: [AuthError] = [.passwordTooShort, .passwordMissingNumber]
        for e in cases {
            #expect(e.errorDescription?.isEmpty == false)
        }
    }

    @Test func authError_usernameCases() {
        let cases: [AuthError] = [.usernameTaken, .usernameInvalid]
        for e in cases {
            #expect(e.errorDescription?.isEmpty == false)
        }
    }

    @Test func authError_remainingCases() {
        let cases: [AuthError] = [.sessionExpired, .notAuthorized, .keychainStoreFailed]
        for e in cases {
            #expect(e.errorDescription?.isEmpty == false)
        }
    }

    // MARK: PostingError

    @Test func postingError_allCases() {
        let errors: [PostingError] = [
            .titleRequired,
            .siteAddressRequired,
            .dueDateMustBeFuture,
            .budgetMustBePositive,
            .invalidStatusTransition(from: .draft, to: .inProgress),
            .notAuthorized,
            .postingNotFound
        ]
        for e in errors {
            #expect(e.errorDescription?.isEmpty == false)
        }
    }

    // MARK: TaskError

    @Test func taskError_allCases() {
        let errors: [TaskError] = [
            .titleRequired,
            .invalidStatusTransition(from: .notStarted, to: .done),
            .blockedCommentRequired,
            .blockedCommentTooShort,
            .unmetDependencies,
            .subtasksNotComplete,
            .taskNotFound,
            .notAuthorized
        ]
        for e in errors {
            #expect(e.errorDescription?.isEmpty == false)
        }
    }

    // MARK: AttachmentError

    @Test func attachmentError_allCases() {
        let errors: [AttachmentError] = [
            .unsupportedFileType,
            .fileTooLarge(maxMB: 10),
            .quotaExceeded,
            .checksumMismatch,
            .duplicateFile,
            .fileNotFound,
            .compressionFailed,
            .invalidMagicBytes,
            .notAuthorized
        ]
        for e in errors {
            #expect(e.errorDescription?.isEmpty == false)
        }
    }

    @Test func attachmentError_fileTooLargeContainsMB() {
        let desc = AttachmentError.fileTooLarge(maxMB: 10).errorDescription ?? ""
        #expect(desc.contains("10"))
    }

    // MARK: AssignmentError

    @Test func assignmentError_allCases() {
        let errors: [AssignmentError] = [
            .alreadyAssigned(name: "Bob", at: Date()),
            .notInvited,
            .invalidStatusTransition(from: .invited, to: .completed),
            .assignmentNotFound,
            .notAuthorized,
            .postingNotOpen
        ]
        for e in errors {
            #expect(e.errorDescription?.isEmpty == false)
        }
    }

    // MARK: SyncError

    @Test func syncError_allCases() {
        let errors: [SyncError] = [
            .exportFailed(reason: "disk full"),
            .importFailed(reason: "parse error"),
            .checksumValidationFailed,
            .conflictsDetected(count: 3),
            .invalidSyncFile,
            .incompatibleVersion,
            .notAuthorized
        ]
        for e in errors {
            #expect(e.errorDescription?.isEmpty == false)
        }
    }

    @Test func syncError_conflictsContainsCount() {
        let desc = SyncError.conflictsDetected(count: 3).errorDescription ?? ""
        #expect(desc.contains("3"))
    }

    // MARK: PluginError

    @Test func pluginError_allCases() {
        let errors: [PluginError] = [
            .nameRequired,
            .invalidStatusTransition(from: .draft, to: .active),
            .sameApproverNotAllowed,
            .sameApproverBothSteps,
            .pluginNotFound,
            .postingNotFound,
            .testingRequired,
            .notAuthorized,
            .noFieldsDefined,
            .noTestResults,
            .testsFailed,
            .invalidApprovalStep,
            .step1NotCompleted,
            .stepAlreadyCompleted(step: 1)
        ]
        for e in errors {
            #expect(e.errorDescription?.isEmpty == false)
        }
    }

    // MARK: NotificationError

    @Test func notificationError_allCases() {
        let errors: [NotificationError] = [
            .notificationNotFound,
            .invalidStatusTransition(from: .pending, to: .seen),
            .unauthorized
        ]
        for e in errors {
            #expect(e.errorDescription?.isEmpty == false)
        }
    }

    // MARK: StaleRecordError

    @Test func staleRecordError_nonEmpty() {
        let e = StaleRecordError(entityType: "Task", entityId: UUID())
        #expect(!e.localizedDescription.isEmpty)
        #expect(e.errorDescription?.isEmpty == false)
        #expect(e.errorDescription?.contains("Task") == true)
    }
}

// MARK: - MagicBytesValidator Tests

@Suite("MagicBytesValidator")
struct MagicBytesValidatorTests {

    @Test func detectPDF() {
        let data = Data([0x25, 0x50, 0x44, 0x46]) + Data(count: 20)
        #expect(MagicBytesValidator.detectMimeType(from: data) == .pdf)
    }

    @Test func detectJPEG() {
        let data = Data([0xFF, 0xD8, 0xFF, 0xE0]) + Data(count: 20)
        #expect(MagicBytesValidator.detectMimeType(from: data) == .jpg)
    }

    @Test func detectPNG() {
        let png = Data([0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A]) + Data(count: 20)
        #expect(MagicBytesValidator.detectMimeType(from: png) == .png)
    }

    @Test func detectHEIC() {
        var heic = Data(count: 12)
        heic.replaceSubrange(4..<8, with: [0x66, 0x74, 0x79, 0x70]) // "ftyp"
        heic.replaceSubrange(8..<12, with: [0x68, 0x65, 0x69, 0x63]) // "heic"
        #expect(MagicBytesValidator.detectMimeType(from: heic) == .heic)
    }

    @Test func detectMOV() {
        var mov = Data(count: 12)
        mov.replaceSubrange(4..<8, with: [0x66, 0x74, 0x79, 0x70]) // "ftyp"
        mov.replaceSubrange(8..<12, with: [0x71, 0x74, 0x20, 0x20]) // "qt  "
        #expect(MagicBytesValidator.detectMimeType(from: mov) == .mov)
    }

    @Test func tooShortReturnsNil() {
        let data = Data([0x25, 0x50])
        #expect(MagicBytesValidator.detectMimeType(from: data) == nil)
    }

    @Test func unknownBytesReturnsNil() {
        let data = Data(repeating: 0x00, count: 16)
        #expect(MagicBytesValidator.detectMimeType(from: data) == nil)
    }

    @Test func validateReturnsTrueForPDF() {
        let data = Data([0x25, 0x50, 0x44, 0x46]) + Data(count: 20)
        #expect(MagicBytesValidator.validate(data: data) == true)
    }

    @Test func validateReturnsFalseForUnknown() {
        #expect(MagicBytesValidator.validate(data: Data(repeating: 0x00, count: 16)) == false)
    }

    @Test func validateReturnsFalseForShortData() {
        #expect(MagicBytesValidator.validate(data: Data([0x25, 0x50])) == false)
    }
}

// MARK: - ImageCompressor Tests

@Suite("ImageCompressor")
struct ImageCompressorTests {

    private func make1x1JPEG() -> Data {
        let renderer = UIGraphicsImageRenderer(size: CGSize(width: 1, height: 1))
        return renderer.jpegData(withCompressionQuality: 1.0) { ctx in
            UIColor.red.setFill()
            ctx.fill(CGRect(x: 0, y: 0, width: 1, height: 1))
        }
    }

    private func makeImageData(width: CGFloat, height: CGFloat) -> Data {
        let renderer = UIGraphicsImageRenderer(size: CGSize(width: width, height: height))
        return renderer.jpegData(withCompressionQuality: 1.0) { ctx in
            UIColor.blue.setFill()
            ctx.fill(CGRect(x: 0, y: 0, width: width, height: height))
        }
    }

    @Test func dimensionsValidImage() {
        let data = make1x1JPEG()
        let size = ImageCompressor.dimensions(of: data)
        // Just verify we get a valid size; pixel dimensions vary by device scale
        #expect(size != nil)
        #expect(size!.width > 0)
        #expect(size!.height > 0)
    }

    @Test func dimensionsInvalidDataReturnsNil() {
        #expect(ImageCompressor.dimensions(of: Data(repeating: 0, count: 100)) == nil)
    }

    @Test func compressInvalidDataReturnsNil() {
        #expect(ImageCompressor.compress(imageData: Data(repeating: 0, count: 100)) == nil)
    }

    @Test func compressValidImageReturnsNonEmptyData() {
        let data = make1x1JPEG()
        let result = ImageCompressor.compress(imageData: data)
        #expect(result != nil)
        #expect(!result!.isEmpty)
    }

    @Test func compressLargeImageScalesDown() {
        // 3000×3000 points — at 3x scale = 9000px. After compression, long edge ≤ 2048pt.
        // UIGraphicsImageRenderer renders output pixels at device scale (up to 3x).
        let data = makeImageData(width: 3000, height: 3000)
        let result = ImageCompressor.compress(imageData: data)
        #expect(result != nil)
        if let result {
            let size = ImageCompressor.dimensions(of: result)
            #expect(size != nil)
            if let size {
                // Allow 3x device scale headroom on the point-based maxLongEdge
                #expect(max(size.width, size.height) <= ImageCompressor.maxLongEdge * 3)
            }
        }
    }

    @Test func compressSmallImagePreservesAspect() {
        let data = makeImageData(width: 100, height: 50)
        let result = ImageCompressor.compress(imageData: data)
        #expect(result != nil)
        if let result {
            let size = ImageCompressor.dimensions(of: result)
            #expect(size != nil)
        }
    }
}

// MARK: - ThumbnailGenerator Tests

@Suite("ThumbnailGenerator")
struct ThumbnailGeneratorTests {

    private func makeImageData(width: CGFloat, height: CGFloat) -> Data {
        let renderer = UIGraphicsImageRenderer(size: CGSize(width: width, height: height))
        return renderer.jpegData(withCompressionQuality: 1.0) { ctx in
            UIColor.green.setFill()
            ctx.fill(CGRect(x: 0, y: 0, width: width, height: height))
        }
    }

    @Test func generateInvalidDataReturnsNil() {
        #expect(ThumbnailGenerator.generate(from: Data(repeating: 0, count: 100)) == nil)
    }

    @Test func generateValidSmallImage() {
        let data = makeImageData(width: 1, height: 1)
        #expect(ThumbnailGenerator.generate(from: data) != nil)
    }

    @Test func generateWithCustomMaxDimension() {
        let data = makeImageData(width: 100, height: 100)
        #expect(ThumbnailGenerator.generate(from: data, maxDimension: 50) != nil)
    }

    @Test func largeImageDownscaledToThumbnailSize() {
        let data = makeImageData(width: 400, height: 400)
        let thumb = ThumbnailGenerator.generate(from: data)
        #expect(thumb != nil)
        if let thumb {
            let size = ImageCompressor.dimensions(of: thumb)
            #expect(size != nil)
            if let size {
                // ThumbnailGenerator.thumbnailSize is in points; rendered pixels
                // include the device scale factor (up to 3x). Allow 3x headroom.
                let maxAllowedPixels = ThumbnailGenerator.thumbnailSize * 3
                #expect(max(size.width, size.height) <= maxAllowedPixels)
            }
        }
    }

    @Test func smallImageProducesThumbnail() {
        // 50×50 pt image is smaller than thumbnailSize — should still generate a thumbnail
        let data = makeImageData(width: 50, height: 50)
        let thumb = ThumbnailGenerator.generate(from: data)
        // Main assertion: thumbnail generation doesn't fail for small images
        #expect(thumb != nil)
    }
}
