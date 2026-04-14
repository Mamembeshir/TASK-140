import SwiftUI

struct AdaptiveGrid<Content: View>: View {
    let minColumnWidth: CGFloat
    let spacing: CGFloat
    @ViewBuilder let content: () -> Content

    init(
        minColumnWidth: CGFloat = 320,
        spacing: CGFloat = 16,
        @ViewBuilder content: @escaping () -> Content
    ) {
        self.minColumnWidth = minColumnWidth
        self.spacing = spacing
        self.content = content
    }

    var body: some View {
        LazyVGrid(
            columns: [GridItem(.adaptive(minimum: minColumnWidth), spacing: spacing)],
            spacing: spacing
        ) {
            content()
        }
    }
}

#Preview {
    ScrollView {
        AdaptiveGrid {
            ForEach(0..<6) { index in
                RoundedRectangle(cornerRadius: 12)
                    .fill(Color("SurfaceElevated"))
                    .frame(height: 120)
                    .overlay {
                        Text("Card \(index + 1)")
                            .foregroundStyle(Color("TextPrimary"))
                    }
                    .shadow(radius: 4, y: 2)
            }
        }
        .padding()
    }
}
