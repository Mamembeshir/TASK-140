import SwiftUI

struct PluginTestView: View {
    let pluginId: UUID
    let pluginService: PluginService
    let postingService: PostingService
    @Environment(\.dismiss) private var dismiss
    @Environment(AppState.self) private var appState
    @State private var vm: PluginTestViewModel?

    var body: some View {
        Group {
            if let vm {
                List {
                    Section("Select Sample Postings") {
                        ForEach(vm.availablePostings) { posting in
                            Button {
                                vm.togglePosting(posting.id)
                            } label: {
                                HStack {
                                    Image(systemName: vm.selectedPostingIds.contains(posting.id)
                                          ? "checkmark.circle.fill" : "circle")
                                        .foregroundStyle(vm.selectedPostingIds.contains(posting.id)
                                                         ? .blue : .secondary)
                                    VStack(alignment: .leading) {
                                        Text(posting.title)
                                            .font(.subheadline)
                                        Text(posting.status.rawValue)
                                            .font(.caption)
                                            .foregroundStyle(.secondary)
                                    }
                                }
                            }
                            .tint(.primary)
                        }
                    }

                    if !vm.testResults.isEmpty {
                        Section("Test Results") {
                            ForEach(vm.testResults) { result in
                                HStack {
                                    Image(systemName: result.status == .pass
                                          ? "checkmark.circle.fill" : "xmark.circle.fill")
                                        .foregroundStyle(result.status == .pass ? .green : .red)
                                    VStack(alignment: .leading) {
                                        Text(result.postingId.uuidString.prefix(8))
                                            .font(.subheadline.monospaced())
                                        if let error = result.errorDetails {
                                            Text(error)
                                                .font(.caption)
                                                .foregroundStyle(.red)
                                        }
                                    }
                                }
                            }
                        }
                    }
                }
                .navigationTitle("Test Plugin")
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        Button("Done") { dismiss() }
                    }
                    ToolbarItem(placement: .primaryAction) {
                        Button("Run Tests") {
                            Task { await vm.runTests() }
                        }
                        .disabled(vm.selectedPostingIds.isEmpty || vm.isRunning)
                    }
                }
            } else {
                ProgressView()
            }
        }
        .task {
            let viewModel = PluginTestViewModel(pluginService: pluginService, postingService: postingService, appState: appState)
            vm = viewModel
            await viewModel.load(pluginId: pluginId)
        }
    }
}
