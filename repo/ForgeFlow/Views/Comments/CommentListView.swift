import SwiftUI

struct CommentListView: View {
    @State private var viewModel: CommentListViewModel

    let watermarkEnabled: Bool

    init(postingId: UUID, commentService: CommentService,
         attachmentService: AttachmentService? = nil, appState: AppState,
         watermarkEnabled: Bool = false) {
        self.watermarkEnabled = watermarkEnabled
        _viewModel = State(initialValue: CommentListViewModel(
            postingId: postingId, commentService: commentService,
            attachmentService: attachmentService, appState: appState
        ))
    }

    var body: some View {
        VStack(spacing: 0) {
            if viewModel.threads.isEmpty && !viewModel.isLoading {
                Spacer()
                VStack(spacing: 8) {
                    Image(systemName: "bubble.left.and.bubble.right")
                        .font(.system(size: 32))
                        .foregroundStyle(Color("TextTertiary"))
                    Text("No comments yet")
                        .font(.subheadline)
                        .foregroundStyle(Color("TextSecondary"))
                }
                Spacer()
            } else {
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 12) {
                        ForEach(viewModel.threads) { thread in
                            CommentThreadView(
                                thread: thread,
                                depth: 0,
                                inlineImages: viewModel.inlineImages
                            ) { replyToId in
                                viewModel.replyingTo = replyToId
                            }
                        }
                    }
                    .padding()
                }
            }

            Divider()

            // Comment input
            commentInput
        }
        .navigationTitle("Comments")
        .toolbar {
            if viewModel.attachmentService != nil {
                ToolbarItem(placement: .primaryAction) {
                    Button {
                        viewModel.showCommentForm = true
                    } label: {
                        Image(systemName: "square.and.pencil")
                    }
                    .accessibilityLabel("New Comment with Attachment")
                }
            }
        }
        .sheet(isPresented: $viewModel.showCommentForm) {
            CommentFormView(
                postingId: viewModel.postingId,
                parentCommentId: nil,
                commentService: viewModel.commentService,
                appState: viewModel.appState,
                attachmentService: viewModel.attachmentService,
                watermarkEnabled: watermarkEnabled
            )
        }
        .task { await viewModel.loadComments() }
    }

    private var commentInput: some View {
        VStack(spacing: 8) {
            if let replyingTo = viewModel.replyingTo {
                HStack {
                    Text("Replying to comment...")
                        .font(.caption)
                        .foregroundStyle(Color("TextSecondary"))
                    Spacer()
                    Button("Cancel") { viewModel.replyingTo = nil }
                        .font(.caption)
                }
                .padding(.horizontal)
            }

            HStack(spacing: 12) {
                TextField("Add a comment...", text: $viewModel.newCommentBody, axis: .vertical)
                    .lineLimit(1...4)
                    .textFieldStyle(.roundedBorder)

                Button {
                    Task { await viewModel.addComment() }
                } label: {
                    Image(systemName: "paperplane.fill")
                        .foregroundStyle(Color("ForgeBlue"))
                }
                .disabled(viewModel.newCommentBody.trimmingCharacters(in: .whitespaces).isEmpty)
            }
            .padding(.horizontal)
            .padding(.vertical, 8)
        }
        .background(Color("SurfaceElevated"))
    }
}

// MARK: - Comment Thread View (Recursive)

private struct CommentThreadView: View {
    let thread: ThreadedComment
    let depth: Int
    let inlineImages: [UUID: [UIImage]]
    let onReply: (UUID) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            // Comment bubble
            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    Text(thread.comment.authorId.uuidString.prefix(8))
                        .font(.caption)
                        .fontWeight(.semibold)
                        .foregroundStyle(Color("ForgeBlue"))

                    Spacer()

                    Text(DateFormatters.relative.localizedString(for: thread.comment.createdAt, relativeTo: Date()))
                        .font(.caption2)
                        .foregroundStyle(Color("TextTertiary"))
                }

                Text(thread.comment.body)
                    .font(.subheadline)
                    .foregroundStyle(Color("TextPrimary"))

                // Inline images
                if let images = inlineImages[thread.comment.id], !images.isEmpty {
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 8) {
                            ForEach(images.indices, id: \.self) { i in
                                Image(uiImage: images[i])
                                    .resizable()
                                    .scaledToFill()
                                    .frame(width: 120, height: 80)
                                    .clipShape(RoundedRectangle(cornerRadius: 6))
                            }
                        }
                    }
                }

                Button {
                    onReply(thread.comment.id)
                } label: {
                    Text("Reply")
                        .font(.caption)
                        .foregroundStyle(Color("TextSecondary"))
                }
            }
            .padding(12)
            .background(Color("SurfaceElevated"), in: RoundedRectangle(cornerRadius: 10))
            .shadow(color: .black.opacity(0.04), radius: 2, y: 1)

            // Replies (indented)
            if !thread.replies.isEmpty {
                ForEach(thread.replies) { reply in
                    CommentThreadView(
                        thread: reply,
                        depth: depth + 1,
                        inlineImages: inlineImages,
                        onReply: onReply
                    )
                    .padding(.leading, 24)
                }
            }
        }
    }
}
