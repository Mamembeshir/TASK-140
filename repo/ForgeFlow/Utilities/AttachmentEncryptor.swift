import Foundation
import CryptoKit

/// AES-256-GCM encryption/decryption for watermarked attachment originals.
/// Uses a random per-file data key protected by a Keychain-backed master key.
enum AttachmentEncryptor {

    private static let masterKeyTag = "com.forgeflow.app.master-encryption-key"

    /// Gets or creates the master key stored in Keychain.
    private static func masterKey() throws -> SymmetricKey {
        // Try to load existing master key from Keychain
        if let data = KeychainHelper.load(forKey: masterKeyTag) {
            return SymmetricKey(data: data)
        }
        // Generate and store a new random master key
        let key = SymmetricKey(size: .bits256)
        let keyData = key.withUnsafeBytes { Data($0) }
        try KeychainHelper.save(data: keyData, forKey: masterKeyTag)
        return key
    }

    /// Derives a per-file key using HKDF with the master key and file ID as info.
    private static func deriveKey(fileId: UUID) throws -> SymmetricKey {
        let master = try masterKey()
        let info = Data("ForgeFlow.file.\(fileId.uuidString)".utf8)
        let derived = HKDF<SHA256>.deriveKey(
            inputKeyMaterial: master,
            info: info,
            outputByteCount: 32
        )
        return derived
    }

    /// Encrypts data using AES-256-GCM. Returns combined nonce + ciphertext + tag.
    static func encrypt(data: Data, fileId: UUID) throws -> Data {
        let key = try deriveKey(fileId: fileId)
        let sealedBox = try AES.GCM.seal(data, using: key)
        guard let combined = sealedBox.combined else {
            throw AttachmentError.compressionFailed
        }
        return combined
    }

    /// Decrypts AES-256-GCM combined data (nonce + ciphertext + tag).
    static func decrypt(combinedData: Data, fileId: UUID) throws -> Data {
        let key = try deriveKey(fileId: fileId)
        let sealedBox = try AES.GCM.SealedBox(combined: combinedData)
        return try AES.GCM.open(sealedBox, using: key)
    }
}
