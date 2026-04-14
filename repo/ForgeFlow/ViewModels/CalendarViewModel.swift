import Foundation
import SwiftUI

@Observable
final class CalendarViewModel {
    var postings: [ServicePosting] = []
    var selectedDate = Date()
    var isLoading = false
    var errorMessage: String?

    private let postingService: PostingService
    private let appState: AppState

    init(postingService: PostingService, appState: AppState) {
        self.postingService = postingService
        self.appState = appState
    }

    /// Dates that have postings due
    var datesWithPostings: Set<DateComponents> {
        let calendar = Calendar.current
        var dates = Set<DateComponents>()
        for posting in postings {
            let comps = calendar.dateComponents([.year, .month, .day], from: posting.dueDate)
            dates.insert(comps)
        }
        return dates
    }

    /// Postings due on the selected date
    var postingsForSelectedDate: [ServicePosting] {
        let calendar = Calendar.current
        return postings.filter { calendar.isDate($0.dueDate, inSameDayAs: selectedDate) }
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
}
