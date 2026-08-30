// ContactsView.swift
// Contacts list for the private messenger.
// Lets users open a chat or start a new invite.

import SwiftUI

struct ContactsView: View {
    @EnvironmentObject private var store: PrivateStore

    @State private var showInvite = false
    @State private var pendingInviteURL: IdentifiableURL?
    @State private var showEraseConfirm1 = false
    @State private var showEraseConfirm2 = false
    @State private var showEraseError = false

    var body: some View {
        List {
            if store.contacts.isEmpty && !store.isLoadingContacts {
                Section {
                    Text("No contacts yet. Create an invite link to connect with someone.")
                        .foregroundColor(Theme.secondaryText)
                        .font(.subheadline)
                        .listRowBackground(Theme.white)
                }
            }
            ForEach(store.contacts) { contact in
                NavigationLink {
                    ChatView(contact: contact)
                } label: {
                    ContactRow(contact: contact)
                }
                .listRowBackground(Theme.white)
            }

            Section {
                Button(role: .destructive) {
                    showEraseConfirm1 = true
                } label: {
                    if store.isErasing {
                        HStack {
                            ProgressView()
                            Text("Erasing…").foregroundColor(Theme.red)
                        }
                    } else {
                        Label("Erase Local Identity", systemImage: "trash")
                            .foregroundColor(Theme.red)
                    }
                }
                .disabled(store.isErasing)
                .listRowBackground(Theme.white)
            } footer: {
                Text("Permanently removes your server account and device identity, all contact keys and pending invites from this phone. This cannot be undone.")
                    .foregroundColor(Theme.secondaryText)
            }
        }
        .safeScrollContentBackground()
        .background(Theme.appBackground.ignoresSafeArea())
        .listStyle(.insetGrouped)
        .navigationTitle("Messages")
        .toolbar {
            ToolbarItem(placement: .navigationBarTrailing) {
                Button(action: { showInvite = true }) {
                    Image(systemName: "person.badge.plus")
                }
            }
        }
        // First erase confirmation
        .confirmationDialog(
            "Erase local identity?",
            isPresented: $showEraseConfirm1,
            titleVisibility: .visible
        ) {
            Button("Erase Local Identity", role: .destructive) {
                showEraseConfirm2 = true
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This wipes your server account, device identity, every contact key and any pending invites from this phone. The shared key and all messages cannot be recovered.")
        }
        // Second erase confirmation
        .confirmationDialog(
            "Are you absolutely sure?",
            isPresented: $showEraseConfirm2,
            titleVisibility: .visible
        ) {
            Button("Yes, erase everything", role: .destructive) {
                store.eraseLocalIdentity()
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("There is no recovery. You will need a new invite to reconnect with anyone.")
        }
        // Server erasure failure alert
        .alert("Could not erase account", isPresented: $showEraseError) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(store.eraseError ?? "The server account could not be deleted. Your local identity has been kept. Please try again.")
        }
        .onChange(of: store.eraseError) { newValue in
            if newValue != nil { showEraseError = true }
        }
        .refreshable {
            await store.loadContacts()
        }
        .overlay {
            if store.isLoadingContacts && store.contacts.isEmpty {
                ProgressView()
            }
        }
        .sheet(isPresented: $showInvite) {
            InviteView()
                .environmentObject(store)
        }
        .sheet(item: $pendingInviteURL, onDismiss: {
            // Sheet dismissed (accepted or cancelled) — nothing else to clear;
            // the store's transient URL was already consumed when we presented.
        }) { wrapper in
            if let (token, key) = parseInviteURL(wrapper.url) {
                AcceptInviteView(token: token, sharedKey: key)
                    .environmentObject(store)
            }
        }
        // Present any deep-link invite the store received (possibly on cold
        // launch, before this view existed) exactly once. ContactsView only
        // exists after consent and successful authentication, so presenting
        // here preserves the consent gate. Consume the transient URL from the
        // store so it is handed off exactly once.
        .onChange(of: store.pendingInviteURL) { newValue in
            if newValue != nil { presentPendingInviteIfNeeded() }
        }
        .task {
            presentPendingInviteIfNeeded()
            await store.loadContacts()
        }
    }

    /// Move any pending invite URL out of the store's transient state and into
    /// this view's sheet-item state, presenting it exactly once.
    private func presentPendingInviteIfNeeded() {
        guard pendingInviteURL == nil else { return }
        if let url = store.takePendingInviteURL() {
            pendingInviteURL = IdentifiableURL(url: url)
        }
    }

    private func parseInviteURL(_ url: URL) -> (token: String, key: Data?)? {
        guard let fragment = url.fragment else { return nil }
        // fragment = "token=TOKEN&key=KEY"
        var params: [String: String] = [:]
        for part in fragment.split(separator: "&") {
            let kv = part.split(separator: "=", maxSplits: 1)
            if kv.count == 2 { params[String(kv[0])] = String(kv[1]) }
        }
        guard let token = params["token"] else { return nil }
        let key = params["key"].flatMap { PrivateCrypto.base64urlDecode($0) }
        return (token, key)
    }
}

// MARK: - Contact row

struct ContactRow: View {
    let contact: ContactInfo

    var body: some View {
        HStack(spacing: 12) {
            Circle()
                .fill(Theme.activeBlue.opacity(0.15))
                .frame(width: 40, height: 40)
                .overlay(
                    Text(initials(for: contact.handle))
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundColor(Theme.activeBlue)
                )

            VStack(alignment: .leading, spacing: 2) {
                Text(contact.handle ?? "Anonymous")
                    .font(.body)
                    .foregroundColor(Theme.appText)
            }

            Spacer()
        }
        .padding(.vertical, 2)
    }

    private func initials(for handle: String?) -> String {
        guard let h = handle, !h.isEmpty else { return "?" }
        return String(h.prefix(1)).uppercased()
    }
}

// MARK: - Identifiable URL wrapper for sheet(item:)

struct IdentifiableURL: Identifiable {
    let url: URL
    var id: String { url.absoluteString }
}

private extension View {
    @ViewBuilder
    func safeScrollContentBackground() -> some View {
        if #available(iOS 16.0, *) {
            scrollContentBackground(.hidden)
        } else {
            self
        }
    }
}
