import SwiftUI

struct PostingRowView: View {
    let posting: ServicePosting

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(posting.title)
                .font(.body)
                .fontWeight(.medium)
                .foregroundStyle(Color("TextPrimary"))
                .lineLimit(2)

            Text(posting.siteAddress)
                .font(.caption)
                .foregroundStyle(Color("TextSecondary"))
                .lineLimit(1)

            HStack(spacing: 12) {
                DueDateLabel(date: posting.dueDate)
                BudgetLabel(cents: posting.budgetCapCents)
                Spacer()
                StatusBadge(status: posting.status)
            }
        }
        .padding(.vertical, 4)
        .accessibilityElement(children: .combine)
    }
}
