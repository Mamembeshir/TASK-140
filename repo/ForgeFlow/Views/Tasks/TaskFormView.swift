import SwiftUI

struct TaskFormView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var title = ""
    @State private var priority: Priority = .p2
    @State private var errorMessage: String?

    let parentTaskId: UUID
    let viewModel: TaskListViewModel

    var body: some View {
        NavigationStack {
            Form {
                Section("Subtask Details") {
                    TextField("Title *", text: $title)
                }

                Section("Priority") {
                    Picker("Priority", selection: $priority) {
                        ForEach(Priority.allCases, id: \.self) { p in
                            HStack {
                                Circle()
                                    .fill(priorityColor(p))
                                    .frame(width: 8, height: 8)
                                Text("\(p.rawValue) — \(p.label)")
                            }
                            .tag(p)
                        }
                    }
                    .pickerStyle(.inline)
                    .labelsHidden()
                }

                if let error = errorMessage {
                    Section {
                        Text(error)
                            .font(.caption)
                            .foregroundStyle(Color("Danger"))
                    }
                }
            }
            .navigationTitle("New Subtask")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Create") {
                        Task {
                            await viewModel.createSubtask(
                                parentTaskId: parentTaskId,
                                title: title,
                                priority: priority,
                                assignedTo: nil
                            )
                            if viewModel.errorMessage == nil {
                                dismiss()
                            } else {
                                errorMessage = viewModel.errorMessage
                            }
                        }
                    }
                    .disabled(title.trimmingCharacters(in: .whitespaces).isEmpty)
                    .fontWeight(.bold)
                }
            }
        }
    }

    private func priorityColor(_ p: Priority) -> Color {
        switch p {
        case .p0: return Color("P0Critical")
        case .p1: return Color("P1High")
        case .p2: return Color("P2Medium")
        case .p3: return Color("P3Low")
        }
    }
}
