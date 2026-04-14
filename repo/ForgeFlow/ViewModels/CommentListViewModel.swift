import Foundation
import SwiftUI

@Observable
final class CommentListViewModel {
    var threads: [ThreadedComment] = []
    var inlineImages: [UUID: [UIImage]] = [:]  // commentId → images
    var isLoading = false
    var errorMessage: String?

    // Comment form
    var newCommentBody = ""
    var replyingTo: UUID?
    var showCommentForm = false

    let postingId: UUID
    let commentService: CommentService
    let attachmentService: AttachmentService?
    let appState: AppState

    init(postingId: UUID, commentService: CommentService,
         attachmentService: AttachmentService? = nil, appState: AppState) {
        self.postingId = postingId
        self.commentService = commentService
        self.attachmentService = attachmentService
        self.appState = appState
    }

    func loadComments() async {
        guard let actorId = appState.currentUserId else { return }
        isLoading = true
        do {
            threads = try await commentService.threadedComments(postingId: postingId, actorId: actorId)
            await loadInlineImages(from: threads)
        } catch {
            errorMessage = error.localizedDescription
        }
        isLoading = false
    }

    func addComment() async {
        guard let authorId = appState.currentUserId else { return }
        guard !newCommentBody.trimmingCharacters(in: .whitespaces).isEmpty else { return }

        do {
            _ = try await commentService.create(
                postingId: postingId,
                authorId: authorId,
                body: newCommentBody,
                parentCommentId: replyingTo
            )
            newCommentBody = ""
            replyingTo = nil
            await loadComments()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    // MARK: - Inline Images

    private func loadInlineImages(from threads: [ThreadedComment]) async {
        guard let attachmentService, let actorId = appState.currentUserId else { return }
        let allComments = flattenThreads(threads)
        var result: [UUID: [UIImage]] = [:]
        for comment in allComments {
            guard let attachments = try? await attachmentService.listAttachments(commentId: comment.id, postingId: postingId, actorId: actorId) else { continue }
            let images = attachments.compactMap { attachment -> UIImage? in
                guard [AttachmentMimeType.jpg, .png, .heic].contains(attachment.mimeType) else { return nil }
                return loadImage(from: attachment)
            }
            if !images.isEmpty {
                result[comment.id] = images
            }
        }
        inlineImages = result
    }

    private func flattenThreads(_ threads: [ThreadedComment]) -> [Comment] {
        threads.flatMap { [$0.comment] + flattenThreads($0.replies) }
    }

    private func loadImage(from attachment: Attachment) -> UIImage? {
        guard let docs = try? FileManager.default.url(
            for: .documentDirectory, in: .userDomainMask, appropriateFor: nil, create: false
        ) else { return nil }
        let attachmentsDir = docs.appendingPathComponent("attachments")
        let fullURL: URL
        if let postingId = attachment.postingId {
            fullURL = attachmentsDir
                .appendingPathComponent(postingId.uuidString)
                .appendingPathComponent(attachment.filePath)
        } else {
            fullURL = attachmentsDir.appendingPathComponent(attachment.filePath)
        }
        guard let data = try? Data(contentsOf: fullURL) else { return nil }
        return UIImage(data: data)
    }
}
