import Foundation
import CryptoKit

enum HashValidator {
    /// Computes SHA-256 hash of the given data and returns the digest bytes.
    static func sha256(data: Data) -> [UInt8] {
        let digest = SHA256.hash(data: data)
        return Array(digest)
    }

    /// Computes SHA-256 hash and returns it as a hex string.
    static func sha256Hex(data: Data) -> String {
        let bytes = sha256(data: data)
        return bytes.map { String(format: "%02x", $0) }.joined()
    }

    /// Computes SHA-256 hash of a file at the given URL.
    static func sha256Hex(fileURL: URL) throws -> String {
        let data = try Data(contentsOf: fileURL)
        return sha256Hex(data: data)
    }

    /// Validates that a file's SHA-256 matches the expected hash.
    static func validate(fileURL: URL, expectedHash: String) throws -> Bool {
        let computed = try sha256Hex(fileURL: fileURL)
        return computed == expectedHash
    }
}
