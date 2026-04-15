import Foundation
import Testing
@testable import ForgeFlow

// MARK: - CurrencyFormatter Tests

@Suite("CurrencyFormatter")
struct CurrencyFormatterTests {

    // MARK: Happy paths

    @Test func formatZeroCents() {
        #expect(CurrencyFormatter.format(cents: 0) == "$0.00")
    }

    @Test func formatOneCent() {
        #expect(CurrencyFormatter.format(cents: 1) == "$0.01")
    }

    @Test func formatNinetyNineCents() {
        #expect(CurrencyFormatter.format(cents: 99) == "$0.99")
    }

    @Test func formatExactDollar() {
        #expect(CurrencyFormatter.format(cents: 100) == "$1.00")
    }

    @Test func formatRoundThousand() {
        // $2,500.00
        #expect(CurrencyFormatter.format(cents: 250_000) == "$2,500.00")
    }

    @Test func formatOneMillion() {
        #expect(CurrencyFormatter.format(cents: 100_000_000) == "$1,000,000.00")
    }

    @Test func formatTwentyFiveDollars() {
        #expect(CurrencyFormatter.format(cents: 2_500) == "$25.00")
    }

    @Test func formatOddCents() {
        #expect(CurrencyFormatter.format(cents: 1_099) == "$10.99")
    }

    @Test func formatLargeBudget() {
        // $9,999.99
        #expect(CurrencyFormatter.format(cents: 999_999) == "$9,999.99")
    }

    @Test func formatConsistentWithDecimalConversion() {
        // Verify that the formatter correctly moves the decimal point
        let cents = 12_345
        let result = CurrencyFormatter.format(cents: cents)
        #expect(result.contains("123.45"))
    }

    @Test func formatAlwaysHasTwoDecimalPlaces() {
        // Whole-dollar amounts must still show ".00"
        let result = CurrencyFormatter.format(cents: 5_000)
        #expect(result.hasSuffix(".00"))
    }

    @Test func formatAlwaysHasDollarSign() {
        let result = CurrencyFormatter.format(cents: 100)
        #expect(result.hasPrefix("$"))
    }
}

// MARK: - PasswordHasher Tests

@Suite("PasswordHasher")
struct PasswordHasherTests {

    @Test func hashProducesNonEmptyString() {
        let hash = PasswordHasher.hash("ForgeFlow1")
        #expect(!hash.isEmpty)
    }

    @Test func hashHasThreeSegments() {
        // Format: "<iterations>$<salt_hex>$<hash_hex>"
        let hash = PasswordHasher.hash("password")
        let parts = hash.split(separator: "$")
        #expect(parts.count == 3)
    }

    @Test func hashIterationsField() {
        let hash = PasswordHasher.hash("password")
        let parts = hash.split(separator: "$")
        let iters = Int(parts[0])
        #expect(iters != nil)
        #expect(iters! > 0)
    }

    @Test func verifyCorrectPasswordSucceeds() {
        let password = "Secur3Pass!"
        let hash = PasswordHasher.hash(password)
        #expect(PasswordHasher.verify(password, against: hash) == true)
    }

    @Test func verifyWrongPasswordFails() {
        let hash = PasswordHasher.hash("CorrectPass1")
        #expect(PasswordHasher.verify("WrongPass99", against: hash) == false)
    }

    @Test func verifyEmptyStringFails() {
        let hash = PasswordHasher.hash("NonEmpty1")
        #expect(PasswordHasher.verify("", against: hash) == false)
    }

    @Test func hashesAreDifferentForSamePassword() {
        // Each call uses a fresh random salt
        let hash1 = PasswordHasher.hash("SamePass1")
        let hash2 = PasswordHasher.hash("SamePass1")
        #expect(hash1 != hash2)
    }

    @Test func verifyBothHashesForSamePassword() {
        let password = "SamePass1"
        let hash1 = PasswordHasher.hash(password)
        let hash2 = PasswordHasher.hash(password)
        // Each independent hash must verify correctly
        #expect(PasswordHasher.verify(password, against: hash1) == true)
        #expect(PasswordHasher.verify(password, against: hash2) == true)
    }

    @Test func verifyBadlyFormattedHashReturnsFalse() {
        #expect(PasswordHasher.verify("anything", against: "not_a_valid_hash") == false)
    }

    @Test func verifyEmptyStoredHashReturnsFalse() {
        #expect(PasswordHasher.verify("password", against: "") == false)
    }
}
