import Foundation
import CryptoKit
import CommonCrypto

/// PBKDF2-based password hashing with per-user salt.
/// Stored format: "<iterations>$<salt_hex>$<hash_hex>"
enum PasswordHasher {
    private static let iterations = 100_000
    private static let saltLength = 16
    private static let keyLength = 32 // 256 bits

    /// Hashes a password with a random salt using PBKDF2-SHA256.
    /// Returns "<iterations>$<salt_hex>$<hash_hex>".
    static func hash(_ password: String) -> String {
        let salt = randomSalt()
        let derived = derive(password: password, salt: salt, iterations: iterations)
        let saltHex = salt.map { String(format: "%02x", $0) }.joined()
        let hashHex = derived.map { String(format: "%02x", $0) }.joined()
        return "\(iterations)$\(saltHex)$\(hashHex)"
    }

    /// Verifies a password against a stored hash string.
    static func verify(_ password: String, against stored: String) -> Bool {
        let parts = stored.split(separator: "$")
        guard parts.count == 3,
              let iters = Int(parts[0]),
              let salt = hexToBytes(String(parts[1])),
              let expectedHash = hexToBytes(String(parts[2])) else {
            // Fallback: check as legacy plain SHA-256 hex
            return HashValidator.sha256Hex(data: password.data(using: .utf8)!) == stored
        }

        let derived = derive(password: password, salt: salt, iterations: iters)
        return derived == expectedHash
    }

    // MARK: - Private

    private static func randomSalt() -> [UInt8] {
        var salt = [UInt8](repeating: 0, count: saltLength)
        _ = SecRandomCopyBytes(kSecRandomDefault, saltLength, &salt)
        return salt
    }

    private static func derive(password: String, salt: [UInt8], iterations: Int) -> [UInt8] {
        let passwordData = password.data(using: .utf8)!
        var derivedKey = [UInt8](repeating: 0, count: keyLength)

        derivedKey.withUnsafeMutableBufferPointer { derivedKeyPtr in
            salt.withUnsafeBufferPointer { saltPtr in
                passwordData.withUnsafeBytes { passwordPtr in
                    CCKeyDerivationPBKDF(
                        CCPBKDFAlgorithm(kCCPBKDF2),
                        passwordPtr.baseAddress?.assumingMemoryBound(to: Int8.self),
                        passwordData.count,
                        saltPtr.baseAddress,
                        salt.count,
                        CCPseudoRandomAlgorithm(kCCPRFHmacAlgSHA256),
                        UInt32(iterations),
                        derivedKeyPtr.baseAddress,
                        keyLength
                    )
                }
            }
        }

        return derivedKey
    }

    private static func hexToBytes(_ hex: String) -> [UInt8]? {
        var bytes: [UInt8] = []
        var index = hex.startIndex
        while index < hex.endIndex {
            guard let nextIndex = hex.index(index, offsetBy: 2, limitedBy: hex.endIndex) else { return nil }
            guard let byte = UInt8(hex[index..<nextIndex], radix: 16) else { return nil }
            bytes.append(byte)
            index = nextIndex
        }
        return bytes.isEmpty ? nil : bytes
    }
}
