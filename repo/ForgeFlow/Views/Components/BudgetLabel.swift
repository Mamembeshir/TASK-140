import SwiftUI

struct BudgetLabel: View {
    let cents: Int

    var body: some View {
        Text(CurrencyFormatter.format(cents: cents))
            .font(.subheadline)
            .fontWeight(.semibold)
            .foregroundStyle(Color("TextPrimary"))
            .accessibilityLabel("Budget: \(CurrencyFormatter.format(cents: cents))")
    }
}

#Preview {
    VStack(spacing: 12) {
        BudgetLabel(cents: 250000)
        BudgetLabel(cents: 99)
        BudgetLabel(cents: 1000000)
    }
    .padding()
}
