import SwiftUI

struct ConfirmationButton: View {
    let title: String
    let role: ButtonRole?
    let confirmTitle: String
    let confirmMessage: String
    let action: () -> Void

    @State private var showConfirmation = false

    init(
        title: String,
        role: ButtonRole? = .destructive,
        confirmTitle: String = "Are you sure?",
        confirmMessage: String = "This action cannot be undone.",
        action: @escaping () -> Void
    ) {
        self.title = title
        self.role = role
        self.confirmTitle = confirmTitle
        self.confirmMessage = confirmMessage
        self.action = action
    }

    var body: some View {
        Button(role: role) {
            showConfirmation = true
        } label: {
            Text(title)
        }
        .confirmationDialog(confirmTitle, isPresented: $showConfirmation, titleVisibility: .visible) {
            Button(title, role: role, action: action)
            Button("Cancel", role: .cancel) {}
        } message: {
            Text(confirmMessage)
        }
    }
}

#Preview {
    ConfirmationButton(
        title: "Cancel Posting",
        confirmTitle: "Cancel this posting?",
        confirmMessage: "This will cancel the posting and notify all assigned technicians.",
        action: {}
    )
    .padding()
}
