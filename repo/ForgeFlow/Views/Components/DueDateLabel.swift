import SwiftUI

struct DueDateLabel: View {
    let date: Date

    private var isOverdue: Bool {
        date < Date()
    }

    var body: some View {
        HStack(spacing: 4) {
            Image(systemName: isOverdue ? "exclamationmark.triangle.fill" : "calendar")
                .font(.caption)
            Text(DateFormatters.display.string(from: date))
                .font(.subheadline)
        }
        .foregroundStyle(isOverdue ? Color("Danger") : Color("TextSecondary"))
        .accessibilityLabel(
            isOverdue
                ? "Overdue: \(DateFormatters.display.string(from: date))"
                : "Due: \(DateFormatters.display.string(from: date))"
        )
    }
}

#Preview {
    VStack(spacing: 12) {
        DueDateLabel(date: Date().addingTimeInterval(86400 * 7))
        DueDateLabel(date: Date().addingTimeInterval(-86400))
    }
    .padding()
}
