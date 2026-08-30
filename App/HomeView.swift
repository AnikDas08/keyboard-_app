import SwiftUI

struct HomeView: View {
    @EnvironmentObject private var store: PrivateStore
    @State private var openMessages = false

    var body: some View {
        NavigationView {
            ZStack {
                Theme.appBackground.ignoresSafeArea()

                NavigationLink(
                    destination: MessengerView(),
                    isActive: $openMessages
                ) {
                    EmptyView()
                }
                .hidden()

                VStack(spacing: 48) {
                    VStack(spacing: 16) {
                        Text("A")
                            .font(.ananse(size: 96, style: .classic))
                            .foregroundColor(Theme.gold)
                            .shadow(color: Theme.gold.opacity(0.3), radius: 10, x: 0, y: 5)

                        Text("Ananse")
                            .font(.system(size: 32, weight: .bold, design: .serif))
                            .foregroundColor(Theme.appText)
                            .tracking(2)
                    }
                    .padding(.top, 60)

                    VStack(spacing: 24) {
                        NavigationLink(destination: WriterView()) {
                            HomeButton(title: "Write with Ananse", icon: "pencil.line", color: Theme.red)
                        }

                        NavigationLink(destination: MessengerView()) {
                            HomeButton(title: "Private Messages", icon: "lock.message.fill", color: Theme.green)
                        }
                    }
                    .padding(.horizontal, 32)

                    Spacer()

                    NavigationLink(destination: KeyboardSetupView()) {
                        HStack {
                            Image(systemName: "keyboard")
                            Text("System Keyboard Setup")
                        }
                        .font(.subheadline.bold())
                        .foregroundColor(Theme.appText.opacity(0.7))
                        .padding(.bottom, 32)
                    }
                }
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

struct HomeButton: View {
    let title: String
    let icon: String
    let color: Color

    var body: some View {
        HStack(spacing: 16) {
            Image(systemName: icon)
                .font(.system(size: 24))
            Text(title)
                .font(.system(size: 20, weight: .semibold, design: .serif))
            Spacer()
            Image(systemName: "chevron.right")
                .opacity(0.5)
        }
        .padding(.vertical, 20)
        .padding(.horizontal, 24)
        .foregroundColor(Theme.appText)
        .background(color.opacity(0.9))
        .cornerRadius(20)
        .overlay(
            RoundedRectangle(cornerRadius: 20)
                .stroke(color, lineWidth: 1)
        )
        .shadow(color: color.opacity(0.3), radius: 10, x: 0, y: 5)
    }
}