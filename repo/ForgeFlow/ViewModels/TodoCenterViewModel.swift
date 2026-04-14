import Foundation
import SwiftUI

@Observable
final class TodoCenterViewModel {
    var tasks: [ForgeTask] = []
    var postings: [ServicePosting] = []
    var isLoading = false
    var errorMessage: String?

    private let taskService: TaskService
    private let postingService: PostingService
    private let appState: AppState

    init(taskService: TaskService, postingService: PostingService, appState: AppState) {
        self.taskService = taskService
        self.postingService = postingService
        self.appState = appState
    }

    /// Tasks grouped by posting, sorted by priority (P0 first)
    var tasksByPosting: [(posting: ServicePosting, tasks: [ForgeTask])] {
        let taskMap = Dictionary(grouping: activeTasks, by: { $0.postingId })
        return postings.compactMap { posting in
            guard let postingTasks = taskMap[posting.id], !postingTasks.isEmpty else { return nil }
            let sorted = postingTasks.sorted { $0.priority.rawValue < $1.priority.rawValue }
            return (posting: posting, tasks: sorted)
        }
    }

    private var activeTasks: [ForgeTask] {
        tasks.filter { $0.status != .done }
    }

    func loadTodaysTasks() async {
        guard let userId = appState.currentUserId,
              let role = appState.currentUserRole else { return }
        isLoading = true
        do {
            if role == .technician {
                tasks = try await taskService.listTasksForUser(userId: userId, actorId: userId)
            } else {
                // Admin/Coordinator see all tasks from their postings
                let allPostings = try await postingService.listPostings(role: role, userId: userId)
                var allTasks: [ForgeTask] = []
                for posting in allPostings {
                    let postingTasks = try await taskService.listTasks(postingId: posting.id, actorId: userId)
                    allTasks.append(contentsOf: postingTasks)
                }
                tasks = allTasks
            }
            postings = try await postingService.listPostings(
                role: role, userId: userId
            )
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
            await loadTodaysTasks()
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}
