import SwiftUI
import UniformTypeIdentifiers

struct ImportView: View {
    let syncService: SyncService
    let postingService: PostingService
    @Environment(AppState.self) private var appState
    @State private var vm: SyncViewModel?
    @State private var showingFilePicker = false

    var body: some View {
        Group {
            if let vm {
                List {
                    Section {
                        TextField("Source Peer Device ID (optional)", text: Binding(
                            get: { vm.sourcePeerIdForImport },
                            set: { vm.sourcePeerIdForImport = $0 }
                        ))
                        .autocorrectionDisabled()
                        .textInputAutocapitalization(.never)

                        Button {
                            showingFilePicker = true
                        } label: {
                            Label("Select .forgeflow File", systemImage: "doc.badge.plus")
                        }
                        .disabled(vm.isImporting)
                    } footer: {
                        Text("Enter the peer's device ID to advance the delta cursor after import.")
                    }

                    if vm.isImporting {
                        Section {
                            HStack {
                                ProgressView()
                                Text("Validating import file...")
                                    .font(.subheadline)
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }

                    if let imp = vm.lastImport {
                        Section("Import Status") {
                            LabeledContent("Records", value: "\(imp.recordCount)")
                            LabeledContent("Conflicts", value: "\(imp.conflictsCount)")
                            LabeledContent("Status", value: imp.status.rawValue)
                        }
                    }

                    if !vm.conflicts.isEmpty {
                        Section("Conflicts (\(vm.conflicts.count))") {
                            ForEach(vm.conflicts, id: \.entityId) { conflict in
                                VStack(alignment: .leading, spacing: 6) {
                                    HStack {
                                        Text(conflict.entityType)
                                            .font(.caption.weight(.semibold))
                                            .textCase(.uppercase)
                                        Spacer()
                                        Text("v\(conflict.localVersion) → v\(conflict.incomingVersion)")
                                            .font(.caption.monospaced())
                                    }
                                    HStack(spacing: 8) {
                                        VStack(alignment: .leading) {
                                            Text("Local")
                                                .font(.caption2.weight(.semibold))
                                            Text(conflict.localData)
                                                .font(.caption2)
                                                .foregroundStyle(.secondary)
                                        }
                                        .frame(maxWidth: .infinity, alignment: .leading)

                                        VStack(alignment: .leading) {
                                            Text("Incoming")
                                                .font(.caption2.weight(.semibold))
                                            Text(conflict.incomingData)
                                                .font(.caption2)
                                                .foregroundStyle(.secondary)
                                        }
                                        .frame(maxWidth: .infinity, alignment: .leading)
                                    }
                                    HStack {
                                        Button("Keep Local") {
                                            Task { await vm.resolveConflict(entityId: conflict.entityId, decision: .keepLocal) }
                                        }
                                        .buttonStyle(.bordered)
                                        .controlSize(.small)

                                        Button("Accept Incoming") {
                                            Task { await vm.resolveConflict(entityId: conflict.entityId, decision: .acceptIncoming) }
                                        }
                                        .buttonStyle(.bordered)
                                        .controlSize(.small)
                                    }
                                }
                                .padding(.vertical, 4)
                            }
                        }

                        Section("Bulk Actions") {
                            HStack {
                                Button("Keep All Local") {
                                    Task { await vm.resolveAllKeepLocal() }
                                }
                                .buttonStyle(.borderedProminent)
                                .tint(.blue)

                                Spacer()

                                Button("Accept All Incoming") {
                                    Task { await vm.resolveAllAcceptIncoming() }
                                }
                                .buttonStyle(.borderedProminent)
                                .tint(.orange)
                            }
                        }
                    }
                }
            } else {
                ProgressView()
            }
        }
        .navigationTitle("Import")
        .fileImporter(
            isPresented: $showingFilePicker,
            allowedContentTypes: [.data],
            allowsMultipleSelection: false
        ) { result in
            if case .success(let urls) = result, let url = urls.first {
                Task { await vm?.importFile(url: url) }
            }
        }
        .task {
            let viewModel = SyncViewModel(syncService: syncService, appState: appState)
            vm = viewModel
            await viewModel.load()
        }
    }
}
