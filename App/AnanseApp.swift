import SwiftUI

@main
struct AnanseApp: App {
    @Environment(\.scenePhase) private var scenePhase
    @StateObject private var store = PrivateStore()

    var body: some Scene {
        WindowGroup {
            MainNavigationView()
                .environmentObject(store)
                .onOpenURL { url in
                    handleIncomingURL(url)
                }
        }
        .onChange(of: scenePhase) { phase in
            if phase == .background {
                Task { @MainActor in
                    store.handleBackground()
                }
            }
        }
    }

    private func handleIncomingURL(_ url: URL) {
        Task { @MainActor in
            store.receiveInviteURL(url)
        }
    }
}

struct MainNavigationView: View {
    @EnvironmentObject private var store: PrivateStore
    @State private var openMessages = false

    var body: some View {
        NavigationView {
            ZStack {
                WriterView()
                    .environmentObject(store)

                NavigationLink(
                    destination: MessengerView().environmentObject(store),
                    isActive: $openMessages
                ) {
                    EmptyView()
                }
                .hidden()
            }
            .navigationBarHidden(true)
        }
        .navigationViewStyle(.stack)
        .accentColor(Theme.appText)
        .onAppear {
            openMessages = store.pendingInviteURL != nil
        }
        .onChange(of: store.pendingInviteURL) { inviteURL in
            openMessages = inviteURL != nil
        }
    }
}
