import SwiftUI

struct PostingDetailView: View {
    @Environment(AppState.self) private var appState
    @State private var viewModel: PostingDetailViewModel

    private let postingService: PostingService
    private let assignmentService: AssignmentService
    private let authService: AuthService
    var taskService: TaskService?
    var commentService: CommentService?
    var attachmentService: AttachmentService?

    init(postingId: UUID, postingService: PostingService, assignmentService: AssignmentService,
         authService: AuthService, appState: AppState, taskService: TaskService? = nil,
         commentService: CommentService? = nil, attachmentService: AttachmentService? = nil) {
        self.postingService = postingService
        self.assignmentService = assignmentService
        self.authService = authService
        self.taskService = taskService
        self.commentService = commentService
        self.attachmentService = attachmentService
        _viewModel = State(initialValue: PostingDetailViewModel(
            postingId: postingId,
            postingService: postingService,
            assignmentService: assignmentService,
            appState: appState
        ))
    }

    var body: some View {
        Group {
            if let posting = viewModel.posting {
                List {
                    postingInfoSection(posting)
                    assignmentsSection
                    tasksSection
                    commentsSection(posting)
                    attachmentsSection(posting)
                    actionsSection(posting)
                }
                .listStyle(.insetGrouped)
            } else if viewModel.isLoading {
                ProgressView("Loading...")
            } else {
                EmptyStateView(icon: "exclamationmark.triangle", heading: "Not Found",
                               description: "This posting could not be loaded.")
            }
        }
        .navigationTitle(viewModel.posting?.title ?? "Posting")
        .navigationBarTitleDisplayMode(.large)
        .task { await viewModel.load() }
        .refreshable { await viewModel.load() }
        .alert("Error", isPresented: .constant(viewModel.errorMessage != nil)) {
            Button("OK") { viewModel.errorMessage = nil }
        } message: {
            Text(viewModel.errorMessage ?? "")
        }
    }

    // MARK: - Sections

    @ViewBuilder
    private func postingInfoSection(_ posting: ServicePosting) -> some View {
        Section("Details") {
            LabeledContent("Status") { StatusBadge(status: posting.status) }
            LabeledContent("Site Address") { Text(posting.siteAddress).foregroundStyle(Color("TextPrimary")) }
            LabeledContent("Due Date") { DueDateLabel(date: posting.dueDate) }
            LabeledContent("Budget") { BudgetLabel(cents: posting.budgetCapCents) }
            LabeledContent("Acceptance") {
                Text(posting.acceptanceMode == .inviteOnly ? "Invite Only" : "Open")
                    .foregroundStyle(Color("TextSecondary"))
            }
            if posting.watermarkEnabled {
                LabeledContent("Watermark") {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundStyle(Color("Success"))
                }
            }
        }
    }

    @ViewBuilder
    private var assignmentsSection: some View {
        Section("Assignments (\(viewModel.assignments.count))") {
            if viewModel.assignments.isEmpty {
                Text("No assignments yet")
                    .font(.subheadline)
                    .foregroundStyle(Color("TextTertiary"))
            } else {
                ForEach(viewModel.assignments) { assignment in
                    VStack(alignment: .leading, spacing: 2) {
                        HStack {
                            Text(assignment.technicianId.uuidString.prefix(8))
                                .font(.subheadline)
                                .foregroundStyle(Color("TextPrimary"))
                            Spacer()
                            StatusBadge(status: assignment.status)
                        }
                        if let note = assignment.auditNote {
                            Text(note)
                                .font(.caption)
                                .foregroundStyle(Color("TextTertiary"))
                        }
                    }
                }
            }
        }
    }

    @ViewBuilder
    private var tasksSection: some View {
        Section {
            if viewModel.tasks.isEmpty {
                Text("No tasks")
                    .font(.subheadline)
                    .foregroundStyle(Color("TextTertiary"))
            } else {
                ForEach(viewModel.tasks) { task in
                    HStack {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(task.title)
                                .font(.subheadline)
                                .foregroundStyle(Color("TextPrimary"))
                            PriorityBadge(priority: task.priority)
                        }
                        Spacer()
                        StatusBadge(status: task.status)
                    }
                }
            }
            if let taskService, let posting = viewModel.posting {
                NavigationLink {
                    TaskListView(postingId: posting.id, taskService: taskService, appState: appState,
                                commentService: commentService, attachmentService: attachmentService,
                                watermarkEnabled: posting.watermarkEnabled)
                } label: {
                    Label("Manage Tasks", systemImage: "checklist")
                        .foregroundStyle(Color("ForgeBlue"))
                }
            }
        } header: {
            Text("Tasks (\(viewModel.tasks.count))")
        }
    }

    @ViewBuilder
    private func commentsSection(_ posting: ServicePosting) -> some View {
        if let commentService {
            Section("Comments") {
                NavigationLink {
                    CommentListView(
                        postingId: posting.id,
                        commentService: commentService,
                        attachmentService: attachmentService,
                        appState: appState,
                        watermarkEnabled: posting.watermarkEnabled
                    )
                } label: {
                    Label("View Comments", systemImage: "bubble.left.and.bubble.right")
                        .foregroundStyle(Color("ForgeBlue"))
                }
            }
        }
    }

    @ViewBuilder
    private func attachmentsSection(_ posting: ServicePosting) -> some View {
        if let attachmentService {
            Section("Attachments") {
                NavigationLink {
                    AttachmentThumbnailGrid(
                        postingId: posting.id,
                        attachmentService: attachmentService,
                        appState: appState,
                        watermarkEnabled: posting.watermarkEnabled
                    )
                } label: {
                    Label("View Attachments", systemImage: "paperclip")
                        .foregroundStyle(Color("ForgeBlue"))
                }
            }
        }
    }

    @ViewBuilder
    private func actionsSection(_ posting: ServicePosting) -> some View {
        if viewModel.canPublish || viewModel.canCancel || viewModel.canAccept || viewModel.canDecline || viewModel.canInvite {
            Section("Actions") {
                if viewModel.canPublish {
                    Button {
                        Task { await viewModel.publish() }
                    } label: {
                        Label("Publish Posting", systemImage: "paperplane.fill")
                    }
                    .tint(Color("ForgeBlue"))
                }

                if viewModel.canInvite {
                    NavigationLink {
                        InviteTechniciansView(
                            assignmentService: assignmentService,
                            authService: authService,
                            postingId: posting.id,
                            appState: appState
                        )
                    } label: {
                        Label("Invite Technicians", systemImage: "person.badge.plus")
                    }
                }

                if viewModel.canAccept {
                    Button {
                        Task { await viewModel.acceptAssignment() }
                    } label: {
                        Label("Accept Assignment", systemImage: "checkmark.circle.fill")
                    }
                    .tint(Color("Success"))
                }

                if viewModel.canDecline {
                    Button(role: .destructive) {
                        Task { await viewModel.declineAssignment() }
                    } label: {
                        Label("Decline Assignment", systemImage: "xmark.circle.fill")
                    }
                }

                if viewModel.canCancel {
                    ConfirmationButton(
                        title: "Cancel Posting",
                        confirmTitle: "Cancel this posting?",
                        confirmMessage: "This will cancel the posting and cannot be undone."
                    ) {
                        Task { await viewModel.cancel() }
                    }
                }
            }
        }
    }
}
