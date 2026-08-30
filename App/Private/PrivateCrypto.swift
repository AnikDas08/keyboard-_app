// PrivateCrypto.swift
// Locally-encrypted envelope compatible with Android:
//   ananse-aesgcm-v1.NONCE.CIPHERTEXT_TAG
// where NONCE and CIPHERTEXT_TAG are unpadded base64url,
// using a raw 32-byte key and AES-GCM.
// No plaintext ever leaves this device over the network.

import CryptoKit
import Foundation

/// Validate untrusted relay routing metadata before attempting decryption.
func shouldAcceptLiveEnvelope(
    id: String,
    senderUserId: String,
    recipientUserId: String,
    activeContactId: String,
    myUserId: String,
    seenIds: Set<String>
) -> Bool {
    !id.isEmpty &&
        senderUserId == activeContactId &&
        recipientUserId == myUserId &&
        !seenIds.contains(id)
}

/// Resolve only the pending key whose ID exactly matches the contact's current
/// invite. The caller uses the returned material to replace any existing key.
func matchingPendingConversationKey(
    contactInviteKeyId: String?,
    loadPendingKey: (String) -> Data?
) -> (keyId: String, key: Data)? {
    guard let keyId = contactInviteKeyId,
          let key = loadPendingKey(keyId) else { return nil }
    return (keyId, key)
}

enum PrivateCrypto {

    static let prefix = "ananse-aesgcm-v1"

    // MARK: - Key generation

    /// Generate a new random 32-byte symmetric key.
    static func generateConversationKey() -> Data {
        SymmetricKey(size: .bits256).withUnsafeBytes { Data($0) }
    }

    // MARK: - Invite key id

    /// SHA-256 hex of the raw invite token — the server's `inviteKeyId`.
    /// Used to match the pending conversation key stashed at invite time to
    /// the contact that later appears in the list.
    static func inviteKeyId(forToken token: String) -> String {
        let digest = SHA256.hash(data: Data(token.utf8))
        return digest.map { String(format: "%02x", $0) }.joined()
    }

    // MARK: - Encrypt

    /// Encrypt `plaintext` using the given 32-byte `key`.
    /// Returns the full envelope string ready to send as the payload.
    static func encrypt(plaintext: Data, key: Data) throws -> String {
        guard key.count == 32 else { throw CryptoError.invalidKeySize }
        let symKey = SymmetricKey(data: key)

        // AES-GCM with a random 12-byte nonce
        let nonce = AES.GCM.Nonce()
        let sealed = try AES.GCM.seal(plaintext, using: symKey, nonce: nonce)

        // combined = ciphertext || tag (AES.GCM.SealedBox.combined excludes nonce)
        guard let combined = sealed.combined else { throw CryptoError.sealFailed }
        // combined layout from CryptoKit: nonce(12) | ciphertext | tag(16)
        // We want just ciphertext+tag (without the nonce prefix that CryptoKit prepends)
        let ciphertextAndTag = combined.dropFirst(12) // skip the 12-byte nonce prefix

        let nonceB64   = base64url(Data(nonce))
        let ctB64      = base64url(Data(ciphertextAndTag))
        return "\(prefix).\(nonceB64).\(ctB64)"
    }

    /// Deterministic entry point for executable interoperability vectors only.
    static func encrypt(plaintext: Data, key: Data, nonceData: Data) throws -> String {
        guard key.count == 32 else { throw CryptoError.invalidKeySize }
        guard nonceData.count == 12 else { throw CryptoError.malformedEnvelope }
        let nonce = try AES.GCM.Nonce(data: nonceData)
        let sealed = try AES.GCM.seal(plaintext, using: SymmetricKey(data: key), nonce: nonce)
        guard let combined = sealed.combined else { throw CryptoError.sealFailed }
        return "\(prefix).\(base64url(nonceData)).\(base64url(Data(combined.dropFirst(12))))"
    }

    // MARK: - Decrypt

    /// Decrypt a full envelope string using the given 32-byte `key`.
    static func decrypt(envelope: String, key: Data) throws -> Data {
        guard key.count == 32 else { throw CryptoError.invalidKeySize }

        let parts = envelope.split(separator: ".", maxSplits: 2, omittingEmptySubsequences: false)
        guard parts.count == 3, parts[0] == prefix else { throw CryptoError.malformedEnvelope }

        guard let nonceData = base64urlDecode(String(parts[1])),
              let ctData    = base64urlDecode(String(parts[2])) else {
            throw CryptoError.malformedEnvelope
        }
        guard nonceData.count == 12 else { throw CryptoError.malformedEnvelope }

        let nonce  = try AES.GCM.Nonce(data: nonceData)
        let symKey = SymmetricKey(data: key)

        // CryptoKit's SealedBox(combined:) expects nonce | ciphertext | tag
        let combined = nonceData + ctData
        let sealedBox = try AES.GCM.SealedBox(combined: combined)
        let plaintext = try AES.GCM.open(sealedBox, using: symKey)
        return plaintext
    }

    // MARK: - Helpers

    private static func base64url(_ data: Data) -> String {
        data.base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
    }

    static func base64urlDecode(_ s: String) -> Data? {
        guard !s.isEmpty, s.count % 4 != 1,
              s.unicodeScalars.allSatisfy({
                  CharacterSet.alphanumerics.contains($0) || $0 == "-" || $0 == "_"
              }) else { return nil }
        var b64 = s
            .replacingOccurrences(of: "-", with: "+")
            .replacingOccurrences(of: "_", with: "/")
        // re-pad
        let rem = b64.count % 4
        if rem != 0 { b64 += String(repeating: "=", count: 4 - rem) }
        guard let decoded = Data(base64Encoded: b64),
              base64url(decoded) == s else { return nil }
        return decoded
    }
}

enum CryptoError: Error, LocalizedError {
    case invalidKeySize
    case sealFailed
    case malformedEnvelope
    case decryptionFailed

    var errorDescription: String? {
        switch self {
        case .invalidKeySize:    return "Invalid encryption key size"
        case .sealFailed:        return "Encryption failed"
        case .malformedEnvelope: return "Malformed encrypted envelope"
        case .decryptionFailed:  return "Decryption failed"
        }
    }
}
