import Foundation

enum CurrencyFormatter {
    private static let formatter: NumberFormatter = {
        let f = NumberFormatter()
        f.numberStyle = .currency
        f.currencyCode = "USD"
        f.currencySymbol = "$"
        f.minimumFractionDigits = 2
        f.maximumFractionDigits = 2
        return f
    }()

    /// Formats integer cents to a currency string.
    /// Example: `250000` → `"$2,500.00"`
    static func format(cents: Int) -> String {
        let dollars = Decimal(cents) / 100
        return formatter.string(from: dollars as NSDecimalNumber) ?? "$0.00"
    }
}
