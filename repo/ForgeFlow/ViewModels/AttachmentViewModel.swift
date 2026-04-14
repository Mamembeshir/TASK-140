import Foundation
import SwiftUI

@Observable
final class AttachmentViewModel {
    var attachments: [Attachment] = []
    var isLoading = false
    var isUploading = false
    var errorMessage: String?
    var quotaUsed: Int = 0
    var quotaTotal: Int = 2_147_483_648

    let postingId: UUID
    private let attachmentService: AttachmentService
    private let appState: AppState

    init(postingId: UUID, attachmentService: AttachmentService, appState: AppState) {
        self.postingId = postingId
        self.attachmentService = attachmentService
        self.appState = appState
    }

    var quotaPercentage: Double {
        guard quotaTotal > 0 else { return 0 }
        return Double(quotaUsed) / Double(quotaTotal)
    }

    var quotaDisplay: String {
        let usedMB = Double(quotaUsed) / (1024 * 1024)
        let totalMB = Double(quotaTotal) / (1024 * 1024)
        return String(format: "%.1f MB / %.0f MB", usedMB, totalMB)
    }

    func loadAttachments() async {
        guard let actorId = appState.currentUserId else { return }
        isLoading = true
        do {
            attachments = try await attachmentService.listAttachments(postingId: postingId, actorId: actorId)
            let usage = try await attachmentService.getQuotaUsage(userId: actorId)
            quotaUsed = usage.used
            quotaTotal = usage.quota
        } catch {
            errorMessage = error.localizedDescription
        }
        isLoading = false
    }

    func upload(data: Data, fileName: String, watermarkEnabled: Bool = false) async {
        guard let userId = appState.currentUserId else { return }
        isUploading = true
        errorMessage = nil

        do {
            _ = try await attachmentService.upload(
                fileData: data,
                fileName: fileName,
                postingId: postingId,
                commentId: nil,
                taskId: nil,
                uploadedBy: userId,
                watermarkEnabled: watermarkEnabled,
                watermarkUsername: watermarkEnabled ? appState.currentUsername : nil
            )
            await loadAttachments()
        } catch {
            errorMessage = error.localizedDescription
        }
        isUploading = false
    }
}
