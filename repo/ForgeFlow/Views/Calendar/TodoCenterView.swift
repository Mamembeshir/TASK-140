import SwiftUI

struct TodoCenterView: View {
    @Environment(AppState.self) private var appState
    @State private var viewModel: TodoCenterViewModel
    @State private var showBlockedSheet = false
    @State private var blockedComment = ""
    @State private var blockingTaskId: UUID?

    private let taskService: TaskService

    init(taskService: TaskService, postingService: PostingService, appState: AppState) {
        self.taskService = taskService
        _viewModel = State(initialValue: TodoCenterViewModel(
            taskService: taskService, postingService: postingService, appState: appState
        ))
    }

    var body: some View {
        Group {
            if viewModel.tasksByPosting.isEmpty && !viewModel.isLoading {
                EmptyStateView(
                    icon: "checkmark.circle",
                    heading: "All Caught Up",
                    description: "No active tasks to work on."
                )
            } else {
                List {
                    ForEach(viewModel.tasksByPosting, id: \.posting.id) { group in
                        Section {
                            ForEach(group.tasks) { task in
                                TodoTaskRow(task: task) { newStatus in
                                    if newStatus == .blocked {
                                        blockingTaskId = task.id
                                        blockedComment = ""
                                        showBlockedSheet = true
                                    } else {
                                        Task {
                                            await viewModel.updateStatus(
                                                taskId: task.id, newStatus: newStatus
                                            )
                                        }
                                    }
                                }
                            }
                        } header: {
                            HStack {
                                Text(group.posting.title)
                                    .font(.subheadline)
                                    .fontWeight(.semibold)
                                Spacer()
                                StatusBadge(status: group.posting.status)
                            }
                        }
                    }
                }
                .listStyle(.insetGrouped)
            }
        }
        .navigationTitle("To-Do Center")
        .task { await viewModel.loadTodaysTasks() }
        .refreshable { await viewModel.loadTodaysTasks() }
        .sheet(isPresented: $showBlockedSheet) {
            NavigationStack {
                Form {
                    Section("Why is this task blocked?") {
                        TextField("Reason (min 10 characters)", text: $blockedComment, axis: .vertical)
                            .lineLimit(3...6)
                    }
                }
                .navigationTitle("Block Task")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        Button("Cancel") { showBlockedSheet = false }
                    }
                    ToolbarItem(placement: .confirmationAction) {
                        Button("Block") {
                            showBlockedSheet = false
                            if let taskId = blockingTaskId {
                                Task {
                                    await viewModel.updateStatus(
                                        taskId: taskId, newStatus: .blocked,
                                        blockedComment: blockedComment
                                    )
                                }
                            }
                        }
                        .disabled(blockedComment.count < 10)
                        .fontWeight(.bold)
                    }
                }
            }
        }
    }
}

// MARK: - Todo Task Row

private struct TodoTaskRow: View {
    let task: ForgeTask
    let onStatusChange: (TaskStatus) -> Void

    var body: some View {
        HStack(spacing: 12) {
            // Quick toggle button
            Button {
                switch task.status {
                case .notStarted: onStatusChange(.inProgress)
                case .inProgress: onStatusChange(.done)
                case .blocked: onStatusChange(.inProgress)
                case .done: break
                }
            } label: {
                statusIcon
            }
            .buttonStyle(.plain)

            VStack(alignment: .leading, spacing: 4) {
                Text(task.title)
                    .font(.subheadline)
                    .fontWeight(.medium)
                    .foregroundStyle(Color("TextPrimary"))
                    .strikethrough(task.status == .done)

                HStack(spacing: 6) {
                    PriorityBadge(priority: task.priority)
                    StatusBadge(status: task.status)
                }
            }
        }
        .padding(.vertical, 2)
    }

    @ViewBuilder
    private var statusIcon: some View {
        switch task.status {
        case .notStarted:
            Image(systemName: "circle")
                .font(.title3)
                .foregroundStyle(Color("TextTertiary"))
        case .inProgress:
            Image(systemName: "circle.dotted.circle")
                .font(.title3)
                .foregroundStyle(Color("Warning"))
        case .blocked:
            Image(systemName: "exclamationmark.circle.fill")
                .font(.title3)
                .foregroundStyle(Color("Danger"))
        case .done:
            Image(systemName: "checkmark.circle.fill")
                .font(.title3)
                .foregroundStyle(Color("Success"))
        }
    }
}
