import Foundation
import SwiftUI

@Observable
final class PostingDetailViewModel {
    var posting: ServicePosting?
    var assignments: [Assignment] = []
    var tasks: [ForgeTask] = []
    var isLoading = false
    var errorMessage: String?

    let postingId: UUID
    private let postingService: PostingService
    private let assignmentService: AssignmentService
    private let appState: AppState

    init(postingId: UUID, postingService: PostingService, assignmentService: AssignmentService, appState: AppState) {
        self.postingId = postingId
        self.postingService = postingService
        self.assignmentService = assignmentService
        self.appState = appState
    }

    var currentRole: Role? { appState.currentUserRole }
    var currentUserId: UUID? { appState.currentUserId }

    var currentAssignment: Assignment? {
        guard let userId = currentUserId else { return nil }
        return assignments.first { $0.technicianId == userId }
    }

    var canPublish: Bool {
        posting?.status == .draft && (currentRole == .admin || currentRole == .coordinator)
    }

    var canCancel: Bool {
        guard let status = posting?.status else { return false }
        return (status == .draft || status == .open || status == .inProgress)
            && (currentRole == .admin || currentRole == .coordinator)
    }

    var canAccept: Bool {
        guard currentRole == .technician else { return false }
        guard posting?.status == .open || posting?.status == .inProgress else { return false }
        if posting?.acceptanceMode == .inviteOnly {
            return currentAssignment?.status == .invited
        }
        // OPEN: can accept if no current assignment
        return currentAssignment == nil
    }

    var canDecline: Bool {
        currentRole == .technician && currentAssignment?.status == .invited
    }

    var canInvite: Bool {
        posting?.acceptanceMode == .inviteOnly
            && posting?.status == .open
            && (currentRole == .admin || currentRole == .coordinator)
    }

    func load() async {
        guard let actorId = currentUserId else { return }
        isLoading = true
        do {
            posting = try await postingService.getPosting(id: postingId, actorId: actorId)
            assignments = try await assignmentService.listAssignments(postingId: postingId, actorId: actorId)
            if let actorId = currentUserId {
                tasks = try await postingService.listTasks(postingId: postingId, actorId: actorId)
            }
        } catch {
            errorMessage = error.localizedDescription
        }
        isLoading = false
    }

    func publish() async {
        guard let actorId = currentUserId else { return }
        do {
            _ = try await postingService.publish(actorId: actorId, postingId: postingId)
            await load()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func cancel() async {
        guard let actorId = currentUserId else { return }
        do {
            _ = try await postingService.cancel(actorId: actorId, postingId: postingId)
            await load()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func acceptAssignment() async {
        guard let userId = currentUserId else { return }
        do {
            _ = try await assignmentService.accept(actorId: userId, postingId: postingId, technicianId: userId)
            await load()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func declineAssignment() async {
        guard let userId = currentUserId else { return }
        do {
            _ = try await assignmentService.decline(actorId: userId, postingId: postingId, technicianId: userId)
            await load()
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}
