// ChatView.swift
// Active chat window. All message state lives in memory (PrivateStore).
// Messages are delivered live and never stored on device or server.
// Ending the conversation triggers a double-confirmation, then DELETE /contacts/{id}.

import SwiftUI
import UIKit

struct ChatView: View {
    let contact: ContactInfo

    @EnvironmentObject private var store: PrivateStore
    @Environment(\.dismiss) private var dismiss

    @State private var draft = ""
    @State private var selectedRange: NSRange = NSRange(location: 0, length: 0)
    @State private var manualAnnotations: [AnanseManualValueAnnotation] = []
    @State private var showEndConfirm1 = false
    @State private var showEndConfirm2 = false
    @State private var isEnding = false
    @State private var showEndError = false
    @State private var endError: String?
    @StateObject private var keyboardState = InAppKeyboardState()

    private var messages: [ChatMessage] {
        store.activeConversation?.messages ?? []
    }

    var body: some View {
        VStack(spacing: 0) {
            // Message list
            GeometryReader { messageSpace in
                ScrollViewReader { proxy in
                    ScrollView {
                        LazyVStack(alignment: .leading, spacing: 8) {
                            ForEach(messages) { msg in
                                MessageBubble(
                                    message: msg,
                                    automaticValues: keyboardState.autoValues,
                                    weightEm: keyboardState.hangingLine.emFactor,
                                    style: keyboardState.style,
                                    color: keyboardState.glyphColor,
                                    bubbleWidth: min(messageSpace.size.width * 0.72, 360)
                                )
                                    .id(msg.id)
                            }
                        }
                        .padding(.horizontal)
                        .padding(.top, 8)
                        .padding(.bottom, 4)
                    }
                    .onChange(of: messages.count) { _ in
                        if let last = messages.last {
                            withAnimation { proxy.scrollTo(last.id, anchor: .bottom) }
                        }
                    }
                    .onAppear {
                        if let last = messages.last {
                            proxy.scrollTo(last.id, anchor: .bottom)
                        }
                    }
                }
            }

            Divider()

            // Compose bar — using InAppKeyboardView for Ananse text entry
            VStack(spacing: 0) {
                HStack(spacing: 8) {
                    ZStack(alignment: .topLeading) {
                        RoundedRectangle(cornerRadius: 8)
                            .fill(Theme.appText.opacity(0.1))
                            .frame(minHeight: 44)

                        if draft.isEmpty {
                            Text("Message...")
                                .foregroundColor(Theme.secondaryText)
                                .padding(.horizontal, 12)
                                .padding(.top, 12)
                        }

                        EditableAnanseCanvas(
                            text: $draft,
                            selectedRange: $selectedRange,
                            automaticValues: keyboardState.autoValues,
                            manualAnnotations: manualAnnotations,
                            weightEm: keyboardState.hangingLine.emFactor,
                            style: keyboardState.style,
                            color: keyboardState.glyphColor,
                            fontSize: 24,
                            isEnglishMode: keyboardState.script == .english
                        )
                        .frame(height: 80)
                        .padding(.horizontal, 4)
                    }

                    Button(action: sendMessage) {
                        Image(systemName: "arrow.up.circle.fill")
                            .font(.system(size: 32))
                            .foregroundColor(draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? .secondary : Theme.activeBlue)
                    }
                    .disabled(draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || store.isSending)
                }
                .padding(.horizontal)
                .padding(.vertical, 8)
                .background(Theme.appBackground)

                InAppKeyboardView(
                    state: keyboardState,
                    text: $draft,
                    manualAnnotations: $manualAnnotations,
                    selectedRange: $selectedRange,
                    onReturn: sendMessage
                )
            }
        }
        .background(Theme.appBackground.ignoresSafeArea())
        .navigationTitle(contact.handle ?? "Anonymous")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .navigationBarTrailing) {
                Button(role: .destructive, action: { showEndConfirm1 = true }) {
                    Label("End conversation", systemImage: "xmark.circle")
                        .foregroundColor(Theme.red)
                }
            }
        }
        // First confirmation
        .confirmationDialog(
            "End this conversation?",
            isPresented: $showEndConfirm1,
            titleVisibility: .visible
        ) {
            Button("End Conversation", role: .destructive) {
                showEndConfirm2 = true
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This will permanently delete the contact and all messages. The shared key and all messages cannot be recovered. There is no undo.")
        }
        // Second confirmation
        .confirmationDialog(
            "Are you sure?",
            isPresented: $showEndConfirm2,
            titleVisibility: .visible
        ) {
            Button("Yes, delete everything", role: .destructive) {
                endConversation()
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("The contact, the shared conversation key, and all messages will be permanently gone and cannot be recovered.")
        }
        .alert("Could not end conversation", isPresented: $showEndError) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(endError ?? "The contact could not be deleted on the server. Nothing was removed. Please try again.")
        }
        .onAppear {
            keyboardState.restore()
            store.openConversation(contactId: contact.userId)
        }
        .onDisappear {
            // Only clear if we aren't in the middle of a deliberate end (which
            // handles its own cleanup)
            if !isEnding {
                store.clearConversation()
            }
        }
        // Erase the draft immediately when the app moves to the background so
        // iOS cannot snapshot, cache, or restore sensitive compose text.
        .onReceive(NotificationCenter.default.publisher(for: UIApplication.didEnterBackgroundNotification)) { _ in
            draft = ""
        }
    }

    private func sendMessage() {
        let text = draft.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return }
        draft = ""
        selectedRange = NSRange(location: 0, length: 0)
        // sendMessage is non-async: it spawns a tracked, cancellable Task in the
        // store so conversation teardown can abort the in-flight request.
        store.sendMessage(text: text, to: contact.userId)
    }

    private func endConversation() {
        isEnding = true
        Task {
            do {
                try await store.endConversation(contactId: contact.userId)
                await MainActor.run { dismiss() }
            } catch {
                // Server deletion failed — do NOT claim success. Keep the
                // conversation intact and surface the failure; resume polling.
                await MainActor.run {
                    isEnding = false
                    endError = error.localizedDescription
                    showEndError = true
                    store.openConversation(contactId: contact.userId)
                }
            }
        }
    }
}

// MARK: - Message bubble

struct MessageBubble: View {
    let message: ChatMessage
    let automaticValues: Bool
    let weightEm: CGFloat
    let style: PreviewGlyphStyle
    let color: PreviewGlyphColor
    let bubbleWidth: CGFloat

    var body: some View {
        HStack {
            if message.isMine { Spacer(minLength: 40) }

            VStack(alignment: message.isMine ? .trailing : .leading, spacing: 2) {
                AnanseDraftPreview(
                    text: message.text,
                    automaticValues: automaticValues,
                    manualAnnotations: [],
                    weightEm: weightEm,
                    style: style,
                    color: color,
                    isScrollEnabled: false,
                    fontSize: 24
                )
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .frame(width: bubbleWidth)
                .frame(minHeight: 44)
                .background(message.isMine ? Theme.white : Theme.activeBlue.opacity(0.1))
                .clipShape(RoundedRectangle(cornerRadius: 16))
                .shadow(color: Color.black.opacity(0.05), radius: 2, y: 1)

                statusLine
            }

            if !message.isMine { Spacer(minLength: 40) }
        }
    }

    @ViewBuilder
    private var statusLine: some View {
        switch message.sendStatus {
        case .pending:
            Text("Sending…")
                .font(.caption2)
                .foregroundColor(Theme.appText.opacity(0.6))
        case .rejected:
            // 503 from the server means the recipient was not actively waiting;
            // the message was never uploaded, stored, or queued anywhere.
            Label("Not delivered — recipient was not available. Message was not stored.", systemImage: "exclamationmark.triangle.fill")
                .font(.caption2)
                .foregroundColor(Theme.red)
        case .uncertain:
            // 504 — cross-worker delivery could not be confirmed. It may or may
            // not have reached the recipient; nothing was queued.
            Label("Delivery could not be confirmed — do not resend sensitive information. Nothing was queued.", systemImage: "questionmark.circle.fill")
                .font(.caption2)
                .foregroundColor(Theme.gold)
        case .sent:
            // "Delivered" here means the server confirmed receipt by the
            // recipient's live session. Nothing was stored on device or server.
            Text("Delivered · \(timeString(message.createdAt))")
                .font(.caption2)
                .foregroundColor(Theme.appText.opacity(0.6))
        }
    }

    private func timeString(_ date: Date) -> String {
        let f = DateFormatter()
        f.doesRelativeDateFormatting = true
        f.dateStyle = .none
        f.timeStyle = .short
        return f.string(from: date)
    }
}
