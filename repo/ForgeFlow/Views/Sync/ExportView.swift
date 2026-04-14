import SwiftUI

struct ExportView: View {
    let syncService: SyncService
    @Environment(AppState.self) private var appState
    @State private var vm: SyncViewModel?

    var body: some View {
        Group {
            if let vm {
                List {
                    Section("Entity Types") {
                        Toggle("Postings", isOn: Binding(
                            get: { vm.exportPostings },
                            set: { vm.exportPostings = $0 }
                        ))
                        Toggle("Tasks", isOn: Binding(
                            get: { vm.exportTasks },
                            set: { vm.exportTasks = $0 }
                        ))
                        Toggle("Assignments", isOn: Binding(
                            get: { vm.exportAssignments },
                            set: { vm.exportAssignments = $0 }
                        ))
                        Toggle("Comments", isOn: Binding(
                            get: { vm.exportComments },
                            set: { vm.exportComments = $0 }
                        ))
                        Toggle("Dependencies", isOn: Binding(
                            get: { vm.exportDependencies },
                            set: { vm.exportDependencies = $0 }
                        ))
                    }

                    // Delta sync: peer-aware incremental export
                    Section {
                        TextField("Peer Device ID", text: Binding(
                            get: { vm.peerDeviceId },
                            set: { vm.peerDeviceId = $0 }
                        ))
                        .autocorrectionDisabled()
                        .textInputAutocapitalization(.never)

                        Button {
                            Task { await vm.deltaExport() }
                        } label: {
                            HStack {
                                Spacer()
                                if vm.isExporting {
                                    ProgressView().padding(.trailing, 8)
                                }
                                Text(vm.isExporting ? "Exporting…" : "Delta Export")
                                    .font(.headline)
                                Spacer()
                            }
                        }
                        .disabled(vm.isExporting || vm.selectedEntityTypes.isEmpty || vm.peerDeviceId.isEmpty)

                        // Confirm delivery — advances cursor so next delta starts from here
                        if vm.pendingDeltaConfirmation != nil {
                            Button {
                                Task { await vm.confirmDeltaDelivered() }
                            } label: {
                                Label("Confirm Delivered to Peer", systemImage: "checkmark.seal")
                                    .foregroundStyle(.green)
                            }
                        }
                    } header: {
                        Text("Incremental (Delta) Sync")
                    } footer: {
                        Text("Delta Export sends only records changed since the last confirmed sync with the peer. Tap Confirm Delivered after the peer imports successfully to advance the cursor.")
                    }

                    // Manual full export with optional date range
                    Section("Full Export (Date Range)") {
                        DatePicker("Start", selection: Binding(
                            get: { vm.exportStartDate ?? Date() },
                            set: { vm.exportStartDate = $0 }
                        ), displayedComponents: .date)
                        DatePicker("End", selection: Binding(
                            get: { vm.exportEndDate ?? Date() },
                            set: { vm.exportEndDate = $0 }
                        ), displayedComponents: .date)

                        Button {
                            Task { await vm.export() }
                        } label: {
                            HStack {
                                Spacer()
                                if vm.isExporting {
                                    ProgressView().padding(.trailing, 8)
                                }
                                Text(vm.isExporting ? "Exporting…" : "Full Export")
                                    .font(.headline)
                                Spacer()
                            }
                        }
                        .disabled(vm.isExporting || vm.selectedEntityTypes.isEmpty)
                    }

                    if let last = vm.lastExport {
                        Section("Last Export") {
                            LabeledContent("Records", value: "\(last.recordCount)")
                            LabeledContent("Checksum", value: String(last.checksumSha256.prefix(16)) + "…")
                        }
                    }

                    if let err = vm.errorMessage {
                        Section {
                            Text(err).foregroundStyle(.red)
                        }
                    }
                }
            } else {
                ProgressView()
            }
        }
        .navigationTitle("Export")
        .task {
            let viewModel = SyncViewModel(syncService: syncService, appState: appState)
            vm = viewModel
            await viewModel.load()
        }
    }
}
