import SwiftUI

struct NotificationRowView: View {
    let notification: ForgeNotification
    var onMarkSeen: (() -> Void)?

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            // Status indicator
            statusDot

            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    Text(notification.eventType.displayName)
                        .font(.caption)
                        .fontWeight(.semibold)
                        .foregroundStyle(Color("ForgeBlue"))

                    Spacer()

                    Text(DateFormatters.relative.localizedString(
                        for: notification.createdAt, relativeTo: Date()
                    ))
                    .font(.caption2)
                    .foregroundStyle(Color("TextTertiary"))
                }

                Text(notification.title)
                    .font(.subheadline)
                    .fontWeight(notification.status == .delivered ? .semibold : .regular)
                    .foregroundStyle(Color("TextPrimary"))

                Text(notification.body)
                    .font(.caption)
                    .foregroundStyle(Color("TextSecondary"))
                    .lineLimit(2)
            }
        }
        .padding(.vertical, 4)
        .swipeActions(edge: .trailing) {
            if notification.status == .delivered {
                Button {
                    onMarkSeen?()
                } label: {
                    Label("Mark Seen", systemImage: "checkmark.circle.fill")
                }
                .tint(Color("Success"))
            }
        }
    }

    private var statusDot: some View {
        Group {
            switch notification.status {
            case .pending:
                Image(systemName: "clock.fill")
                    .font(.caption2)
                    .foregroundStyle(Color("TextTertiary"))
            case .delivered:
                Circle()
                    .fill(Color("ForgeBlue"))
                    .frame(width: 8, height: 8)
            case .seen:
                Image(systemName: "checkmark.circle.fill")
                    .font(.caption2)
                    .foregroundStyle(Color("TextTertiary"))
            }
        }
        .frame(width: 16, height: 16)
        .padding(.top, 3)
    }
}
