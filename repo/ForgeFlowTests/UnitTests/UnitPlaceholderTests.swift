import Foundation
import Testing
@testable import ForgeFlow

@Suite("Unit Tests")
struct UnitTests {
    @Test("Currency formatter formats cents correctly")
    func currencyFormatterBasic() {
        #expect(CurrencyFormatter.format(cents: 250000) == "$2,500.00")
        #expect(CurrencyFormatter.format(cents: 99) == "$0.99")
        #expect(CurrencyFormatter.format(cents: 0) == "$0.00")
    }
}
