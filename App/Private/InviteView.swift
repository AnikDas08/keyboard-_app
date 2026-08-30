// InviteView.swift
// Create and share an invite link. The 32-byte conversation key is embedded
// ONLY in the URL fragment (never sent to the server or logged).
// Generates an on-screen QR code with CoreImage.
// Handles incoming ananse://invite#token=...&key=... URLs.

import CoreImage
import CoreImage.CIFilterBuiltins
import SwiftUI
import UIKit

// MARK: - Invite creation view

struct InviteView: View {
    @EnvironmentObject private var store: PrivateStore
    @Environment(\.dismiss) private var dismiss

    @State private var inviteURL: URL?
    @State private var inviteToken: String?       // kept so Cancel can POST to the server
    @State private var error: String?
    @State private var isCreating = false
    @State private var isCancelling = false
    @State private var qrImage: Image?
    @State private var showCancelConfirm = false

    var body: some View {
        NavigationView {
            VStack(spacing: 24) {
                if let url = inviteURL {
                    Text("Share this invite with one person.")
                        .font(.subheadline)
                        .foregroundColor(Theme.secondaryText)
                        .multilineTextAlignment(.center)

                    if let qr = qrImage {
                        qr
                            .interpolation(.none)
                            .resizable()
                            .scaledToFit()
                            .frame(width: 220, height: 220)
                            .padding(8)
                            .background(Theme.white)
                            .cornerRadius(12)
                            .shadow(radius: 4)
                    }

                    Text("The link expires in 15 minutes and can be used only once.")
                        .font(.caption)
                        .foregroundColor(Theme.secondaryText)
                        .multilineTextAlignment(.center)

                    Button(action: { share(url: url) }) {
                        Label("Share Invite Link", systemImage: "square.and.arrow.up")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent).tint(Theme.activeBlue)

                    if let e = error {
                        Text(e)
                            .foregroundColor(Theme.red)
                            .font(.footnote)
                            .multilineTextAlignment(.center)
                    }

                    // Explicit Cancel Invite — POSTs /api/private/invites/cancel and
                    // deletes the pending key only after server confirms.
                    Button(role: .destructive, action: { showCancelConfirm = true }) {
                        Group {
                            if isCancelling {
                                ProgressView()
                            } else {
                                Label("Cancel Invite", systemImage: "xmark.circle")
                            }
                        }
                        .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.bordered).foregroundColor(Theme.appText)
                    .disabled(isCancelling)
                    .confirmationDialog(
                        "Cancel this invite?",
                        isPresented: $showCancelConfirm,
                        titleVisibility: .visible
                    ) {
                        Button("Cancel Invite", role: .destructive) { cancelInvite() }
                        Button("Keep Open", role: .cancel) {}
                    } message: {
                        Text("The invite link will be revoked on the server and the pending key will be deleted. The QR code will no longer work.")
                    }

                } else if isCreating {
                    ProgressView("Creating invite…")
                } else {
                    Text("Create a one-time invite link to connect with someone.")
                        .font(.subheadline)
                        .foregroundColor(Theme.secondaryText)
                        .multilineTextAlignment(.center)
                        .padding()

                    if let e = error {
                        Text(e)
                            .foregroundColor(Theme.red)
                            .font(.footnote)
                            .multilineTextAlignment(.center)
                    }

                    Button(action: createInvite) {
                        Text("Create Invite Link")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent).tint(Theme.activeBlue)
                }

                Spacer()
            }
            .padding()
            .navigationTitle("Invite a Contact")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    // Closing the screen DOES NOT cancel the invite; the pending
                    // key persists in the Keychain until expiry or explicit Cancel.
                    Button("Close") { dismiss() }
                }
            }
        }
    }

    private func createInvite() {
        isCreating = true
        error = nil
        Task {
            defer { isCreating = false }
            do {
                // Generate the 32-byte conversation key BEFORE getting the token.
                let rawKey = PrivateCrypto.generateConversationKey()
                let keyB64 = base64url(rawKey)

                let created = try await PrivateAPIClient.shared.createInvite()

                // Build the deep-link URL with the key in the FRAGMENT only.
                var components = URLComponents()
                components.scheme = "ananse"
                components.host = "invite"
                // Fragment carries both token and key — never hits the server.
                components.fragment = "token=\(created.token)&key=\(keyB64)"

                guard let url = components.url else {
                    // Local setup failed after the server created the invite —
                    // best-effort cancel it so no orphan invite survives.
                    try? await PrivateAPIClient.shared.cancelInvite(token: created.token)
                    error = "Failed to build invite URL"
                    return
                }

                // Securely stash the pending key in the Keychain FIRST, keyed by
                // the server's inviteKeyId (SHA-256 hex of the raw token). The
                // invite is not exposed/shared until this succeeds — otherwise a
                // shared link could reference a key that was never saved.
                let inviteKeyId = PrivateCrypto.inviteKeyId(forToken: created.token)
                do {
                    try PrivateKeychain.savePendingInviteKey(rawKey, inviteKeyId: inviteKeyId)
                } catch {
                    // Local key storage failed after server creation — best-effort
                    // cancel the server invite and surface the failure. Nothing is
                    // exposed to the user.
                    try? await PrivateAPIClient.shared.cancelInvite(token: created.token)
                    self.error = "Could not securely store the invite key on this device. The invite was cancelled. Please try again."
                    return
                }

                // Pending key saved — only now expose the invite for sharing.
                inviteURL = url
                inviteToken = created.token
                qrImage = generateQR(from: url.absoluteString)
            } catch {
                self.error = error.localizedDescription
            }
        }
    }

    /// Explicit Cancel: POST /api/private/invites/cancel with the server token,
    /// then delete the pending key only after the server confirms. On failure,
    /// the pending key is preserved so the user can retry.
    private func cancelInvite() {
        guard let token = inviteToken else { return }
        isCancelling = true
        error = nil
        Task {
            defer { isCancelling = false }
            let inviteKeyId = PrivateCrypto.inviteKeyId(forToken: token)
            do {
                try await PrivateAPIClient.shared.cancelInvite(token: token)
                // Server confirmed cancellation (204, including the idempotent
                // already-cancelled case) — only now remove the local pending key.
                PrivateKeychain.deletePendingInviteKey(inviteKeyId: inviteKeyId)
                dismiss()
            } catch APIError.httpError(410, let msg) {
                // The invite is already used or expired: it can no longer be
                // accepted, so its pending key is now useless. Drop the local key
                // and tell the user truthfully — do NOT pretend we cancelled it.
                PrivateKeychain.deletePendingInviteKey(inviteKeyId: inviteKeyId)
                self.error = msg ?? "This invite can no longer be cancelled because it was already used or expired. It has been cleared from this device."
            } catch {
                // Any other failure (network, etc.): keep local state intact so
                // the user can retry cancellation.
                self.error = "Could not cancel invite: \(error.localizedDescription)"
            }
        }
    }

    private func share(url: URL) {
        let vc = UIActivityViewController(activityItems: [url], applicationActivities: nil)
        if let scene = UIApplication.shared.connectedScenes.first as? UIWindowScene,
           let window = scene.windows.first,
           let root = window.rootViewController {
            root.present(vc, animated: true)
        }
    }

    private func generateQR(from string: String) -> Image? {
        let context = CIContext()
        let filter = CIFilter.qrCodeGenerator()
        filter.message = Data(string.utf8)
        filter.correctionLevel = "M"
        guard let output = filter.outputImage else { return nil }
        let scaled = output.transformed(by: CGAffineTransform(scaleX: 10, y: 10))
        guard let cgImage = context.createCGImage(scaled, from: scaled.extent) else { return nil }
        return Image(decorative: cgImage, scale: 1, orientation: .up)
    }

    private func base64url(_ data: Data) -> String {
        data.base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
    }
}

// MARK: - Incoming invite handler view

struct AcceptInviteView: View {
    let token: String
    let sharedKey: Data?  // parsed from URL fragment

    @EnvironmentObject private var store: PrivateStore
    @Environment(\.dismiss) private var dismiss

    @State private var preview: InvitePreview?
    @State private var error: String?
    @State private var isLoading = true
    @State private var isAccepting = false
    @State private var accepted = false

    /// A native invite is only acceptable if the URL fragment carried a valid
    /// 32-byte key.
    private var hasValidKey: Bool { (sharedKey?.count ?? 0) == 32 }

    var body: some View {
        NavigationView {
            Group {
                if isLoading {
                    ProgressView("Checking invite…")
                } else if accepted {
                    VStack(spacing: 16) {
                        Image(systemName: "checkmark.circle.fill")
                            .font(.system(size: 60))
                            .foregroundColor(.green)
                        Text("Contact added!")
                            .font(.title2).bold()
                        Button("Done") { dismiss() }
                            .buttonStyle(.borderedProminent).tint(Theme.activeBlue)
                    }
                } else if let p = preview {
                    ScrollView {
                        VStack(alignment: .leading, spacing: 20) {
                            VStack(alignment: .leading, spacing: 8) {
                                Text("Invite from:")
                                    .font(.caption).foregroundColor(Theme.secondaryText)
                                Text(p.inviterHandle ?? "Anonymous")
                                    .font(.title3).bold()
                                Text("Fingerprint: \(p.inviterFingerprint)")
                                    .font(.caption2).foregroundColor(Theme.secondaryText)
                                    .lineLimit(2)
                            }

                            if p.isSelf {
                                Label("This is your own invite link.", systemImage: "exclamationmark.triangle")
                                    .foregroundColor(Theme.gold)
                            } else if p.alreadyContact {
                                Label("You are already connected with this person.", systemImage: "info.circle")
                                    .foregroundColor(Theme.activeBlue)
                            } else if !hasValidKey {
                                Label("This invite link is missing its encryption key and cannot be accepted. Ask for a new invite.", systemImage: "key.slash")
                                    .foregroundColor(Theme.red)
                            }

                            if let e = error {
                                Text(e).foregroundColor(Theme.red).font(.footnote)
                            }

                            if !p.isSelf {
                                Button(action: acceptInvite) {
                                    Group {
                                        if isAccepting {
                                            ProgressView()
                                        } else {
                                            Text("Accept & Add Contact")
                                        }
                                    }
                                    .frame(maxWidth: .infinity)
                                }
                                .buttonStyle(.borderedProminent).tint(Theme.activeBlue)
                                .disabled(isAccepting || !hasValidKey)
                            }

                            Button("Cancel") { dismiss() }
                                .frame(maxWidth: .infinity)
                                .buttonStyle(.bordered).foregroundColor(Theme.appText)
                        }
                        .padding()
                    }
                } else {
                    VStack(spacing: 16) {
                        if let e = error {
                            Text(e).foregroundColor(Theme.red).multilineTextAlignment(.center)
                        }
                        Button("Close") { dismiss() }.buttonStyle(.bordered).foregroundColor(Theme.appText)
                    }.padding()
                }
            }
            .background(Theme.appBackground.ignoresSafeArea())
            .navigationTitle("Accept Invite")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
            }
        }
        .task { await loadPreview() }
    }

    private func loadPreview() async {
        isLoading = true
        defer { isLoading = false }
        do {
            preview = try await PrivateAPIClient.shared.previewInvite(token: token)
        } catch {
            self.error = error.localizedDescription
        }
    }

    private func acceptInvite() {
        isAccepting = true
        error = nil
        Task {
            defer { isAccepting = false }
            do {
                _ = try await store.acceptInvite(token: token, sharedKey: sharedKey)
                accepted = true
            } catch {
                self.error = error.localizedDescription
            }
        }
    }
}
