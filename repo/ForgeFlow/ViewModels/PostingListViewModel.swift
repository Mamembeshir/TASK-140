import Foundation
import SwiftUI

@Observable
final class PostingListViewModel {
    var postings: [ServicePosting] = []
    var isLoading = false
    var errorMessage: String?
    var statusFilter: PostingStatus?

    private let postingService: PostingService
    private let appState: AppState

    init(postingService: PostingService, appState: AppState) {
        self.postingService = postingService
        self.appState = appState
    }

    var filteredPostings: [ServicePosting] {
        guard let filter = statusFilter else { return postings }
        return postings.filter { $0.status == filter }
    }

    func loadPostings() async {
        guard let role = appState.currentUserRole, let userId = appState.currentUserId else { return }
        isLoading = true
        do {
            postings = try await postingService.listPostings(role: role, userId: userId)
        } catch {
            errorMessage = error.localizedDescription
        }
        isLoading = false
    }

    func cancelPosting(_ postingId: UUID) async {
        guard let actorId = appState.currentUserId else { return }
        do {
            _ = try await postingService.cancel(actorId: actorId, postingId: postingId)
            await loadPostings()
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}
