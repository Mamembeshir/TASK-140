import SwiftUI

struct PluginApprovalView: View {
    let pluginId: UUID
    let pluginService: PluginService
    @Environment(AppState.self) private var appState
    @State private var vm: PluginApprovalViewModel?
    @State private var approvalNotes = ""

    var body: some View {
        Group {
            if let vm {
                List {
                    if let plugin = vm.plugin {
                        Section("Plugin Details") {
                            LabeledContent("Name", value: plugin.name)
                            LabeledContent("Description", value: plugin.description)
                            LabeledContent("Category", value: plugin.category)
                            LabeledContent("Status", value: plugin.status.rawValue)
                        }
                    }

                    Section("Fields (\(vm.fields.count))") {
                        ForEach(vm.fields) { field in
                            HStack {
                                Text(field.fieldName)
                                    .font(.subheadline)
                                Spacer()
                                Text(field.fieldType.rawValue)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }

                    Section("Test Results") {
                        ForEach(vm.testResults) { result in
                            HStack {
                                Image(systemName: result.status == .pass
                                      ? "checkmark.circle.fill" : "xmark.circle.fill")
                                    .foregroundStyle(result.status == .pass ? .green : .red)
                                Text(result.status.rawValue)
                                    .font(.subheadline)
                            }
                        }
                    }

                    Section("Approval History") {
                        ForEach(vm.approvals) { approval in
                            VStack(alignment: .leading, spacing: 4) {
                                HStack {
                                    Text("Step \(approval.step)")
                                        .font(.subheadline.weight(.medium))
                                    Spacer()
                                    Text(approval.decision.rawValue)
                                        .font(.caption.weight(.semibold))
                                        .foregroundStyle(approval.decision == .approved ? .green : .red)
                                }
                                if let notes = approval.notes, !notes.isEmpty {
                                    Text(notes)
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                            }
                        }
                        if vm.approvals.isEmpty {
                            Text("No approvals yet")
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                        }
                    }

                    if vm.canApprove {
                        Section("Review (Step \(vm.currentStep))") {
                            TextField("Notes (optional)", text: $approvalNotes, axis: .vertical)
                                .lineLimit(3...6)
                            HStack {
                                Button("Approve") {
                                    Task {
                                        await vm.approve(notes: approvalNotes.isEmpty ? nil : approvalNotes)
                                        approvalNotes = ""
                                    }
                                }
                                .buttonStyle(.borderedProminent)
                                .tint(.green)

                                Spacer()

                                Button("Reject") {
                                    Task {
                                        await vm.reject(notes: approvalNotes.isEmpty ? nil : approvalNotes)
                                        approvalNotes = ""
                                    }
                                }
                                .buttonStyle(.borderedProminent)
                                .tint(.red)
                            }
                        }
                    }
                }
                .navigationTitle("Plugin Approval")
            } else {
                ProgressView()
            }
        }
        .task {
            let viewModel = PluginApprovalViewModel(pluginService: pluginService, appState: appState)
            vm = viewModel
            await viewModel.load(pluginId: pluginId)
        }
    }
}
