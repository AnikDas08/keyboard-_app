import SwiftUI

struct KeyboardSetupView: View {
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                VStack(alignment: .leading, spacing: 16) {
                    Text("System Keyboard Setup")
                        .font(.title2.bold())
                        .foregroundColor(Theme.appText)

                    Text("To write with Ananse in other apps, enable the companion keyboard.")
                        .foregroundColor(Theme.appText.opacity(0.8))

                    VStack(alignment: .leading, spacing: 12) {
                        Text("1. Open Settings → General → Keyboard → Keyboards → Add New Keyboard…")
                        Text("2. Choose \"Ananse Keyboard\".")
                        Text("3. In any text field, tap the globe icon to switch to it.")
                    }
                    .padding()
                    .background(Theme.appText.opacity(0.05))
                    .cornerRadius(12)

                    Button(action: {
                        if let url = URL(string: UIApplication.openSettingsURLString) {
                            UIApplication.shared.open(url)
                        }
                    }) {
                        Text("Open Settings")
                            .font(.headline)
                            .foregroundColor(.white)
                            .padding()
                            .frame(maxWidth: .infinity)
                            .background(Theme.red)
                            .cornerRadius(12)
                    }
                }

                VStack(alignment: .leading, spacing: 12) {
                    Text("Important Limitations")
                        .font(.headline)
                        .foregroundColor(Theme.appText)

                    Text("Inserted text is standard Latin letters (for example, typing Q inserts KW). Other apps normally show that readable Latin text because each app controls its own fonts.")
                        .font(.subheadline)
                        .foregroundColor(Theme.appText.opacity(0.7))

                    Text("The custom iOS keyboard cannot force other apps to use the Ananse font.")
                        .font(.subheadline)
                        .foregroundColor(Theme.appText.opacity(0.7))
                }
                .padding()
                .background(Theme.gold.opacity(0.1))
                .cornerRadius(12)
            }
            .padding()
        }
        .background(Theme.appBackground.ignoresSafeArea())
        .navigationTitle("Keyboard Setup")
        .navigationBarTitleDisplayMode(.inline)
    }
}