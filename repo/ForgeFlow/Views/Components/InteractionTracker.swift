import SwiftUI

/// Detects user interaction (taps, drags) and refreshes the inactivity timer.
struct InteractionTrackingModifier: ViewModifier {
    let appState: AppState

    func body(content: Content) -> some View {
        content
            .simultaneousGesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { _ in appState.recordInteraction() }
            )
            .onReceive(NotificationCenter.default.publisher(for: UIResponder.keyboardDidShowNotification)) { _ in
                appState.recordInteraction()
            }
    }
}

extension View {
    func trackingInteraction(appState: AppState) -> some View {
        modifier(InteractionTrackingModifier(appState: appState))
    }
}
