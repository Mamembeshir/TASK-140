import SwiftUI

/// Refreshes the inactivity timer on keyboard activity and scene activation.
/// Navigation-safe: does NOT use any gesture recognizer that could interfere
/// with NavigationLink, Button, or ScrollView touches.
struct InteractionTrackingModifier: ViewModifier {
    let appState: AppState

    func body(content: Content) -> some View {
        content
            .onReceive(NotificationCenter.default.publisher(
                for: UIResponder.keyboardDidShowNotification
            )) { _ in
                appState.recordInteraction()
            }
    }
}

extension View {
    func trackingInteraction(appState: AppState) -> some View {
        modifier(InteractionTrackingModifier(appState: appState))
    }
}
