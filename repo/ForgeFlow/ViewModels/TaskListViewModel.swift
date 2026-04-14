import Foundation
import SwiftUI

@Observable
final class TaskListViewModel {
    var tasks: [ForgeTask] = []
    var isLoading = false
    var errorMessage: String?

    let postingId: UUID
    private let taskService: TaskService
    private let appState: AppState

    init(postingId: UUID, taskService: TaskService, appState: AppState) {
        self.postingId = postingId
        self.taskService = taskService
        self.appState = appState
    }

    var parentTasks: [ForgeTask] { tasks.filter { $0.parentTaskId == nil } }

    func subtasks(for parentId: UUID) -> [ForgeTask] {
        tasks.filter { $0.parentTaskId == parentId }
    }

    func loadTasks() async {
        guard let actorId = appState.currentUserId else { return }
        isLoading = true
        do {
            tasks = try await taskService.listTasks(postingId: postingId, actorId: actorId)
        } catch {
            errorMessage = error.localizedDescription
        }
        isLoading = false
    }

    func updateStatus(taskId: UUID, newStatus: TaskStatus, blockedComment: String? = nil) async {
        guard let actorId = appState.currentUserId else { return }
        do {
            _ = try await taskService.updateStatus(
                actorId: actorId, taskId: taskId,
                newStatus: newStatus, blockedComment: blockedComment
            )
            await loadTasks()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func createSubtask(parentTaskId: UUID, title: String, priority: Priority, assignedTo: UUID?) async {
        guard let actorId = appState.currentUserId else { return }
        do {
            _ = try await taskService.createSubtask(
                actorId: actorId, parentTaskId: parentTaskId,
                title: title, priority: priority, assignedTo: assignedTo
            )
            await loadTasks()
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}
