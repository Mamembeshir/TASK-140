import SwiftUI

struct NotificationBadge: View {
    let count: Int

    var body: some View {
        ZStack(alignment: .topTrailing) {
            Image(systemName: "bell.fill")
                .imageScale(.large)

            if count > 0 {
                Text(count < 100 ? "\(count)" : "99+")
                    .font(.system(size: 9, weight: .bold))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 4)
                    .padding(.vertical, 2)
                    .background(Color("Danger"), in: Capsule())
                    .offset(x: 8, y: -6)
            }
        }
    }
}
