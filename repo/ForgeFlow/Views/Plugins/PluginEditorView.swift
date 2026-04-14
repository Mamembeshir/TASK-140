import SwiftUI

struct PluginEditorView: View {
    let pluginId: UUID
    let pluginService: PluginService
    let postingService: PostingService
    @Environment(AppState.self) private var appState
    @State private var vm: PluginEditorViewModel?
    @State private var showingTestView = false

    var body: some View {
        Group {
            if let vm {
                List {
                    if let plugin = vm.plugin {
                        Section("Plugin Details") {
                            LabeledContent("Name", value: plugin.name)
                            LabeledContent("Category", value: plugin.category)
                            LabeledContent("Status", value: plugin.status.rawValue)
                        }
                    }

                    Section("Fields (\(vm.fields.count))") {
                        ForEach(vm.fields) { field in
                            VStack(alignment: .leading, spacing: 2) {
                                Text(field.fieldName)
                                    .font(.subheadline.weight(.medium))
                                HStack {
                                    Text(field.fieldType.rawValue)
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                    if let unit = field.unit {
                                        Text("(\(unit))")
                                            .font(.caption)
                                            .foregroundStyle(.secondary)
                                    }
                                }
                            }
                        }
                    }

                    if vm.plugin?.status == .draft || vm.plugin?.status == .testing {
                        Section("Add Field") {
                            TextField("Field Name", text: Binding(
                                get: { vm.newFieldName },
                                set: { vm.newFieldName = $0 }
                            ))
                            Picker("Type", selection: Binding(
                                get: { vm.newFieldType },
                                set: { vm.newFieldType = $0 }
                            )) {
                                ForEach(PluginFieldType.allCases, id: \.self) { type in
                                    Text(type.rawValue).tag(type)
                                }
                            }
                            TextField("Unit (optional)", text: Binding(
                                get: { vm.newFieldUnit },
                                set: { vm.newFieldUnit = $0 }
                            ))
                            TextField("Validation Rules JSON (optional)", text: Binding(
                                get: { vm.newFieldValidation },
                                set: { vm.newFieldValidation = $0 }
                            ))
                            Button("Add Field") {
                                Task { await vm.addField() }
                            }
                            .disabled(vm.newFieldName.isEmpty)
                        }

                        Section {
                            Button("Test Plugin") {
                                showingTestView = true
                            }
                            if vm.plugin?.status == .testing {
                                Button("Submit for Approval") {
                                    Task { await vm.submitForApproval() }
                                }
                                .tint(.blue)
                            }
                        }
                    }
                }
                .navigationTitle(vm.plugin?.name ?? "Plugin Editor")
            } else {
                ProgressView()
            }
        }
        .sheet(isPresented: $showingTestView) {
            NavigationStack {
                PluginTestView(pluginId: pluginId, pluginService: pluginService, postingService: postingService)
            }
        }
        .task {
            let viewModel = PluginEditorViewModel(pluginService: pluginService, appState: appState)
            vm = viewModel
            await viewModel.load(pluginId: pluginId)
        }
    }
}
