import SwiftUI

struct PriorityBadge: View {
    let priority: Priority

    private var color: Color {
        switch priority {
        case .p0: return Color("P0Critical")
        case .p1: return Color("P1High")
        case .p2: return Color("P2Medium")
        case .p3: return Color("P3Low")
        }
    }

    var body: some View {
        Text("\(priority.rawValue) \(priority.label)")
            .font(.caption2)
            .fontWeight(.bold)
            .foregroundStyle(color)
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(color.opacity(0.15), in: Capsule())
    }
}

#Preview {
    VStack(spacing: 12) {
        PriorityBadge(priority: .p0)
        PriorityBadge(priority: .p1)
        PriorityBadge(priority: .p2)
        PriorityBadge(priority: .p3)
    }
    .padding()
}
