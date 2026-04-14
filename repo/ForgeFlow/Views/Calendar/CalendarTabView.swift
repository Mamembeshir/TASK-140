import SwiftUI

struct CalendarTabView: View {
    @State private var selectedView: CalendarSubView = .calendar

    let postingService: PostingService
    let assignmentService: AssignmentService
    let authService: AuthService
    let taskService: TaskService
    let appState: AppState

    enum CalendarSubView: String, CaseIterable {
        case calendar = "Calendar"
        case todo = "To-Do"
    }

    var body: some View {
        VStack(spacing: 0) {
            Picker("View", selection: $selectedView) {
                ForEach(CalendarSubView.allCases, id: \.self) { view in
                    Text(view.rawValue).tag(view)
                }
            }
            .pickerStyle(.segmented)
            .padding(.horizontal)
            .padding(.top, 8)

            switch selectedView {
            case .calendar:
                CalendarView(
                    postingService: postingService,
                    assignmentService: assignmentService,
                    authService: authService,
                    appState: appState
                )
            case .todo:
                TodoCenterView(
                    taskService: taskService,
                    postingService: postingService,
                    appState: appState
                )
            }
        }
        .navigationTitle("Calendar")
        .background(Color("SurfacePrimary"))
    }
}
