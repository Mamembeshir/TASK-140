import SwiftUI

struct CommentFormView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var commentBody = ""
    @State private var errorMessage: String?
    @State private var showingAttachmentPicker = false
    @State private var createdCommentId: UUID?
    @State private var commentPosted = false

    let postingId: UUID
    let parentCommentId: UUID?
    let commentService: CommentService
    let appState: AppState
    var attachmentService: AttachmentService? = nil
    var watermarkEnabled: Bool = false

    var body: some View {
        NavigationStack {
            Form {
                if !commentPosted {
                    Section("Comment") {
                        TextField("Write your comment...", text: $commentBody, axis: .vertical)
                            .lineLimit(3...10)
                    }
                } else {
                    Section {
                        Label("Comment posted successfully", systemImage: "checkmark.circle.fill")
                            .foregroundStyle(.green)
                    }

                    if attachmentService != nil {
                        Section("Add Attachment to Comment") {
                            Button {
                                showingAttachmentPicker = true
                            } label: {
                                Label("Attach File (Photos or Files)", systemImage: "paperclip")
                            }
                        }

                        Section {
                            Button("Done") { dismiss() }
                                .fontWeight(.semibold)
                        }
                    }
                }

                if let error = errorMessage {
                    Section {
                        Text(error).font(.caption).foregroundStyle(.red)
                    }
                }
            }
            .navigationTitle(parentCommentId != nil ? "Reply" : "New Comment")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(commentPosted ? "Close" : "Cancel") { dismiss() }
                }
                if !commentPosted {
                    ToolbarItem(placement: .confirmationAction) {
                        Button("Post") {
                            Task { await postComment() }
                        }
                        .disabled(commentBody.trimmingCharacters(in: .whitespaces).isEmpty)
                        .fontWeight(.bold)
                    }
                }
            }
            .sheet(isPresented: $showingAttachmentPicker) {
                if let attachmentService, let commentId = createdCommentId {
                    AttachmentUploadView(
                        postingId: postingId,
                        commentId: commentId,
                        attachmentService: attachmentService,
                        appState: appState,
                        watermarkEnabled: watermarkEnabled
                    )
                }
            }
        }
    }

    private func postComment() async {
        guard let authorId = appState.currentUserId else { return }
        do {
            let comment = try await commentService.create(
                postingId: postingId,
                authorId: authorId,
                body: commentBody,
                parentCommentId: parentCommentId
            )
            createdCommentId = comment.id
            commentPosted = true

            // If no attachment service, dismiss immediately
            if attachmentService == nil {
                dismiss()
            }
            // Otherwise, stay open so user can attach files
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}
