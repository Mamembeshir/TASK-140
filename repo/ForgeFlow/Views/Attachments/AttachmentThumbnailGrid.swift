import SwiftUI

struct AttachmentThumbnailGrid: View {
    @State private var viewModel: AttachmentViewModel
    @State private var selectedAttachment: Attachment?
    @State private var showingUpload = false
    let postingId: UUID
    let attachmentService: AttachmentService
    let watermarkEnabled: Bool
    @Environment(AppState.self) private var appState

    init(postingId: UUID, attachmentService: AttachmentService, appState: AppState,
         watermarkEnabled: Bool = false) {
        self.postingId = postingId
        self.attachmentService = attachmentService
        self.watermarkEnabled = watermarkEnabled
        _viewModel = State(initialValue: AttachmentViewModel(
            postingId: postingId, attachmentService: attachmentService, appState: appState
        ))
    }

    var body: some View {
        VStack(spacing: 16) {
            // Quota indicator
            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    Text("Storage")
                        .font(.caption)
                        .foregroundStyle(Color("TextSecondary"))
                    Spacer()
                    Text(viewModel.quotaDisplay)
                        .font(.caption)
                        .foregroundStyle(Color("TextSecondary"))
                }
                ProgressView(value: min(viewModel.quotaPercentage, 1.0))
                    .tint(viewModel.quotaPercentage > 0.9 ? Color("Danger") : Color("ForgeBlue"))
            }
            .padding(.horizontal)

            if viewModel.attachments.isEmpty && !viewModel.isLoading {
                Spacer()
                EmptyStateView(
                    icon: "paperclip",
                    heading: "No Attachments",
                    description: "Upload files to this posting."
                )
                Spacer()
            } else {
                ScrollView {
                    LazyVGrid(
                        columns: [GridItem(.adaptive(minimum: 100), spacing: 12)],
                        spacing: 12
                    ) {
                        ForEach(viewModel.attachments) { attachment in
                            AttachmentThumbnailCell(attachment: attachment)
                                .onTapGesture { selectedAttachment = attachment }
                        }
                    }
                    .padding()
                }
            }

            if viewModel.isUploading {
                ProgressView("Uploading...")
                    .padding()
            }
        }
        .navigationTitle("Attachments")
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button { showingUpload = true } label: {
                    Image(systemName: "plus")
                }
                .accessibilityLabel("Upload Attachment")
            }
        }
        .task { await viewModel.loadAttachments() }
        .sheet(item: $selectedAttachment) { attachment in
            AttachmentPreviewSheet(attachment: attachment, attachmentService: attachmentService)
        }
        .sheet(isPresented: $showingUpload) {
            AttachmentUploadView(
                postingId: postingId,
                attachmentService: attachmentService,
                appState: appState,
                watermarkEnabled: watermarkEnabled
            )
        }
        .alert("Error", isPresented: .constant(viewModel.errorMessage != nil)) {
            Button("OK") { viewModel.errorMessage = nil }
        } message: {
            Text(viewModel.errorMessage ?? "")
        }
    }
}

// MARK: - Thumbnail Cell

private struct AttachmentThumbnailCell: View {
    let attachment: Attachment

    var body: some View {
        VStack(spacing: 4) {
            ZStack {
                RoundedRectangle(cornerRadius: 8)
                    .fill(Color("SurfaceSunken"))
                    .frame(height: 80)

                if let uiImage = thumbnailImage {
                    Image(uiImage: uiImage)
                        .resizable()
                        .scaledToFill()
                        .frame(height: 80)
                        .clipShape(RoundedRectangle(cornerRadius: 8))
                } else {
                    Image(systemName: iconName)
                        .font(.title2)
                        .foregroundStyle(Color("TextTertiary"))
                }
            }

            Text(attachment.fileName)
                .font(.caption2)
                .foregroundStyle(Color("TextSecondary"))
                .lineLimit(1)
                .truncationMode(.middle)
        }
    }

    private var thumbnailImage: UIImage? {
        guard let thumbPath = attachment.thumbnailPath else { return nil }
        guard let docs = try? FileManager.default.url(
            for: .documentDirectory, in: .userDomainMask, appropriateFor: nil, create: false
        ) else { return nil }
        let attachmentsDir = docs.appendingPathComponent("attachments")
        let fullURL: URL
        if let postingId = attachment.postingId {
            fullURL = attachmentsDir
                .appendingPathComponent(postingId.uuidString)
                .appendingPathComponent(thumbPath)
        } else {
            fullURL = attachmentsDir.appendingPathComponent(thumbPath)
        }
        guard let data = try? Data(contentsOf: fullURL) else { return nil }
        return UIImage(data: data)
    }

    private var iconName: String {
        switch attachment.mimeType {
        case .pdf: return "doc.fill"
        case .jpg, .png, .heic: return "photo.fill"
        case .mov: return "video.fill"
        }
    }
}

// MARK: - Preview Sheet

private struct AttachmentPreviewSheet: View {
    let attachment: Attachment
    let attachmentService: AttachmentService
    @Environment(\.dismiss) private var dismiss
    @Environment(AppState.self) private var appState
    @State private var previewImage: UIImage?
    @State private var originalImage: UIImage?
    @State private var showingOriginal = false
    @State private var isLoadingOriginal = false
    @State private var isDownloading = false
    @State private var exportURL: URL?
    @State private var errorMessage: String?

    var body: some View {
        NavigationStack {
            VStack(spacing: 16) {
                if showingOriginal, let img = originalImage {
                    Image(uiImage: img)
                        .resizable()
                        .scaledToFit()
                        .clipShape(RoundedRectangle(cornerRadius: 8))
                        .padding(.horizontal)
                    Text("Original (decrypted)")
                        .font(.caption)
                        .foregroundStyle(.green)
                } else if let preview = previewImage {
                    Image(uiImage: preview)
                        .resizable()
                        .scaledToFit()
                        .clipShape(RoundedRectangle(cornerRadius: 8))
                        .padding(.horizontal)
                    if attachment.originalEncryptedPath != nil {
                        Text("Watermarked preview")
                            .font(.caption)
                            .foregroundStyle(Color("TextTertiary"))
                    }
                } else {
                    Image(systemName: iconName)
                        .font(.system(size: 64))
                        .foregroundStyle(Color("TextTertiary"))
                }

                Text(attachment.fileName)
                    .font(.headline)
                    .foregroundStyle(Color("TextPrimary"))

                LabeledContent("Type") { Text(attachment.mimeType.rawValue) }
                LabeledContent("Size") {
                    let mb = Double(attachment.fileSizeBytes) / (1024 * 1024)
                    Text(String(format: "%.2f MB", mb))
                }
                LabeledContent("Checksum") {
                    Text(String(attachment.checksumSha256.prefix(16)) + "...")
                        .font(.caption)
                }

                if attachment.originalEncryptedPath != nil {
                    HStack(spacing: 8) {
                        Image(systemName: "lock.shield.fill")
                            .foregroundStyle(Color("Warning"))
                        Text("Watermarked — original encrypted")
                            .font(.caption)
                            .foregroundStyle(Color("TextSecondary"))
                    }

                    if appState.currentUserRole == .admin {
                        Button {
                            Task { await loadOriginal() }
                        } label: {
                            if isLoadingOriginal {
                                ProgressView()
                            } else {
                                Label(
                                    showingOriginal ? "Showing Original" : "Access Original",
                                    systemImage: showingOriginal ? "eye.fill" : "lock.open.fill"
                                )
                            }
                        }
                        .buttonStyle(.borderedProminent)
                        .tint(Color("ForgeBlue"))
                        .disabled(isLoadingOriginal)
                    }
                }

                // Download / export — routes through service (access check + audit)
                if let url = exportURL {
                    ShareLink(item: url) {
                        Label("Export", systemImage: "square.and.arrow.up")
                    }
                    .buttonStyle(.bordered)
                } else {
                    Button {
                        Task { await downloadForExport() }
                    } label: {
                        if isDownloading {
                            ProgressView()
                        } else {
                            Label("Download", systemImage: "arrow.down.circle")
                        }
                    }
                    .buttonStyle(.bordered)
                    .disabled(isDownloading)
                }

                if let msg = errorMessage {
                    Text(msg)
                        .font(.caption)
                        .foregroundStyle(Color("Danger"))
                        .multilineTextAlignment(.center)
                }

                Spacer()
            }
            .padding()
            .navigationTitle("Attachment Details")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Close") { dismiss() }
                }
            }
            .task { await loadPreviewImage() }
        }
    }

    /// Loads the main (watermarked) preview via the service (access-checked, audited).
    private func loadPreviewImage() async {
        guard let actorId = appState.currentUserId else { return }
        guard let data = try? await attachmentService.downloadAttachment(id: attachment.id, actorId: actorId),
              let img = UIImage(data: data) else { return }
        previewImage = img
    }

    /// Fetches and decrypts the original via the service. Admin-only; audited.
    private func loadOriginal() async {
        guard let actorId = appState.currentUserId else { return }
        isLoadingOriginal = true
        do {
            let data = try await attachmentService.downloadOriginal(id: attachment.id, actorId: actorId)
            guard let img = UIImage(data: data) else { return }
            originalImage = img
            showingOriginal = true
        } catch {
            errorMessage = error.localizedDescription
        }
        isLoadingOriginal = false
    }

    /// Downloads the attachment via the service and stages it for export. Audited.
    private func downloadForExport() async {
        guard let actorId = appState.currentUserId else { return }
        isDownloading = true
        do {
            let data = try await attachmentService.downloadAttachment(id: attachment.id, actorId: actorId)
            let tempURL = FileManager.default.temporaryDirectory
                .appendingPathComponent(attachment.fileName)
            try data.write(to: tempURL)
            exportURL = tempURL
        } catch {
            errorMessage = error.localizedDescription
        }
        isDownloading = false
    }

    private var iconName: String {
        switch attachment.mimeType {
        case .pdf: return "doc.fill"
        case .jpg, .png, .heic: return "photo.fill"
        case .mov: return "video.fill"
        }
    }
}
