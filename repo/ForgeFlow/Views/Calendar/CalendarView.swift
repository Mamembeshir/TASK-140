import SwiftUI

struct CalendarView: View {
    @State private var viewModel: CalendarViewModel

    private let postingService: PostingService
    private let assignmentService: AssignmentService
    private let authService: AuthService
    private let appState: AppState

    init(postingService: PostingService, assignmentService: AssignmentService,
         authService: AuthService, appState: AppState) {
        self.postingService = postingService
        self.assignmentService = assignmentService
        self.authService = authService
        self.appState = appState
        _viewModel = State(initialValue: CalendarViewModel(
            postingService: postingService, appState: appState
        ))
    }

    var body: some View {
        VStack(spacing: 0) {
            // Calendar picker
            DatePicker(
                "Select Date",
                selection: $viewModel.selectedDate,
                displayedComponents: .date
            )
            .datePickerStyle(.graphical)
            .tint(Color("ForgeBlue"))
            .padding(.horizontal)

            Divider()

            // Postings for selected date
            if viewModel.postingsForSelectedDate.isEmpty {
                Spacer()
                VStack(spacing: 8) {
                    Image(systemName: "calendar.badge.minus")
                        .font(.system(size: 32))
                        .foregroundStyle(Color("TextTertiary"))
                    Text("No postings on this date")
                        .font(.subheadline)
                        .foregroundStyle(Color("TextSecondary"))
                }
                Spacer()
            } else {
                List {
                    ForEach(viewModel.postingsForSelectedDate) { posting in
                        NavigationLink {
                            PostingDetailView(
                                postingId: posting.id,
                                postingService: postingService,
                                assignmentService: assignmentService,
                                authService: authService,
                                appState: appState
                            )
                        } label: {
                            PostingRowView(posting: posting)
                        }
                    }
                }
                .listStyle(.plain)
            }
        }
        .navigationTitle("Calendar")
        .background(Color("SurfacePrimary"))
        .task { await viewModel.loadPostings() }
        .refreshable { await viewModel.loadPostings() }
    }
}
