// PrivateIdentity.swift
// Manages the device Ed25519 keypair and conversation secrets in the Keychain.
// Nothing here touches message contents — only identity and shared secrets.

import CryptoKit
import Foundation
import Security

/// Keychain-backed store for the device identity keypair and per-contact
/// conversation keys. All sensitive material is stored with
/// kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly so it survives app
/// restarts but never leaves the device in a backup.
///
/// EVERY item written here carries a shared kSecAttrService prefix so that
/// "erase local identity" can scope its deletes to Ananse's own items and
/// never touch unrelated generic-password entries.
enum PrivateKeychain {

    // MARK: - Service namespacing

    /// Base service for identity/config items (device id, user id, handle,
    /// identity private key).
    static let identityService = "app.ananse.private.identity"
    /// Service for per-contact conversation secrets.
    static let contactService = "app.ananse.private.contact"
    /// Service for pending invite keys (keyed by inviteKeyId = SHA-256 hex of
    /// the raw token), awaiting the acceptor to appear in the contact list.
    static let pendingKeyService = "app.ananse.private.pendingKey"

    /// All Ananse services — used only for scoped erase.
    private static let allServices = [identityService, contactService, pendingKeyService]

    // MARK: - Account names (within identityService)

    private static let privateKeyAccount = "identity.ed25519"
    private static let deviceIDAccount   = "deviceID"
    private static let userIDAccount     = "userID"
    private static let handleAccount     = "handle"

    private static let consentDoneKey = "app.ananse.private.consentDone"

    // MARK: - Consent flag (UserDefaults is fine — non-sensitive)

    static var consentGiven: Bool {
        get { UserDefaults.standard.bool(forKey: consentDoneKey) }
        set { UserDefaults.standard.set(newValue, forKey: consentDoneKey) }
    }

    // MARK: - Identity keypair

    /// Returns or lazily creates the device Ed25519 signing key.
    /// The raw private key bytes are stored as kSecClassGenericPassword
    /// (CryptoKit Curve25519 keys are not SecKey objects and should not
    /// be stored under kSecClassKey).
    static func identityPrivateKey() throws -> Curve25519.Signing.PrivateKey {
        if let data = loadData(service: identityService, account: privateKeyAccount) {
            return try Curve25519.Signing.PrivateKey(rawRepresentation: data)
        }
        let newKey = Curve25519.Signing.PrivateKey()
        try saveData(newKey.rawRepresentation, service: identityService, account: privateKeyAccount)
        return newKey
    }

    static func identityPublicKey() throws -> Curve25519.Signing.PublicKey {
        try identityPrivateKey().publicKey
    }

    /// Base64-encoded SPKI representation expected by the server.
    static func identityPublicKeySPKI() throws -> String {
        let pub = try identityPublicKey()
        // SPKI header for Ed25519 (RFC 8410) = 12 bytes
        let spkiHeader = Data([
            0x30, 0x2a,             // SEQUENCE
            0x30, 0x05,             // SEQUENCE
            0x06, 0x03,             // OID
            0x2b, 0x65, 0x70,       // 1.3.101.112 (id-EdDSA/Ed25519)
            0x03, 0x21, 0x00,       // BIT STRING, 33 bytes, 0 unused bits
        ])
        let spki = spkiHeader + pub.rawRepresentation
        return spki.base64EncodedString()
    }

    // MARK: - Device / user IDs

    static func saveDeviceID(_ id: String) throws {
        try saveData(Data(id.utf8), service: identityService, account: deviceIDAccount)
    }
    static func loadDeviceID() -> String? {
        loadString(service: identityService, account: deviceIDAccount)
    }
    static func saveUserID(_ id: String) throws {
        try saveData(Data(id.utf8), service: identityService, account: userIDAccount)
    }
    static func loadUserID() -> String? {
        loadString(service: identityService, account: userIDAccount)
    }
    static func saveHandle(_ handle: String?) throws {
        if let h = handle {
            try saveData(Data(h.utf8), service: identityService, account: handleAccount)
        } else {
            deleteItem(service: identityService, account: handleAccount)
        }
    }
    static func loadHandle() -> String? {
        loadString(service: identityService, account: handleAccount)
    }

    // MARK: - Per-contact conversation secrets (raw 32-byte AES-GCM keys)

    /// Persist a shared secret for a contact. The key is the raw 32-byte
    /// symmetric key used to encrypt/decrypt messages in this conversation.
    static func saveContactSecret(_ secret: Data, contactUserID: String) throws {
        try saveData(secret, service: contactService, account: contactUserID)
    }

    static func loadContactSecret(contactUserID: String) -> Data? {
        loadData(service: contactService, account: contactUserID)
    }

    static func deleteContactSecret(contactUserID: String) {
        deleteItem(service: contactService, account: contactUserID)
    }

    // MARK: - Pending invite keys (keyed by inviteKeyId)

    /// Store the conversation key generated when an invite is created, keyed
    /// by inviteKeyId (SHA-256 hex of the raw token). When the acceptor later
    /// appears in the contact list with a matching inviteKeyId, the key is
    /// moved to a per-contact secret.
    static func savePendingInviteKey(_ key: Data, inviteKeyId: String) throws {
        try saveData(key, service: pendingKeyService, account: inviteKeyId)
    }

    static func loadPendingInviteKey(inviteKeyId: String) -> Data? {
        loadData(service: pendingKeyService, account: inviteKeyId)
    }

    static func deletePendingInviteKey(inviteKeyId: String) {
        deleteItem(service: pendingKeyService, account: inviteKeyId)
    }

    // MARK: - Scoped erase

    /// Erase ONLY Ananse private items (identity, contact secrets, pending
    /// invite keys). Never touches unrelated generic-password items belonging
    /// to other services.
    static func eraseAll() {
        for service in allServices {
            let query: [String: Any] = [
                kSecClass as String:       kSecClassGenericPassword,
                kSecAttrService as String: service,
            ]
            SecItemDelete(query as CFDictionary)
        }
        UserDefaults.standard.removeObject(forKey: consentDoneKey)
    }

    // MARK: - Private Keychain primitives (service + account scoped)

    private static func saveData(_ data: Data, service: String, account: String) throws {
        let addQuery: [String: Any] = [
            kSecClass as String:          kSecClassGenericPassword,
            kSecAttrService as String:    service,
            kSecAttrAccount as String:    account,
            kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly,
            kSecValueData as String:      data,
        ]
        var status = SecItemAdd(addQuery as CFDictionary, nil)
        if status == errSecDuplicateItem {
            let updateQuery: [String: Any] = [
                kSecClass as String:       kSecClassGenericPassword,
                kSecAttrService as String: service,
                kSecAttrAccount as String: account,
            ]
            let updateAttrs: [String: Any] = [kSecValueData as String: data]
            status = SecItemUpdate(updateQuery as CFDictionary, updateAttrs as CFDictionary)
        }
        if status != errSecSuccess { throw KeychainError.saveFailed(status) }
    }

    private static func loadData(service: String, account: String) -> Data? {
        let query: [String: Any] = [
            kSecClass as String:       kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecReturnData as String:  true,
            kSecMatchLimit as String:  kSecMatchLimitOne,
        ]
        var item: CFTypeRef?
        guard SecItemCopyMatching(query as CFDictionary, &item) == errSecSuccess,
              let data = item as? Data else { return nil }
        return data
    }

    private static func loadString(service: String, account: String) -> String? {
        guard let data = loadData(service: service, account: account) else { return nil }
        return String(data: data, encoding: .utf8)
    }

    private static func deleteItem(service: String, account: String) {
        let query: [String: Any] = [
            kSecClass as String:       kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
        ]
        SecItemDelete(query as CFDictionary)
    }
}

enum KeychainError: Error, LocalizedError {
    case saveFailed(OSStatus)
    case notFound

    var errorDescription: String? {
        switch self {
        case .saveFailed(let s): return "Keychain save failed: \(s)"
        case .notFound:          return "Keychain item not found"
        }
    }
}
