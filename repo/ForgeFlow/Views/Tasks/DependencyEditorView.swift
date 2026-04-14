import SwiftUI

struct DependencyEditorView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(AppState.self) private var appState
    @State private var allTasks: [ForgeTask] = []
    @State private var currentDeps: [Dependency] = []
    @State private var isLoading = false
    @State private var errorMessage: String?

    let taskId: UUID
    let postingId: UUID
    private let taskService: TaskService

    init(taskId: UUID, postingId: UUID, taskService: TaskService) {
        self.taskId = taskId
        self.postingId = postingId
        self.taskService = taskService
    }

    private var availableTasks: [ForgeTask] {
        let depIds = Set(currentDeps.map { $0.dependsOnTaskId })
        return allTasks.filter { $0.id != taskId && !depIds.contains($0.id) }
    }

    var body: some View {
        List {
            if !currentDeps.isEmpty {
                Section("Current Dependencies") {
                    ForEach(currentDeps) { dep in
                        if let task = allTasks.first(where: { $0.id == dep.dependsOnTaskId }) {
                            HStack {
                                VStack(alignment: .leading) {
                                    Text(task.title)
                                        .font(.subheadline)
                                    StatusBadge(status: task.status)
                                }
                                Spacer()
                                Image(systemName: "link")
                                    .foregroundStyle(Color("ForgeBlue"))
                            }
                        }
                    }
                }
            }

            Section("Add Dependency") {
                if availableTasks.isEmpty {
                    Text("No other tasks available")
                        .font(.subheadline)
                        .foregroundStyle(Color("TextTertiary"))
                } else {
                    ForEach(availableTasks) { task in
                        Button {
                            Task { await addDependency(on: task.id) }
                        } label: {
                            HStack {
                                VStack(alignment: .leading) {
                                    Text(task.title)
                                        .font(.subheadline)
                                        .foregroundStyle(Color("TextPrimary"))
                                    StatusBadge(status: task.status)
                                }
                                Spacer()
                                Image(systemName: "plus.circle")
                                    .foregroundStyle(Color("ForgeBlue"))
                            }
                        }
                    }
                }
            }

            if let error = errorMessage {
                Section {
                    Text(error)
                        .font(.caption)
                        .foregroundStyle(Color("Danger"))
                }
            }
        }
        .navigationTitle("Dependencies")
        .task { await load() }
    }

    private func load() async {
        guard let actorId = appState.currentUserId else { return }
        isLoading = true
        do {
            allTasks = try await taskService.listTasks(postingId: postingId, actorId: actorId)
            currentDeps = try await taskService.getDependencies(taskId: taskId)
        } catch {
            errorMessage = error.localizedDescription
        }
        isLoading = false
    }

    private func addDependency(on dependsOnId: UUID) async {
        guard let actorId = appState.currentUserId else { return }
        do {
            _ = try await taskService.addDependency(actorId: actorId, taskId: taskId, dependsOnTaskId: dependsOnId)
            await load()
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}
