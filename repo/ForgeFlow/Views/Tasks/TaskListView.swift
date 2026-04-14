import SwiftUI

struct TaskListView: View {
    @State private var viewModel: TaskListViewModel
    @State private var showAddSubtask = false
    @State private var selectedParentId: UUID?

    private let taskService: TaskService
    private let appState: AppState
    var commentService: CommentService?
    var attachmentService: AttachmentService?

    var watermarkEnabled: Bool = false

    init(postingId: UUID, taskService: TaskService, appState: AppState,
         commentService: CommentService? = nil, attachmentService: AttachmentService? = nil,
         watermarkEnabled: Bool = false) {
        self.taskService = taskService
        self.appState = appState
        self.commentService = commentService
        self.attachmentService = attachmentService
        self.watermarkEnabled = watermarkEnabled
        _viewModel = State(initialValue: TaskListViewModel(
            postingId: postingId, taskService: taskService, appState: appState
        ))
    }

    var body: some View {
        Group {
            if viewModel.tasks.isEmpty && !viewModel.isLoading {
                EmptyStateView(
                    icon: "checklist", heading: "No Tasks",
                    description: "Tasks will appear here when a posting is created."
                )
            } else {
                List {
                    ForEach(viewModel.parentTasks) { parent in
                        Section {
                            // Parent task row
                            NavigationLink {
                                TaskDetailView(taskId: parent.id, taskService: taskService, appState: appState,
                                   commentService: commentService, attachmentService: attachmentService,
                                   watermarkEnabled: watermarkEnabled)
                            } label: {
                                TaskRowView(task: parent)
                            }
                            .swipeActions(edge: .trailing) {
                                statusSwipeActions(for: parent)
                            }

                            // Subtasks
                            ForEach(viewModel.subtasks(for: parent.id)) { subtask in
                                NavigationLink {
                                    TaskDetailView(taskId: subtask.id, taskService: taskService, appState: appState,
                                   commentService: commentService, attachmentService: attachmentService,
                                   watermarkEnabled: watermarkEnabled)
                                } label: {
                                    TaskRowView(task: subtask)
                                        .padding(.leading, 16)
                                }
                                .swipeActions(edge: .trailing) {
                                    statusSwipeActions(for: subtask)
                                }
                            }

                            // Add subtask button
                            Button {
                                selectedParentId = parent.id
                                showAddSubtask = true
                            } label: {
                                Label("Add Subtask", systemImage: "plus.circle")
                                    .font(.subheadline)
                                    .foregroundStyle(Color("ForgeBlue"))
                            }
                        }
                    }
                }
                .listStyle(.insetGrouped)
            }
        }
        .navigationTitle("Tasks")
        .sheet(isPresented: $showAddSubtask) {
            if let parentId = selectedParentId {
                TaskFormView(parentTaskId: parentId, viewModel: viewModel)
            }
        }
        .task { await viewModel.loadTasks() }
        .refreshable { await viewModel.loadTasks() }
        .alert("Error", isPresented: .constant(viewModel.errorMessage != nil)) {
            Button("OK") { viewModel.errorMessage = nil }
        } message: {
            Text(viewModel.errorMessage ?? "")
        }
    }

    @ViewBuilder
    private func statusSwipeActions(for task: ForgeTask) -> some View {
        switch task.status {
        case .notStarted:
            Button("Start") {
                Task { await viewModel.updateStatus(taskId: task.id, newStatus: .inProgress) }
            }.tint(Color("Warning"))
        case .inProgress:
            Button("Done") {
                Task { await viewModel.updateStatus(taskId: task.id, newStatus: .done) }
            }.tint(Color("Success"))
        case .blocked:
            Button("Resume") {
                Task { await viewModel.updateStatus(taskId: task.id, newStatus: .inProgress) }
            }.tint(Color("InfoBlue"))
        case .done:
            EmptyView()
        }
    }
}

// MARK: - Task Row

struct TaskRowView: View {
    let task: ForgeTask

    var body: some View {
        HStack(spacing: 12) {
            statusIcon
            VStack(alignment: .leading, spacing: 4) {
                Text(task.title)
                    .font(.subheadline)
                    .fontWeight(.medium)
                    .foregroundStyle(Color("TextPrimary"))
                    .strikethrough(task.status == .done)
                HStack(spacing: 8) {
                    PriorityBadge(priority: task.priority)
                    StatusBadge(status: task.status)
                }
            }
            Spacer()
        }
        .padding(.vertical, 2)
        .accessibilityElement(children: .combine)
    }

    @ViewBuilder
    private var statusIcon: some View {
        switch task.status {
        case .notStarted:
            Image(systemName: "circle")
                .foregroundStyle(Color("TextTertiary"))
        case .inProgress:
            Image(systemName: "circle.dotted.circle")
                .foregroundStyle(Color("Warning"))
        case .blocked:
            Image(systemName: "exclamationmark.circle.fill")
                .foregroundStyle(Color("Danger"))
        case .done:
            Image(systemName: "checkmark.circle.fill")
                .foregroundStyle(Color("Success"))
        }
    }
}
