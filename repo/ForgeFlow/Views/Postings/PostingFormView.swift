import SwiftUI

struct PostingFormView: View {
    @Bindable var viewModel: PostingFormViewModel
    @Environment(\.dismiss) private var dismiss
    var onCreated: (() -> Void)?

    var body: some View {
        NavigationStack {
            Form {
                Section("Details") {
                    TextField("Title *", text: $viewModel.title)
                    TextField("Site Address *", text: $viewModel.siteAddress)
                }

                Section("Schedule & Budget") {
                    DatePicker("Due Date *", selection: $viewModel.dueDate,
                               in: Date()..., displayedComponents: [.date, .hourAndMinute])

                    HStack {
                        Text("$")
                            .foregroundStyle(Color("TextSecondary"))
                        TextField("Budget *", text: $viewModel.budgetDollars)
                            .keyboardType(.decimalPad)
                    }
                }

                Section("Settings") {
                    Picker("Acceptance Mode", selection: $viewModel.acceptanceMode) {
                        Text("Invite Only").tag(AcceptanceMode.inviteOnly)
                        Text("Open").tag(AcceptanceMode.open)
                    }
                    .pickerStyle(.segmented)

                    Toggle("Watermark Attachments", isOn: $viewModel.watermarkEnabled)
                }

                ForEach(viewModel.activePluginFields, id: \.plugin.id) { group in
                    Section(group.plugin.name) {
                        ForEach(group.fields) { field in
                            pluginFieldRow(field)
                        }
                    }
                }

                if !viewModel.pluginValidationErrors.isEmpty {
                    Section {
                        ForEach(viewModel.pluginValidationErrors, id: \.self) { error in
                            Label(error, systemImage: "exclamationmark.circle")
                                .font(.caption)
                                .foregroundStyle(Color("Danger"))
                        }
                    }
                }

                if let error = viewModel.errorMessage {
                    Section {
                        Text(error)
                            .font(.caption)
                            .foregroundStyle(Color("Danger"))
                    }
                }
            }
            .navigationTitle("New Posting")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Create") {
                        Task {
                            if await viewModel.createPosting() != nil {
                                onCreated?()
                                dismiss()
                            }
                        }
                    }
                    .disabled(!viewModel.isValid || viewModel.isLoading)
                    .fontWeight(.bold)
                }
            }
            .task { await viewModel.loadPluginFields() }
        }
    }

    @ViewBuilder
    private func pluginFieldRow(_ field: PluginField) -> some View {
        switch field.fieldType {
        case .text:
            TextField(field.fieldName, text: stringBinding(for: field.id))
        case .number:
            TextField(field.fieldName, text: stringBinding(for: field.id))
                .keyboardType(.decimalPad)
        case .boolean:
            Toggle(field.fieldName, isOn: boolBinding(for: field.id))
        case .select:
            let options = selectOptions(for: field)
            if options.isEmpty {
                TextField(field.fieldName, text: stringBinding(for: field.id))
            } else {
                Picker(field.fieldName, selection: stringBinding(for: field.id)) {
                    ForEach(options, id: \.self) { Text($0).tag($0) }
                }
            }
        }
    }

    private func stringBinding(for fieldId: UUID) -> Binding<String> {
        Binding(
            get: { viewModel.pluginFieldValues[fieldId] ?? "" },
            set: { viewModel.pluginFieldValues[fieldId] = $0 }
        )
    }

    private func boolBinding(for fieldId: UUID) -> Binding<Bool> {
        Binding(
            get: { viewModel.pluginFieldValues[fieldId] == "true" },
            set: { viewModel.pluginFieldValues[fieldId] = $0 ? "true" : "false" }
        )
    }

    private func selectOptions(for field: PluginField) -> [String] {
        guard let json = field.validationRules,
              let data = json.data(using: .utf8),
              let rules = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let values = rules["allowedValues"] as? [String] else { return [] }
        return values
    }
}
