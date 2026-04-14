import SwiftUI

struct SyncStatusView: View {
    let syncService: SyncService
    let postingService: PostingService
    @Environment(AppState.self) private var appState
    @State private var vm: SyncViewModel?

    var body: some View {
        Group {
            if let vm {
                List {
                    Section("Status") {
                        if let exp = vm.lastExport {
                            LabeledContent("Last Export", value: DateFormatters.display.string(from: exp.exportedAt))
                            LabeledContent("Records Exported", value: "\(exp.recordCount)")
                        } else {
                            Text("No exports yet")
                                .foregroundStyle(.secondary)
                        }
                        if let imp = vm.lastImport {
                            LabeledContent("Last Import", value: DateFormatters.display.string(from: imp.importedAt))
                            LabeledContent("Records Imported", value: "\(imp.recordCount)")
                            LabeledContent("Conflicts", value: "\(imp.conflictsCount)")
                        } else {
                            Text("No imports yet")
                                .foregroundStyle(.secondary)
                        }
                    }

                    Section {
                        NavigationLink("Export Data") {
                            ExportView(syncService: syncService)
                        }
                        NavigationLink("Import Data") {
                            ImportView(syncService: syncService, postingService: postingService)
                        }
                    }

                    if !vm.exports.isEmpty {
                        Section("Export History") {
                            ForEach(vm.exports) { export in
                                HStack {
                                    VStack(alignment: .leading) {
                                        Text("\(export.recordCount) records")
                                            .font(.subheadline)
                                        Text(DateFormatters.display.string(from: export.exportedAt))
                                            .font(.caption)
                                            .foregroundStyle(.secondary)
                                    }
                                    Spacer()
                                    Image(systemName: "checkmark.circle.fill")
                                        .foregroundStyle(.green)
                                }
                            }
                        }
                    }
                }
                .refreshable { await vm.load() }
            } else {
                ProgressView()
            }
        }
        .navigationTitle("Sync")
        .task {
            let viewModel = SyncViewModel(syncService: syncService, appState: appState)
            vm = viewModel
            await viewModel.load()
        }
    }
}
