import SwiftUI

struct TaskDetailView: View {
    @Environment(AppState.self) private var appState
    @State private var task: ForgeTask?
    @State private var dependencies: [Dependency] = []
    @State private var dependents: [Dependency] = []
    @State private var isLoading = false
    @State private var errorMessage: String?
    @State private var showBlockedSheet = false
    @State private var blockedComment = ""

    let taskId: UUID
    private let taskService: TaskService
    var commentService: CommentService?
    var attachmentService: AttachmentService?

    var watermarkEnabled: Bool = false

    init(taskId: UUID, taskService: TaskService, appState: AppState,
         commentService: CommentService? = nil, attachmentService: AttachmentService? = nil,
         watermarkEnabled: Bool = false) {
        self.taskId = taskId
        self.taskService = taskService
        self.commentService = commentService
        self.attachmentService = attachmentService
        self.watermarkEnabled = watermarkEnabled
    }

    var body: some View {
        Group {
            if let task {
                List {
                    infoSection(task)
                    dependenciesSection
                    taskCommentsSection(task)
                    actionsSection(task)
                }
                .listStyle(.insetGrouped)
            } else if isLoading {
                ProgressView("Loading...")
            }
        }
        .navigationTitle(task?.title ?? "Task")
        .task { await load() }
        .sheet(isPresented: $showBlockedSheet) {
            blockedCommentSheet
        }
        .alert("Error", isPresented: .constant(errorMessage != nil)) {
            Button("OK") { errorMessage = nil }
        } message: {
            Text(errorMessage ?? "")
        }
    }

    @ViewBuilder
    private func infoSection(_ task: ForgeTask) -> some View {
        Section("Details") {
            LabeledContent("Status") { StatusBadge(status: task.status) }
            LabeledContent("Priority") { PriorityBadge(priority: task.priority) }
            if let desc = task.taskDescription, !desc.isEmpty {
                LabeledContent("Description") {
                    Text(desc).foregroundStyle(Color("TextSecondary"))
                }
            }
            if let comment = task.blockedComment, task.status == .blocked {
                LabeledContent("Blocked Reason") {
                    Text(comment)
                        .foregroundStyle(Color("Danger"))
                        .font(.subheadline)
                }
            }
        }
    }

    @ViewBuilder
    private var dependenciesSection: some View {
        if !dependencies.isEmpty || !dependents.isEmpty {
            Section("Dependencies") {
                if !dependencies.isEmpty {
                    ForEach(dependencies) { dep in
                        HStack {
                            Image(systemName: "arrow.right.circle")
                                .foregroundStyle(Color("TextTertiary"))
                            Text("Depends on: \(dep.dependsOnTaskId.uuidString.prefix(8))...")
                                .font(.subheadline)
                                .foregroundStyle(Color("TextSecondary"))
                        }
                    }
                }
                if !dependents.isEmpty {
                    ForEach(dependents) { dep in
                        HStack {
                            Image(systemName: "arrow.left.circle")
                                .foregroundStyle(Color("TextTertiary"))
                            Text("Required by: \(dep.taskId.uuidString.prefix(8))...")
                                .font(.subheadline)
                                .foregroundStyle(Color("TextSecondary"))
                        }
                    }
                }
            }
        }
    }

    @ViewBuilder
    private func taskCommentsSection(_ task: ForgeTask) -> some View {
        if let commentService {
            Section("Comments") {
                NavigationLink {
                    CommentListView(
                        postingId: task.postingId,
                        commentService: commentService,
                        attachmentService: attachmentService,
                        appState: appState,
                        watermarkEnabled: watermarkEnabled
                    )
                } label: {
                    Label("View Comments", systemImage: "bubble.left.and.bubble.right")
                        .foregroundStyle(Color("ForgeBlue"))
                }
            }
        }
    }

    @ViewBuilder
    private func actionsSection(_ task: ForgeTask) -> some View {
        Section("Actions") {
            if task.status == .notStarted {
                Button {
                    Task { await changeStatus(.inProgress) }
                } label: {
                    Label("Start Task", systemImage: "play.fill")
                }.tint(Color("Warning"))
            }

            if task.status == .inProgress {
                Button {
                    Task { await changeStatus(.done) }
                } label: {
                    Label("Mark Done", systemImage: "checkmark.circle.fill")
                }.tint(Color("Success"))
            }

            if task.status == .notStarted || task.status == .inProgress {
                Button {
                    blockedComment = ""
                    showBlockedSheet = true
                } label: {
                    Label("Mark Blocked", systemImage: "exclamationmark.triangle.fill")
                }.tint(Color("Danger"))
            }

            if task.status == .blocked {
                Button {
                    Task { await changeStatus(.inProgress) }
                } label: {
                    Label("Resume Task", systemImage: "arrow.clockwise")
                }.tint(Color("InfoBlue"))

                Button {
                    Task { await changeStatus(.notStarted) }
                } label: {
                    Label("Reset to Not Started", systemImage: "arrow.uturn.backward")
                }.tint(Color("TextSecondary"))
            }
        }
    }

    private var blockedCommentSheet: some View {
        NavigationStack {
            Form {
                Section("Why is this task blocked?") {
                    TextField("Reason (min 10 characters)", text: $blockedComment, axis: .vertical)
                        .lineLimit(3...6)
                }
                if blockedComment.count > 0 && blockedComment.count < 10 {
                    Section {
                        Text("Comment must be at least 10 characters (\(blockedComment.count)/10)")
                            .font(.caption)
                            .foregroundStyle(Color("Danger"))
                    }
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
                        Task { await changeStatus(.blocked, comment: blockedComment) }
                    }
                    .disabled(blockedComment.count < 10)
                    .fontWeight(.bold)
                }
            }
        }
    }

    private func load() async {
        guard let actorId = appState.currentUserId else { return }
        isLoading = true
        do {
            task = try await taskService.getTask(id: taskId, actorId: actorId)
            dependencies = try await taskService.getDependencies(taskId: taskId)
            dependents = try await taskService.getDependents(taskId: taskId)
        } catch {
            errorMessage = error.localizedDescription
        }
        isLoading = false
    }

    private func changeStatus(_ status: TaskStatus, comment: String? = nil) async {
        guard let actorId = appState.currentUserId else { return }
        do {
            _ = try await taskService.updateStatus(
                actorId: actorId, taskId: taskId,
                newStatus: status, blockedComment: comment
            )
            await load()
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}
