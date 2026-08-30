import Foundation
#if canImport(CryptoKit)
import CryptoKit
#endif

@main
struct PrivateCryptoCompatibilityCheck {
    static func main() throws {
        let path = CommandLine.arguments[1]
        let data = try Data(contentsOf: URL(fileURLWithPath: path))
        let vector = try JSONSerialization.jsonObject(with: data) as! [String: Any]
        let key = decode(vector["keyBase64url"] as! String)
        let wrongKey = decode(vector["wrongKeyBase64url"] as! String)
        let plaintext = decode(vector["plaintextBase64url"] as! String)
        let ios = vector["ios"] as! [String: String]
        let android = vector["android"] as! [String: String]

        #if canImport(CryptoKit)
        let decryptedByIOS = try PrivateCrypto.decrypt(envelope: android["envelope"]!, key: key)
        precondition(decryptedByIOS == plaintext, "iOS must decrypt the canonical Android envelope")
        let encryptedByIOS = try PrivateCrypto.encrypt(
            plaintext: plaintext,
            key: key,
            nonceData: decode(ios["nonceBase64url"]!)
        )
        precondition(encryptedByIOS == ios["envelope"], "iOS encryption changed from the canonical envelope")
        mustReject("wrong key") {
            _ = try PrivateCrypto.decrypt(envelope: android["envelope"]!, key: wrongKey)
        }
        mustReject("tampered tag") {
            let envelope = android["envelope"]!
            let replacement = envelope.last == "A" ? "B" : "A"
            _ = try PrivateCrypto.decrypt(envelope: String(envelope.dropLast()) + replacement, key: key)
        }
        mustReject("malformed base64url") {
            _ = try PrivateCrypto.decrypt(
                envelope: "ananse-aesgcm-v1.%%%%.\(android["envelope"]!.split(separator: ".").last!)",
                key: key
            )
        }
        precondition(
            PrivateCrypto.inviteKeyId(forToken: vector["inviteToken"] as! String)
                == vector["inviteKeyId"] as! String
        )
        #endif

        let sender = vector["senderUserId"] as! String
        let recipient = vector["recipientUserId"] as! String
        #if canImport(CryptoKit)
        precondition(
            shouldAcceptLiveEnvelope(
                id: "m1",
                senderUserId: sender,
                recipientUserId: recipient,
                activeContactId: sender,
                myUserId: recipient,
                seenIds: []
            )
        )
        precondition(
            !shouldAcceptLiveEnvelope(
                id: "m1",
                senderUserId: sender,
                recipientUserId: "wrong",
                activeContactId: sender,
                myUserId: recipient,
                seenIds: []
            )
        )
        #endif

        let keyId = vector["inviteKeyId"] as! String
        #if canImport(CryptoKit)
        let pending = [keyId: key]
        let match = matchingPendingConversationKey(
            contactInviteKeyId: keyId,
            loadPendingKey: { pending[$0] }
        )
        precondition(
            match?.keyId == keyId && match?.key == key,
            "the exact fresh invite key must be selected for replacement"
        )
        let staleMatch = matchingPendingConversationKey(
            contactInviteKeyId: vector["staleInviteKeyId"] as! String,
            loadPendingKey: { pending[$0] }
        )
        precondition(staleMatch == nil, "stale key IDs must not replace the active key")
        #endif
    }

    static func decode(_ value: String) -> Data {
        var base64 = value.replacingOccurrences(of: "-", with: "+")
            .replacingOccurrences(of: "_", with: "/")
        base64 += String(repeating: "=", count: (4 - base64.count % 4) % 4)
        return Data(base64Encoded: base64)!
    }

    #if canImport(CryptoKit)
    static func mustReject(_ label: String, _ operation: () throws -> Void) {
        do {
            try operation()
            preconditionFailure("\(label) must be rejected")
        } catch {}
    }
    #endif
}