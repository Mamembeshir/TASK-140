import SwiftUI

struct StatusBadge: View {
    let label: String
    let foregroundColor: Color
    let backgroundColor: Color

    init(status: PostingStatus) {
        self.label = switch status {
        case .draft: "Draft"
        case .open: "Open"
        case .inProgress: "In Progress"
        case .completed: "Completed"
        case .cancelled: "Cancelled"
        }

        switch status {
        case .draft:
            self.foregroundColor = Color("TextTertiary")
            self.backgroundColor = Color("SurfaceSunken")
        case .open:
            self.foregroundColor = Color("InfoBlue")
            self.backgroundColor = Color("InfoBlue").opacity(0.15)
        case .inProgress:
            self.foregroundColor = Color("Warning")
            self.backgroundColor = Color("Warning").opacity(0.15)
        case .completed:
            self.foregroundColor = Color("Success")
            self.backgroundColor = Color("Success").opacity(0.15)
        case .cancelled:
            self.foregroundColor = Color("Danger")
            self.backgroundColor = Color("Danger").opacity(0.15)
        }
    }

    init(status: TaskStatus) {
        self.label = switch status {
        case .notStarted: "Not Started"
        case .inProgress: "In Progress"
        case .blocked: "Blocked"
        case .done: "Done"
        }

        switch status {
        case .notStarted:
            self.foregroundColor = Color("TextTertiary")
            self.backgroundColor = Color("SurfaceSunken")
        case .inProgress:
            self.foregroundColor = Color("Warning")
            self.backgroundColor = Color("Warning").opacity(0.15)
        case .blocked:
            self.foregroundColor = Color("Danger")
            self.backgroundColor = Color("Danger").opacity(0.15)
        case .done:
            self.foregroundColor = Color("Success")
            self.backgroundColor = Color("Success").opacity(0.15)
        }
    }

    init(status: AssignmentStatus) {
        self.label = switch status {
        case .invited: "Invited"
        case .accepted: "Accepted"
        case .declined: "Declined"
        case .completed: "Completed"
        }

        switch status {
        case .invited:
            self.foregroundColor = Color("InfoBlue")
            self.backgroundColor = Color("InfoBlue").opacity(0.15)
        case .accepted:
            self.foregroundColor = Color("Success")
            self.backgroundColor = Color("Success").opacity(0.15)
        case .declined:
            self.foregroundColor = Color("Danger")
            self.backgroundColor = Color("Danger").opacity(0.15)
        case .completed:
            self.foregroundColor = Color("Success")
            self.backgroundColor = Color("Success").opacity(0.15)
        }
    }

    init(status: PluginStatus) {
        self.label = switch status {
        case .draft: "Draft"
        case .testing: "Testing"
        case .pendingApproval: "Pending Approval"
        case .approved: "Approved"
        case .rejected: "Rejected"
        case .active: "Active"
        }

        switch status {
        case .draft:
            self.foregroundColor = Color("TextTertiary")
            self.backgroundColor = Color("SurfaceSunken")
        case .testing:
            self.foregroundColor = Color("InfoBlue")
            self.backgroundColor = Color("InfoBlue").opacity(0.15)
        case .pendingApproval:
            self.foregroundColor = Color("Warning")
            self.backgroundColor = Color("Warning").opacity(0.15)
        case .approved:
            self.foregroundColor = Color("Success")
            self.backgroundColor = Color("Success").opacity(0.15)
        case .rejected:
            self.foregroundColor = Color("Danger")
            self.backgroundColor = Color("Danger").opacity(0.15)
        case .active:
            self.foregroundColor = Color("Success")
            self.backgroundColor = Color("Success").opacity(0.15)
        }
    }

    var body: some View {
        Text(label)
            .font(.caption2)
            .fontWeight(.bold)
            .foregroundStyle(foregroundColor)
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(backgroundColor, in: Capsule())
    }
}

#Preview {
    VStack(spacing: 12) {
        StatusBadge(status: PostingStatus.draft)
        StatusBadge(status: PostingStatus.open)
        StatusBadge(status: PostingStatus.inProgress)
        StatusBadge(status: PostingStatus.completed)
        StatusBadge(status: PostingStatus.cancelled)
        StatusBadge(status: TaskStatus.blocked)
    }
    .padding()
}
