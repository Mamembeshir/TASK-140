import SwiftUI

struct EmptyStateView: View {
    let icon: String
    let heading: String
    let description: String
    var actionTitle: String?
    var action: (() -> Void)?

    var body: some View {
        VStack(spacing: 16) {
            Image(systemName: icon)
                .font(.system(size: 48))
                .foregroundStyle(Color("TextTertiary"))

            Text(heading)
                .font(.title3)
                .fontWeight(.semibold)
                .foregroundStyle(Color("TextPrimary"))

            Text(description)
                .font(.subheadline)
                .foregroundStyle(Color("TextSecondary"))
                .multilineTextAlignment(.center)
                .frame(maxWidth: 280)

            if let actionTitle, let action {
                Button(action: action) {
                    Text(actionTitle)
                        .fontWeight(.bold)
                        .foregroundStyle(.white)
                        .padding(.horizontal, 24)
                        .padding(.vertical, 12)
                        .background(Color("ForgeBlue"), in: RoundedRectangle(cornerRadius: 10))
                }
                .padding(.top, 8)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding()
    }
}

#Preview {
    EmptyStateView(
        icon: "doc.text.magnifyingglass",
        heading: "No Postings Yet",
        description: "Create your first service posting to get started.",
        actionTitle: "Create Posting",
        action: {}
    )
}
