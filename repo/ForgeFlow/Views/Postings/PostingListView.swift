import SwiftUI

struct PostingListView: View {
    @Environment(AppState.self) private var appState
    @State private var listViewModel: PostingListViewModel
    @State private var formViewModel: PostingFormViewModel
    @State private var showCreateSheet = false

    private let postingService: PostingService
    private let assignmentService: AssignmentService
    private let authService: AuthService
    var taskService: TaskService?
    var commentService: CommentService?
    var attachmentService: AttachmentService?
    var pluginService: PluginService?

    init(postingService: PostingService, assignmentService: AssignmentService,
         authService: AuthService, appState: AppState, taskService: TaskService? = nil,
         commentService: CommentService? = nil, attachmentService: AttachmentService? = nil,
         pluginService: PluginService? = nil) {
        self.postingService = postingService
        self.assignmentService = assignmentService
        self.authService = authService
        self.taskService = taskService
        self.commentService = commentService
        self.attachmentService = attachmentService
        self.pluginService = pluginService
        _listViewModel = State(initialValue: PostingListViewModel(postingService: postingService, appState: appState))
        _formViewModel = State(initialValue: PostingFormViewModel(postingService: postingService, appState: appState, pluginService: pluginService))
    }

    private var canCreate: Bool {
        appState.currentUserRole == .admin || appState.currentUserRole == .coordinator
    }

    var body: some View {
        Group {
            if listViewModel.filteredPostings.isEmpty && !listViewModel.isLoading {
                EmptyStateView(
                    icon: "doc.text",
                    heading: "No Postings",
                    description: canCreate
                        ? "Create your first service posting to get started."
                        : "No postings available yet.",
                    actionTitle: canCreate ? "Create Posting" : nil,
                    action: canCreate ? { showCreateSheet = true } : nil
                )
            } else {
                List {
                    ForEach(listViewModel.filteredPostings) { posting in
                        NavigationLink {
                            PostingDetailView(
                                postingId: posting.id,
                                postingService: postingService,
                                assignmentService: assignmentService,
                                authService: authService,
                                appState: appState,
                                taskService: taskService,
                                commentService: commentService,
                                attachmentService: attachmentService
                            )
                        } label: {
                            PostingRowView(posting: posting)
                        }
                        .swipeActions(edge: .trailing) {
                            if canCreate && posting.status != .cancelled && posting.status != .completed {
                                Button("Cancel", role: .destructive) {
                                    Task { await listViewModel.cancelPosting(posting.id) }
                                }
                            }
                        }
                    }
                }
                .listStyle(.plain)
            }
        }
        .navigationTitle("Postings")
        .toolbar {
            if canCreate {
                ToolbarItem(placement: .primaryAction) {
                    Button { showCreateSheet = true } label: {
                        Image(systemName: "plus")
                    }
                    .accessibilityLabel("Create Posting")
                }
            }
        }
        .sheet(isPresented: $showCreateSheet) {
            PostingFormView(viewModel: formViewModel) {
                showCreateSheet = false
                Task { await listViewModel.loadPostings() }
            }
        }
        .task { await listViewModel.loadPostings() }
        .refreshable { await listViewModel.loadPostings() }
        .background(Color("SurfacePrimary"))
    }
}
