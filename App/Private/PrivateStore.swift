// PrivateStore.swift
// In-memory state manager for the private messenger.
// Message contents are NEVER persisted — only identity and
// per-contact secrets live in the Keychain (see PrivateIdentity.swift).
// All conversation state is cleared on background and on end/delete.

import Combine
import Foundation

// MARK: - In-memory message model

struct ChatMessage: Identifiable {
    let id: String
    let seq: Int
    let senderUserId: String   // empty string = outbound (sent by self)
    let text: String           // decrypted plaintext
    let createdAt: Date
    let isMine: Bool
    var sendStatus: SendStatus

    enum SendStatus {
        case sent       // delivered live to the recipient (never stored)
        case rejected   // contact removed / offline (503) / forbidden — NOT queued
        case uncertain  // 504 — cross-worker delivery could not be confirmed; NOT queued
        case pending    // optimistic (not yet confirmed)
    }
}

// MARK: - Store

@MainActor
final class PrivateStore: ObservableObject {

    // MARK: - Published state

    @Published var contacts: [ContactInfo] = []
    @Published var isAuthenticated = false
    @Published var authError: String?
    @Published var myUserId: String?
    @Published var myHandle: String?

    /// A deep-link invite (ananse://invite#token=...&key=...) received via
    /// onOpenURL but not yet presented for accept. Held ONLY in transient
    /// in-memory state so a cold-launch invite that arrives before consent,
    /// before authentication, or before ContactsView exists is not lost — and
    /// never touches UserDefaults/file/Keychain. The token and its 32-byte key
    /// stay in memory until the existing acceptance flow performs its key-first
    /// storage. Cleared when handed off for presentation or cancelled.
    @Published var pendingInviteURL: URL?

    /// Active chat: userId → [ChatMessage]. Cleared on end/delete/background.
    @Published var activeConversation: (contactId: String, messages: [ChatMessage])?

    @Published var isLoadingContacts = false
    @Published var isSending = false

    /// Set while eraseLocalIdentity is running its server-side DELETE.
    @Published var isErasing = false
    /// Non-nil when eraseLocalIdentity failed the server DELETE; caller shows this.
    @Published var eraseError: String?

    // MARK: - Private state

    private var pollTask: Task<Void, Never>?
    private var lastSeqByContact: [String: Int] = [:]  // in-memory cursor, never persisted

    /// All in-flight send tasks, keyed by their optimistic message id, so they
    /// can be cancelled the moment the conversation is torn down.
    private var sendTasks: [String: Task<Void, Never>] = [:]

    /// Monotonic "activity generation". Bumped whenever the conversation is
    /// cleared/ended/backgrounded/erased. A send captures the generation at
    /// start and refuses to transmit if it no longer matches — closing the race
    /// between an async send and a teardown.
    private var activityGeneration = 0

    init() {}

    // MARK: - Deep-link invite handoff

    /// Receive a deep-link invite URL from onOpenURL. Validates the scheme/host
    /// and retains it in transient in-memory state only. Safe to call at any
    /// point in the lifecycle (cold launch, before consent, before auth); the
    /// URL is held until ContactsView appears and presents it exactly once.
    /// No persistence of the token or its key occurs here — that only happens
    /// inside the acceptance flow's key-first storage.
    func receiveInviteURL(_ url: URL) {
        guard url.scheme == "ananse", url.host == "invite" else { return }
        pendingInviteURL = url
    }

    /// Take the pending invite URL for presentation, clearing it from transient
    /// state so it is presented exactly once. Returns nil if none is pending.
    func takePendingInviteURL() -> URL? {
        defer { pendingInviteURL = nil }
        return pendingInviteURL
    }

    /// Drop any pending invite URL without presenting it.
    func clearPendingInviteURL() {
        pendingInviteURL = nil
    }

    // MARK: - Auth

    func authenticate() async {
        authError = nil
        do {
            let verified = try await PrivateAPIClient.shared.authenticate()
            myUserId = verified.userId
            myHandle = verified.handle
            isAuthenticated = true
        } catch {
            authError = error.localizedDescription
        }
    }

    // MARK: - Contacts

    func loadContacts() async {
        isLoadingContacts = true
        defer { isLoadingContacts = false }
        do {
            let fetched = try await PrivateAPIClient.shared.listContacts()
            // Inviter-side key exchange & re-keying: for any contact that carries
            // an inviteKeyId with a matching 32-byte pending invite key (stashed
            // at invite time under that exact id), move the pending key onto the
            // contact. Exact-id matching — no FIFO, no in-memory guessing.
            //
            // This intentionally REPLACES an already-stored contact secret when a
            // fresh invite's pending key is present: accepting a new invite for an
            // existing contact re-keys the conversation. To avoid ever leaving the
            // contact without a usable secret, we snapshot the old secret, attempt
            // the overwrite, and only delete the exact pending key AFTER the save
            // succeeds. If the save fails we restore the old secret (if any) and
            // keep the pending key so a later loadContacts() can retry.
            for contact in fetched {
                guard let match = matchingPendingConversationKey(
                    contactInviteKeyId: contact.inviteKeyId,
                    loadPendingKey: { inviteKeyId in
                        guard let key = PrivateKeychain.loadPendingInviteKey(inviteKeyId: inviteKeyId),
                              key.count == 32 else { return nil }
                        return key
                    }
                ) else { continue }
                let inviteKeyId = match.keyId
                let pending = match.key
                let existing = PrivateKeychain.loadContactSecret(contactUserID: contact.userId)
                // Nothing to do if the stored secret already equals the pending
                // key — but still clear the now-redundant pending entry.
                if existing == pending {
                    PrivateKeychain.deletePendingInviteKey(inviteKeyId: inviteKeyId)
                    continue
                }
                do {
                    try PrivateKeychain.saveContactSecret(pending, contactUserID: contact.userId)
                    // Save confirmed — safe to drop this exact pending key.
                    PrivateKeychain.deletePendingInviteKey(inviteKeyId: inviteKeyId)
                } catch {
                    // Overwrite failed — restore the previous secret if there was
                    // one and preserve the pending key for a later retry.
                    if let existing = existing {
                        try? PrivateKeychain.saveContactSecret(existing, contactUserID: contact.userId)
                    }
                }
            }
            contacts = fetched
        } catch {
            // Surface auth errors; network failures leave the existing list
            if case APIError.httpError(401, _) = error {
                isAuthenticated = false
            }
        }
    }

    // MARK: - Conversation (open / close)

    /// Open a chat session with a contact. Starts heartbeat/poll loop.
    func openConversation(contactId: String) {
        activeConversation = (contactId: contactId, messages: [])
        startPoll(contactId: contactId)
    }

    /// End the conversation: DELETE the mutual contact on the server FIRST.
    /// Only clears local state (keys, active messages) once the server delete
    /// succeeds; on failure it throws so the UI can surface it and keep the
    /// conversation intact.
    func endConversation(contactId: String) async throws {
        // Tearing down: stop polling, cancel any in-flight sends, and bump the
        // generation so nothing outstanding can transmit against a conversation
        // we are ending.
        activityGeneration &+= 1
        cancelAllSendTasks()
        stopPoll()
        // Best-effort teardown of the live conversation; ignore its result.
        try? await PrivateAPIClient.shared.deleteLiveConversation(contactId)

        // Authoritative step: the mutual contact deletion MUST succeed before
        // we discard any local state — EXCEPT a 404, which means the contact is
        // already gone on the server (e.g. the peer already ended). That is a
        // safe, idempotent success: proceed with the local wipe. Any other
        // error is rethrown so the UI can surface it and keep the chat intact.
        do {
            try await PrivateAPIClient.shared.deleteContact(contactId)
        } catch APIError.httpError(404, _) {
            // Already gone on the server — safe to complete local cleanup.
        }

        // Server delete confirmed (or already gone) — now clear everything local.
        PrivateKeychain.deleteContactSecret(contactUserID: contactId)
        contacts.removeAll { $0.userId == contactId }
        clearConversation()
    }

    /// Clear transient in-memory conversation state.
    /// Bumps the activity generation and cancels every in-flight send so no
    /// pending network transmission outlives the conversation.
    func clearConversation() {
        activityGeneration &+= 1
        cancelAllSendTasks()
        stopPoll()
        activeConversation = nil
        lastSeqByContact = [:]
    }

    /// Cancel and forget all tracked in-flight send tasks. Cancellation
    /// propagates into URLSession.data(for:) so the underlying request is torn
    /// down, and the send code checks cancellation before transmitting.
    private func cancelAllSendTasks() {
        for task in sendTasks.values { task.cancel() }
        sendTasks.removeAll()
    }

    /// Call on app background.
    func handleBackground() {
        clearConversation()
    }

    // MARK: - Send

    /// Enqueue an outbound message. The actual network send runs inside a
    /// tracked, cancellable Task so conversation teardown can abort it. Returns
    /// immediately; UI observes the optimistic message + its evolving status.
    func sendMessage(text: String, to contactId: String) {
        guard let key = PrivateKeychain.loadContactSecret(contactUserID: contactId) else { return }
        guard let plainData = text.data(using: .utf8) else { return }

        let optimisticId = UUID().uuidString
        let optimistic = ChatMessage(
            id: optimisticId,
            seq: -1,
            senderUserId: myUserId ?? "",
            text: text,
            createdAt: Date(),
            isMine: true,
            sendStatus: .pending
        )
        appendMessage(optimistic, to: contactId)

        // Capture the generation at send start; if teardown bumps it before we
        // transmit, we must NOT hit the network.
        let generationAtStart = activityGeneration

        let task = Task { [weak self] in
            guard let self = self else { return }
            await self.performSend(
                optimisticId: optimisticId,
                text: text,
                key: key,
                plainData: plainData,
                contactId: contactId,
                generationAtStart: generationAtStart
            )
        }
        sendTasks[optimisticId] = task
    }

    /// The cancellable body of a send. Runs on the main actor (PrivateStore is
    /// @MainActor) but its awaits — including URLSession — yield, so Task
    /// cancellation propagates into the network request.
    private func performSend(
        optimisticId: String,
        text: String,
        key: Data,
        plainData: Data,
        contactId: String,
        generationAtStart: Int
    ) async {
        defer {
            sendTasks[optimisticId] = nil
            isSending = !sendTasks.isEmpty
        }
        isSending = true

        do {
            let envelope = try PrivateCrypto.encrypt(plaintext: plainData, key: key)

            // Final guard immediately before transmission: bail if this send
            // was cancelled or the conversation was torn down in the meantime.
            if Task.isCancelled || generationAtStart != activityGeneration {
                return
            }

            // Live send only — nothing is ever queued or stored.
            //   409 (recipientOffline) / 503 (serverBusy) / 403 => .rejected
            let sent = try await PrivateAPIClient.shared.sendLiveMessage(
                recipientUserId: contactId,
                encryptedPayload: envelope
            )
            // If the conversation was torn down while the request was in flight,
            // drop the result silently.
            guard generationAtStart == activityGeneration else { return }
            updateMessage(optimisticId, seq: sent.seq, to: contactId, status: .sent)
        } catch APIError.cancelled {
            // Cancelled by teardown — leave no status update; the message will
            // be cleared along with the conversation.
            return
        } catch APIError.httpError(504, _) {
            // Cross-worker delivery could not be confirmed; nothing was queued.
            guard generationAtStart == activityGeneration else { return }
            updateMessage(optimisticId, seq: -1, to: contactId, status: .uncertain)
        } catch APIError.httpError(let code, _) where code == 403 || code == 404 {
            // The peer ended the contact while this send was in flight. Destroy
            // the local key/contact immediately so the chat cannot be reopened.
            guard generationAtStart == activityGeneration else { return }
            handlePeerEnded(contactId: contactId)
        } catch {
            guard generationAtStart == activityGeneration else { return }
            updateMessage(optimisticId, seq: -1, to: contactId, status: .rejected)
        }
    }

    // MARK: - Poll / heartbeat

    private func startPoll(contactId: String) {
        stopPoll()
        pollTask = Task {
            while !Task.isCancelled {
                // Each call is a long poll: the server holds the connection for
                // up to ~20s. An empty successful wait must IMMEDIATELY start the
                // next long poll (no multi-second gap) so live delivery is
                // effectively continuous. Only a transient error asks for a short
                // backoff before retrying.
                let outcome = await self.pollMessages(contactId: contactId)
                switch outcome {
                case .ended:
                    // Peer ended / removed us — the conversation was cleaned up
                    // inside pollMessages; stop looping.
                    return
                case .ok:
                    // Immediately loop into the next long poll.
                    continue
                case .transientError:
                    do {
                        // Small backoff only after a transient failure.
                        try await Task.sleep(nanoseconds: 1_000_000_000) // 1s
                    } catch {
                        return // cancelled during backoff
                    }
                }
            }
        }
    }

    /// Outcome of a single long-poll cycle.
    private enum PollOutcome {
        case ok             // successful wait (with or without messages)
        case ended          // peer ended the chat (403) — conversation cleaned up
        case transientError // network/other error — back off then retry
    }

    private func stopPoll() {
        pollTask?.cancel()
        pollTask = nil
    }

    private func pollMessages(contactId: String) async -> PollOutcome {
        // Post presence heartbeat (best-effort)
        try? await PrivateAPIClient.shared.postPresence(contactUserId: contactId)

        do {
            // Stateless long poll: the server keeps no cursor, so no `after` is
            // sent. Dedup is done locally by message id.
            let messages = try await PrivateAPIClient.shared.fetchLiveMessages(
                contactUserId: contactId
            )
            guard !messages.isEmpty else { return .ok }

            guard let key = PrivateKeychain.loadContactSecret(contactUserID: contactId) else { return .ok }

            var newSeq = lastSeqByContact[contactId] ?? 0
            var newMessages: [ChatMessage] = []
            for env in messages {
                newSeq = max(newSeq, env.seq)
                let seenIds = Set(activeConversation?.messages.map(\.id) ?? [])
                guard let myUserId = myUserId,
                      shouldAcceptLiveEnvelope(
                          id: env.id,
                          senderUserId: env.senderUserId,
                          recipientUserId: env.recipientUserId,
                          activeContactId: contactId,
                          myUserId: myUserId,
                          seenIds: seenIds
                      ) else { continue }

                let text: String
                do {
                    let plain = try PrivateCrypto.decrypt(envelope: env.payload, key: key)
                    text = String(data: plain, encoding: .utf8) ?? "[unreadable]"
                } catch {
                    text = "[encrypted — could not decrypt]"
                }
                let date = Self.parseDate(env.createdAt)
                newMessages.append(ChatMessage(
                    id: env.id,
                    seq: env.seq,
                    senderUserId: env.senderUserId,
                    text: text,
                    createdAt: date,
                    isMine: false,
                    sendStatus: .sent
                ))
            }
            lastSeqByContact[contactId] = newSeq

            for msg in newMessages {
                appendMessage(msg, to: contactId)
            }
            // No read-marker call: live messaging is stateless on the phone.
            return .ok
        } catch APIError.cancelled {
            // Loop was torn down; do not treat as an error to back off from.
            return .ended
        } catch APIError.httpError(let code, _) where code == 403 || code == 404 {
            // The peer ended the chat (server says we are no longer contacts).
            // Remove the contact locally and WIPE its conversation key so it can
            // never reopen, then stop the loop.
            handlePeerEnded(contactId: contactId)
            return .ended
        } catch {
            // Network / other errors are transient; back off and keep polling.
            return .transientError
        }
    }

    /// The peer ended the conversation (server reports we are no longer
    /// contacts). Remove the contact locally and destroy its conversation key
    /// so the chat can never be reopened, then tear down the active session.
    private func handlePeerEnded(contactId: String) {
        PrivateKeychain.deleteContactSecret(contactUserID: contactId)
        contacts.removeAll { $0.userId == contactId }
        clearConversation()
    }

    // MARK: - Helpers

    private func appendMessage(_ msg: ChatMessage, to contactId: String) {
        guard var conv = activeConversation, conv.contactId == contactId else { return }
        conv.messages.append(msg)
        activeConversation = conv
    }

    private func updateMessage(_ id: String, seq: Int, to contactId: String, status: ChatMessage.SendStatus) {
        guard var conv = activeConversation, conv.contactId == contactId else { return }
        if let i = conv.messages.firstIndex(where: { $0.id == id }) {
            let old = conv.messages[i]
            conv.messages[i] = ChatMessage(
                id: old.id,
                seq: seq,
                senderUserId: old.senderUserId,
                text: old.text,
                createdAt: old.createdAt,
                isMine: old.isMine,
                sendStatus: status
            )
        }
        activeConversation = conv
    }

    // MARK: - Date parsing

    private static func parseDate(_ string: String) -> Date {
        let f1 = ISO8601DateFormatter()
        f1.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let d = f1.date(from: string) { return d }
        let f2 = ISO8601DateFormatter()
        f2.formatOptions = [.withInternetDateTime]
        return f2.date(from: string) ?? Date()
    }

    // MARK: - Invite accept (adds contact + stores shared key)

    func acceptInvite(token: String, sharedKey: Data?) async throws -> ContactInfo {
        // A native app-to-app invite MUST carry a valid 32-byte key in the URL
        // fragment. Refuse rather than generate a divergent fallback key that
        // the two sides could never agree on.
        guard let key = sharedKey, key.count == 32 else {
            throw PrivateStoreError.missingInviteKey
        }

        // Compute the expected inviteKeyId (SHA-256 hex of the raw token) BEFORE
        // any network call so we can (a) stash the pending key under it and
        // (b) verify the server returns a contact for exactly this invite.
        let expectedKeyId = PrivateCrypto.inviteKeyId(forToken: token)

        // Save the pending key FIRST, keyed by the expected inviteKeyId. If
        // acceptance succeeds but the app is interrupted before we reconcile the
        // key onto the contact, the next loadContacts() will move this pending
        // key onto the contact by exact inviteKeyId match — so an accepted
        // contact is never left without its key.
        try PrivateKeychain.savePendingInviteKey(key, inviteKeyId: expectedKeyId)

        let result: InviteAccepted
        do {
            result = try await PrivateAPIClient.shared.acceptInvite(token: token)
        } catch {
            // Acceptance failed: nothing was reconciled onto a contact. Drop the
            // pending key we just stashed so no orphaned secret lingers, then
            // rethrow the original reason for the UI to surface.
            PrivateKeychain.deletePendingInviteKey(inviteKeyId: expectedKeyId)
            throw error
        }
        let contact = result.contact

        // Verify the server's inviteKeyId matches what we computed locally from
        // the URL-fragment token. A mismatch means the server returned a contact
        // for a different invite, which is a security violation — refuse and drop
        // the pending key so no contact is ever paired with the wrong key.
        guard let serverKeyId = contact.inviteKeyId, serverKeyId == expectedKeyId else {
            PrivateKeychain.deletePendingInviteKey(inviteKeyId: expectedKeyId)
            throw PrivateStoreError.inviteKeyIdMismatch
        }

        // Reconcile: move the validated key onto the contact id, then clear the
        // pending entry. If saving the contact secret fails we leave the pending
        // key in place (loadContacts() will reconcile it later) and refuse to
        // present an accepted contact that has no usable key.
        do {
            try PrivateKeychain.saveContactSecret(key, contactUserID: contact.userId)
        } catch {
            throw PrivateStoreError.inviteKeyIdMismatch
        }
        PrivateKeychain.deletePendingInviteKey(inviteKeyId: expectedKeyId)

        if !contacts.contains(where: { $0.userId == contact.userId }) {
            contacts.insert(contact, at: 0)
        }
        return contact
    }

    // MARK: - Erase local identity

    /// Two-confirmation "erase local identity": first calls DELETE /api/private/me
    /// so the server account is removed. Only if that succeeds does the local
    /// identity/contact/key wipe proceed. On server failure the local credentials
    /// are kept intact so the user can retry.
    ///
    /// Sets isErasing = true while the server call is in flight.
    /// On failure sets eraseError with a human-readable message and returns without
    /// wiping local data.
    func eraseLocalIdentity() {
        isErasing = true
        eraseError = nil
        Task {
            defer { isErasing = false }
            do {
                // Authenticated server erasure MUST succeed first.
                try await PrivateAPIClient.shared.deleteAccount()
            } catch {
                // Server call failed — keep every local credential intact.
                eraseError = "Could not erase server account: \(error.localizedDescription). Your local identity has been kept. Please try again."
                return
            }
            // Server confirmed — now wipe local state.
            clearConversation()
            contacts = []
            myUserId = nil
            myHandle = nil
            isAuthenticated = false
            PrivateKeychain.eraseAll()
        }
    }
}

enum PrivateStoreError: Error, LocalizedError {
    case missingInviteKey
    case inviteKeyIdMismatch

    var errorDescription: String? {
        switch self {
        case .missingInviteKey:
            return "This invite link is missing its encryption key. Ask for a new invite."
        case .inviteKeyIdMismatch:
            return "The invite link does not match the contact returned by the server. The invite may have been tampered with or has expired. Ask for a new invite."
        }
    }
}
