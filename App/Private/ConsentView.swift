// ConsentView.swift
// First-run explicit consent screen. Shown once before any identity is
// created. No recovery, no archive, availability-only delivery.
// Also enumerates limitations that cannot be controlled by the app.

import SwiftUI

struct ConsentView: View {
    var onAccept: () -> Void
    var onDecline: () -> Void

    @State private var accepted = false

    var body: some View {
        NavigationView {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    Text("Private Messenger — Before You Begin")
                        .font(.title2).bold()
                        .padding(.top)
                        .foregroundColor(Theme.appText)

                    Group {
                        SectionHeader("How this works")
                        Text("""
This is a privacy-first messenger. Messages are encrypted on your device before they leave it, \
and decrypted only on the recipient's device. The server relays encrypted envelopes only; it \
cannot read your messages.
""")
                        .foregroundColor(Theme.secondaryText)
                    }

                    Group {
                        SectionHeader("No history, no recovery")
                        Text("""
• Messages exist only in memory while a chat is open. They are never written to disk.
• If you close the app, switch apps, or end the conversation, all messages are gone \
permanently — there is no archive and no way to recover them.
• There is no account recovery. If you uninstall the app your identity is lost.
""")
                        .foregroundColor(Theme.secondaryText)
                    }

                    Group {
                        SectionHeader("Availability-only delivery")
                        Text("""
• Delivery succeeds only while the recipient has the conversation open and \
is actively waiting. If they are not, the encrypted message is not uploaded, \
stored, or queued — it is simply not delivered.
• Delivery is not guaranteed. There are no read receipts.
""")
                        .foregroundColor(Theme.secondaryText)
                    }

                    Group {
                        SectionHeader("What data we handle")
                        Text("""
• Network addresses (IP addresses): Ananse momentarily handles your network address to \
deliver traffic to the correct device. These are not retained, not logged, and not used \
to track your location or movement.
• Pseudonymous public key: Your device generates a key pair locally. The public key (and \
an optional display handle) is stored on our server to identify your account. It is not \
linked to your real name or location.
• Contact links: When you exchange invites, both sides' pseudonymous identifiers are \
associated on the server solely to enable delivery. These links can be removed at any time \
by ending the conversation.
• No permissions requested or used for location, address book, advertising, or tracking. \
We do not use device advertising identifiers or share data with ad networks.
""")
                        .foregroundColor(Theme.secondaryText)
                    }

                    Group {
                        SectionHeader("Limitations we cannot control")
                        Text("""
• Screenshots: The recipient can screenshot your messages.
• Copied text: The recipient can copy and forward your messages.
• Recipient behaviour: We cannot prevent the recipient from sharing content.
• Other mobile platforms: Recipients on Android or other platforms use compatible apps \
whose behaviour we cannot guarantee.
• ISPs and network providers: Traffic metadata (not content) may be visible to ISPs.
• Device compromise: If either device is compromised, messages may be exposed.
""")
                        .foregroundColor(Theme.secondaryText)
                    }

                    Group {
                        SectionHeader("Contacts")
                        Text("""
Contacts are added only by exchanging a one-time invite link. You must confirm before adding \
any contact. Ending a conversation permanently deletes the contact, the shared conversation \
key, and all messages — they cannot be recovered.
""")
                        .foregroundColor(Theme.secondaryText)
                    }

                    Toggle(isOn: $accepted) {
                        Text("I understand and accept these terms")
                            .font(.subheadline)
                            .foregroundColor(Theme.appText)
                    }
                    .padding(.top, 8)
                    .tint(Theme.activeBlue)

                    VStack(spacing: 12) {
                        Button(action: {
                            guard accepted else { return }
                            PrivateKeychain.consentGiven = true
                            onAccept()
                        }) {
                            Text("Continue")
                                .frame(maxWidth: .infinity)
                        }
                        .buttonStyle(.borderedProminent)
                        .tint(Theme.activeBlue)
                        .disabled(!accepted)

                        Button(action: onDecline) {
                            Text("No thanks")
                                .frame(maxWidth: .infinity)
                        }
                        .buttonStyle(.bordered)
                        .foregroundColor(Theme.secondaryText)
                    }
                    .padding(.bottom, 24)
                }
                .padding(.horizontal)
            }
            .background(Theme.appBackground.ignoresSafeArea())
            .navigationTitle("Privacy Notice")
            .navigationBarTitleDisplayMode(.inline)
        }
    }
}

private struct SectionHeader: View {
    let title: String
    init(_ title: String) { self.title = title }
    var body: some View {
        Text(title)
            .font(.headline)
            .foregroundColor(Theme.appText)
            .padding(.top, 4)
    }
}
