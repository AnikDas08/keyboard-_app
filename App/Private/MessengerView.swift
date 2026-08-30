// MessengerView.swift
// Root of the private messenger tab.
// Shows consent screen on first run, then authenticates and opens contacts.

import SwiftUI

struct MessengerView: View {
    @EnvironmentObject private var store: PrivateStore
    @State private var showConsent = !PrivateKeychain.consentGiven
    @State private var didDecline = false

    var body: some View {
        Group {
            if showConsent {
                ConsentView(
                    onAccept: {
                        showConsent = false
                        Task { await store.authenticate() }
                    },
                    onDecline: {
                        didDecline = true
                        showConsent = false
                    }
                )
            } else if didDecline {
                VStack(spacing: 16) {
                    Image(systemName: "lock.slash")
                        .font(.system(size: 48))
                        .foregroundColor(Theme.secondaryText)
                    Text("Private Messenger disabled")
                        .font(.headline)
                        .foregroundColor(Theme.appText)
                    Text("You can enable it later in this tab.")
                        .font(.subheadline)
                        .foregroundColor(Theme.secondaryText)
                    Button("Enable Private Messenger") {
                        didDecline = false
                        showConsent = true
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(Theme.activeBlue)
                }
                .padding()
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(Theme.appBackground.ignoresSafeArea())
            } else if let err = store.authError {
                VStack(spacing: 16) {
                    Image(systemName: "exclamationmark.triangle")
                        .font(.system(size: 48))
                        .foregroundColor(Theme.gold)
                    Text("Sign-in failed")
                        .font(.headline)
                        .foregroundColor(Theme.appText)
                    Text(err)
                        .font(.subheadline)
                        .foregroundColor(Theme.secondaryText)
                        .multilineTextAlignment(.center)
                    Button("Retry") {
                        Task { await store.authenticate() }
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(Theme.activeBlue)
                }
                .padding()
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(Theme.appBackground.ignoresSafeArea())
            } else if !store.isAuthenticated {
                VStack(spacing: 16) {
                    ProgressView("Connecting…")
                        .foregroundColor(Theme.appText)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(Theme.appBackground.ignoresSafeArea())
            } else {
                ContactsView()
                    .environmentObject(store)
            }
        }
        // After an "Erase Local Identity", the store deauthenticates and the
        // consent flag is cleared. Re-show the consent gate rather than spin.
        .onChange(of: store.isAuthenticated) { authed in
            if !authed && !PrivateKeychain.consentGiven {
                showConsent = true
                didDecline = false
            }
        }
    }
}
