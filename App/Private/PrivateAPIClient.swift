// PrivateAPIClient.swift
// Native HTTP client for the /api/private endpoints.
// Session cookies are managed automatically by URLSession.
// No plaintext message content ever appears in request bodies
// (all payloads are already encrypted by PrivateCrypto before calling these methods).

import CryptoKit
import Foundation

// MARK: - Response models

struct RegisteredDevice: Codable {
    let userId: String
    let deviceId: String
    let handle: String?
    let createdAt: String
}

struct AuthChallenge: Codable {
    let challengeId: String
    let challenge: String
    let expiresAt: String
}

struct AuthVerified: Codable {
    let userId: String
    let deviceId: String
    let handle: String?
    let sessionExpiresAt: String
}

struct ContactInfo: Codable, Identifiable {
    let userId: String
    let handle: String?
    let fingerprint: String
    let connectedAt: String
    /// SHA-256 hex of the raw invite token that established this contact.
    /// Required by the server contract (nullable). Used to match the pending
    /// conversation key the inviter stashed in the Keychain at invite time.
    let inviteKeyId: String?

    var id: String { userId }
}

struct ContactsResponse: Codable {
    let contacts: [ContactInfo]
}

struct InviteCreated: Codable {
    let token: String
    let expiresAt: String
}

struct InvitePreview: Codable {
    let inviterHandle: String?
    let inviterFingerprint: String
    let expiresAt: String
    let alreadyContact: Bool
    let isSelf: Bool
}

struct InviteAccepted: Codable {
    let contact: ContactInfo
    let alreadyContact: Bool
}

/// A single message returned by the live endpoints (PrivateMessage).
struct PrivateMessage: Codable, Identifiable {
    let id: String
    let seq: Int
    let senderUserId: String
    let recipientUserId: String
    let payload: String       // encrypted envelope string
    let createdAt: String
}

struct MessageListResponse: Codable {
    let messages: [PrivateMessage]
}

// MARK: - API Error

enum APIError: Error, LocalizedError {
    case badURL
    case httpError(Int, String?)
    case decodingError(Error)
    case offline
    case recipientOffline     // 409 — recipient not actively waiting; NOTHING queued or stored
    case serverBusy           // 503 — live relay temporarily unavailable; message NOT queued
    case cancelled            // request was cancelled locally (Task cancellation)
    case unknown(Error)

    var errorDescription: String? {
        switch self {
        case .badURL:                   return "Invalid API URL"
        case .httpError(let c, let m):  return m ?? "HTTP \(c)"
        case .decodingError(let e):     return "Response parse error: \(e)"
        case .offline:                  return "No network connection"
        case .recipientOffline:         return "Recipient must have this conversation open — nothing was queued"
        case .serverBusy:               return "Live relay is temporarily unavailable — message was not delivered"
        case .cancelled:                return "Request was cancelled"
        case .unknown(let e):           return e.localizedDescription
        }
    }

    var isRejected: Bool {
        switch self {
        case .recipientOffline, .serverBusy: return true
        case .httpError(let code, _): return code == 403 || code == 410
        default: return false
        }
    }
}

// MARK: - Client

/// All network I/O for the private messenger. Uses an EPHEMERAL URLSession
/// so the session cookie and any HTTP cache live only in memory and are gone
/// when the app terminates — nothing message-related touches disk.
final class PrivateAPIClient {

    static let shared = PrivateAPIClient()

    private let session: URLSession
    private let baseURL: URL

    private init() {
        // Configurable via Info.plist; default production URL
        let plistURL = Bundle.main.object(forInfoDictionaryKey: "AnansePrivateAPIBaseURL") as? String
        let urlString = plistURL ?? "https://anansekeyboard.com/api"
        baseURL = URL(string: urlString) ?? URL(string: "https://anansekeyboard.com/api")!

        // Ephemeral: cookie storage and cache are in-memory only.
        let config = URLSessionConfiguration.ephemeral
        config.httpCookieAcceptPolicy = .onlyFromMainDocumentDomain
        config.httpShouldSetCookies = true
        // The live GET holds up to 20s; allow headroom on the request timeout.
        config.timeoutIntervalForRequest = 40
        session = URLSession(configuration: config)
    }

    // MARK: - Registration & Auth

    func registerDevice(publicKeySPKI: String) async throws -> RegisteredDevice {
        // The server contract no longer accepts a device label; only the
        // identity public key is sent.
        let body: [String: Any] = ["identityPublicKey": publicKeySPKI]
        return try await post("/private/devices", body: body)
    }

    func createChallenge(deviceId: String) async throws -> AuthChallenge {
        return try await post("/private/auth/challenge", body: ["deviceId": deviceId])
    }

    /// Sign the challenge message and verify with the server to get a session cookie.
    func verifyChallenge(
        challengeId: String,
        challenge: String,
        privateKey: Curve25519.Signing.PrivateKey
    ) async throws -> AuthVerified {
        // The server's challengeMessage format: "ananse-private-auth-v1.challengeId.challenge"
        let message = "ananse-private-auth-v1.\(challengeId).\(challenge)"
        guard let messageData = message.data(using: .utf8) else { throw APIError.badURL }
        let signature = try privateKey.signature(for: messageData)
        let sigB64 = signature.base64EncodedString()

        return try await post("/private/auth/verify", body: [
            "challengeId": challengeId,
            "signature": sigB64,
        ])
    }

    func authenticate() async throws -> AuthVerified {
        let privateKey = try PrivateKeychain.identityPrivateKey()
        let spki = try PrivateKeychain.identityPublicKeySPKI()

        // Load or register device
        let deviceId: String
        if let stored = PrivateKeychain.loadDeviceID() {
            deviceId = stored
        } else {
            let reg = try await registerDevice(publicKeySPKI: spki)
            try PrivateKeychain.saveDeviceID(reg.deviceId)
            try PrivateKeychain.saveUserID(reg.userId)
            try PrivateKeychain.saveHandle(reg.handle)
            deviceId = reg.deviceId
        }

        let challenge = try await createChallenge(deviceId: deviceId)
        let verified = try await verifyChallenge(
            challengeId: challenge.challengeId,
            challenge: challenge.challenge,
            privateKey: privateKey
        )
        try PrivateKeychain.saveUserID(verified.userId)
        try PrivateKeychain.saveHandle(verified.handle)
        return verified
    }

    // MARK: - Contacts

    func listContacts() async throws -> [ContactInfo] {
        let resp: ContactsResponse = try await get("/private/contacts")
        return resp.contacts
    }

    func deleteContact(_ contactUserId: String) async throws {
        try await delete("/private/contacts/\(contactUserId)")
    }

    // MARK: - Invites

    func createInvite() async throws -> InviteCreated {
        return try await post("/private/invites", body: [:])
    }

    func previewInvite(token: String) async throws -> InvitePreview {
        return try await post("/private/invites/preview", body: ["token": token])
    }

    func acceptInvite(token: String) async throws -> InviteAccepted {
        return try await post("/private/invites/accept", body: ["token": token])
    }

    /// Cancel a pending invite by token. The server marks it as revoked so it
    /// can no longer be accepted. The local pending key should be deleted only
    /// after this call succeeds (caller's responsibility).
    func cancelInvite(token: String) async throws {
        try await postNoContent("/private/invites/cancel", body: ["token": token])
    }

    // MARK: - Account erasure

    /// Authenticated DELETE /api/private/me. Must succeed before local identity
    /// is wiped. On failure the caller retains local credentials so retry is possible.
    func deleteAccount() async throws {
        try await delete("/private/me")
    }

    // MARK: - Live messaging (the ONLY messaging path)
    //
    // There is deliberately NO durable /private/messages fallback and NO
    // read-marker call: all phone messaging goes exclusively through the live
    // endpoints. Nothing is queued server-side; an undeliverable message
    // surfaces as a failure to the sender.

    /// Heartbeat that the conversation is active. Returns 204 (no body).
    func postPresence(contactUserId: String) async throws {
        try await postNoContent(
            "/private/live/presence",
            body: ["contactUserId": contactUserId]
        )
    }

    /// Long-poll (server holds up to 20s) for new live messages. The server keeps
    /// no cursor — live delivery is stateless — so no `after`/cursor query is sent.
    func fetchLiveMessages(contactUserId: String) async throws -> [PrivateMessage] {
        let resp: MessageListResponse = try await get(
            "/private/live/conversations/\(contactUserId)/messages"
        )
        return resp.messages
    }

    /// Send a live message. Returns the delivered PrivateMessage (201).
    /// Nothing is ever queued or stored, on device or server. Failure modes:
    ///   409 => recipient is not actively waiting (offline) => APIError.recipientOffline
    ///   503 => the live relay is temporarily unavailable    => APIError.serverBusy
    ///   403 => no longer a contact (peer ended)             => APIError.httpError(403, _)
    func sendLiveMessage(recipientUserId: String, encryptedPayload: String) async throws -> PrivateMessage {
        return try await post("/private/live/messages", body: [
            "recipientUserId": recipientUserId,
            "payload": encryptedPayload,
        ])
    }

    /// Delete the live conversation (server returns 204).
    func deleteLiveConversation(_ contactId: String) async throws {
        try await delete("/private/live/conversations/\(contactId)")
    }

    // MARK: - HTTP helpers

    private func url(for path: String) -> URL {
        // path may include query string
        if let components = URLComponents(string: baseURL.absoluteString + path),
           let u = components.url { return u }
        return baseURL.appendingPathComponent(path)
    }

    private func post<T: Decodable>(_ path: String, body: [String: Any]) async throws -> T {
        return try await post(path, body: body, type: T.self)
    }

    private func post<T: Decodable>(_ path: String, body: [String: Any], type _: T.Type) async throws -> T {
        let u = url(for: path)
        var req = URLRequest(url: u)
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.httpBody = try JSONSerialization.data(withJSONObject: body)
        let (data, _) = try await data(for: req)
        return try decode(T.self, from: data)
    }

    private func get<T: Decodable>(_ path: String) async throws -> T {
        let u = url(for: path)
        var req = URLRequest(url: u)
        req.httpMethod = "GET"
        let (data, _) = try await data(for: req)
        return try decode(T.self, from: data)
    }

    private func delete(_ path: String) async throws {
        let u = url(for: path)
        var req = URLRequest(url: u)
        req.httpMethod = "DELETE"
        _ = try await data(for: req)
    }

    /// POST with a JSON body expecting a no-content (204) response.
    private func postNoContent(_ path: String, body: [String: Any]) async throws {
        let u = url(for: path)
        var req = URLRequest(url: u)
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.httpBody = try JSONSerialization.data(withJSONObject: body)
        _ = try await data(for: req)
    }

    private func data(for request: URLRequest) async throws -> (Data, URLResponse) {
        do {
            // If the enclosing Task was already cancelled, do not transmit.
            try Task.checkCancellation()
            let (data, response) = try await session.data(for: request)
            if let http = response as? HTTPURLResponse,
               !(200..<300).contains(http.statusCode) {
                let isLiveMessageSend =
                    request.httpMethod == "POST" &&
                    request.url?.path.hasSuffix("/private/live/messages") == true
                // 409 — on a live send, the recipient is not actively waiting
                // (offline). Nothing was queued or stored; surface as an
                // explicit recipient-offline error.
                if isLiveMessageSend && http.statusCode == 409 {
                    throw APIError.recipientOffline
                }
                // 503 — the live relay is temporarily unavailable; the message
                // was NOT queued.
                if isLiveMessageSend && http.statusCode == 503 {
                    throw APIError.serverBusy
                }
                let msg = (try? JSONSerialization.jsonObject(with: data) as? [String: Any])?["error"] as? String
                throw APIError.httpError(http.statusCode, msg)
            }
            return (data, response)
        } catch let apiErr as APIError {
            throw apiErr
        } catch is CancellationError {
            throw APIError.cancelled
        } catch {
            let nsErr = error as NSError
            // Structured-concurrency cancellation cancels the underlying
            // URLSession request, which surfaces as NSURLErrorCancelled.
            if nsErr.domain == NSURLErrorDomain && nsErr.code == NSURLErrorCancelled {
                throw APIError.cancelled
            }
            if nsErr.domain == NSURLErrorDomain {
                throw APIError.offline
            }
            throw APIError.unknown(error)
        }
    }

    private func decode<T: Decodable>(_ type: T.Type, from data: Data) throws -> T {
        let decoder = JSONDecoder()
        // API returns camelCase JSON; use default decoding strategy
        do {
            return try decoder.decode(type, from: data)
        } catch {
            throw APIError.decodingError(error)
        }
    }
}
