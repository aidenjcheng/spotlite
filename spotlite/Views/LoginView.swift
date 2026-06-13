import SwiftUI

struct LoginView: View {
    @Environment(AppModel.self) private var model
    @State private var clientIDInput = ""

    var body: some View {
        VStack(spacing: 24) {
            Image(systemName: "music.note.house.fill")
                .font(.system(size: 56, weight: .bold))
                .foregroundStyle(SpotliteTheme.accent)

            VStack(spacing: 8) {
                Text("Spotlite")
                    .font(.system(size: 32, weight: .bold, design: .rounded))
                    .foregroundStyle(SpotliteTheme.textPrimary)
                Text("A lightweight native Spotify client for Mac.")
                    .font(.subheadline)
                    .foregroundStyle(SpotliteTheme.textSecondary)
            }

            VStack(alignment: .leading, spacing: 8) {
                Text("Spotify Client ID")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(SpotliteTheme.textSecondary)
                TextField("Paste your Client ID", text: $clientIDInput)
                    .textFieldStyle(.roundedBorder)
                    .onAppear { clientIDInput = model.auth.clientID }
            }
            .frame(maxWidth: 360)

            VStack(spacing: 12) {
                Button {
                    model.auth.clientID = clientIDInput.trimmingCharacters(in: .whitespacesAndNewlines)
                    do {
                        try model.auth.beginLogin()
                    } catch {
                        model.bannerError = error.localizedDescription
                    }
                } label: {
                    Text(model.auth.isLoading ? "Connecting…" : "Connect with Spotify")
                        .frame(maxWidth: 360)
                }
                .buttonStyle(.borderedProminent)
                .tint(SpotliteTheme.accent)
                .disabled(clientIDInput.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || model.auth.isLoading)

                Text("Requires Spotify Premium. Add redirect URI `spotlite://callback` in your Spotify Developer app.")
                    .font(.caption)
                    .foregroundStyle(SpotliteTheme.textSecondary)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: 420)
            }

            if let error = model.auth.lastError ?? model.bannerError {
                Text(error)
                    .font(.caption)
                    .foregroundStyle(.red)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: 420)
            }
        }
        .padding(40)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
