import SwiftUI
import PhotosUI
import UniformTypeIdentifiers

struct AttachmentUploadView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var selectedPhotoItem: PhotosPickerItem?
    @State private var showingDocumentPicker = false
    @State private var isUploading = false
    @State private var errorMessage: String?

    let postingId: UUID
    var commentId: UUID? = nil
    let attachmentService: AttachmentService
    let appState: AppState
    var watermarkEnabled: Bool = false

    /// Allowed UTTypes for document picker (PDF, images)
    private let allowedTypes: [UTType] = [.pdf, .jpeg, .png, .heic, .quickTimeMovie]

    var body: some View {
        NavigationStack {
            Form {
                Section("Choose File") {
                    PhotosPicker(
                        selection: $selectedPhotoItem,
                        matching: .any(of: [.images, .videos])
                    ) {
                        Label("Select from Photos", systemImage: "photo.on.rectangle")
                    }

                    Button {
                        showingDocumentPicker = true
                    } label: {
                        Label("Select from Files (PDF, images)", systemImage: "doc.badge.plus")
                    }
                }

                if isUploading {
                    Section {
                        HStack {
                            ProgressView()
                            Text("Uploading...")
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                        }
                    }
                }

                if let error = errorMessage {
                    Section {
                        Text(error)
                            .font(.caption)
                            .foregroundStyle(.red)
                    }
                }
            }
            .navigationTitle("Upload Attachment")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
            }
            .onChange(of: selectedPhotoItem) { _, newItem in
                guard let item = newItem else { return }
                Task { await uploadPhotoItem(item) }
            }
            .fileImporter(
                isPresented: $showingDocumentPicker,
                allowedContentTypes: allowedTypes,
                allowsMultipleSelection: false
            ) { result in
                switch result {
                case .success(let urls):
                    guard let url = urls.first else { return }
                    Task { await uploadFileURL(url) }
                case .failure(let error):
                    errorMessage = error.localizedDescription
                }
            }
        }
    }

    private func uploadPhotoItem(_ item: PhotosPickerItem) async {
        isUploading = true
        errorMessage = nil
        do {
            guard let data = try await item.loadTransferable(type: Data.self) else {
                errorMessage = "Could not load file data."
                isUploading = false
                return
            }
            guard let userId = appState.currentUserId else { return }
            let fileName = "photo_\(UUID().uuidString.prefix(8))"
            _ = try await attachmentService.upload(
                fileData: data, fileName: fileName,
                postingId: postingId, commentId: commentId, taskId: nil,
                uploadedBy: userId, watermarkEnabled: watermarkEnabled,
                watermarkUsername: watermarkEnabled ? appState.currentUsername : nil
            )
            dismiss()
        } catch {
            errorMessage = error.localizedDescription
            isUploading = false
        }
    }

    private func uploadFileURL(_ url: URL) async {
        isUploading = true
        errorMessage = nil
        do {
            guard url.startAccessingSecurityScopedResource() else {
                errorMessage = "Could not access the selected file."
                isUploading = false
                return
            }
            defer { url.stopAccessingSecurityScopedResource() }

            let data = try Data(contentsOf: url)
            guard let userId = appState.currentUserId else { return }

            _ = try await attachmentService.upload(
                fileData: data, fileName: url.lastPathComponent,
                postingId: postingId, commentId: commentId, taskId: nil,
                uploadedBy: userId, watermarkEnabled: watermarkEnabled,
                watermarkUsername: watermarkEnabled ? appState.currentUsername : nil
            )
            dismiss()
        } catch {
            errorMessage = error.localizedDescription
            isUploading = false
        }
    }
}
