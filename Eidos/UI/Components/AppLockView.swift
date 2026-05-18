import SwiftUI

/// Full-screen lock view that obscures the entire app until the user
/// authenticates via FaceID / TouchID / device passcode. Presented by
/// `EidosApp` as a `.fullScreenCover` whenever `AppLockController.isLocked`
/// is true.
struct AppLockView: View {
    @Environment(AppLockController.self) private var lock
    @State private var isAuthenticating: Bool = false

    var body: some View {
        ZStack {
            LinearGradient(
                colors: [
                    Color(.systemBackground),
                    Color.accentColor.opacity(0.18),
                ],
                startPoint: .top,
                endPoint: .bottom
            )
            .ignoresSafeArea()

            VStack(spacing: 22) {
                Image(systemName: "lock.shield.fill")
                    .font(.system(size: 64, weight: .light))
                    .foregroundStyle(.tint)

                Text("Eidos is locked")
                    .font(.title2.weight(.semibold))

                Text("Authenticate to access your private AI.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 40)

                if let err = lock.lastErrorMessage {
                    Label(err, systemImage: "exclamationmark.triangle")
                        .font(.caption)
                        .foregroundStyle(.orange)
                        .padding(.horizontal, 40)
                        .multilineTextAlignment(.center)
                }

                Button {
                    triggerAuth()
                } label: {
                    Label(
                        isAuthenticating ? "Authenticating..." : "Unlock",
                        systemImage: "faceid"
                    )
                    .font(.body.weight(.semibold))
                    .frame(maxWidth: 220)
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
                .disabled(isAuthenticating)
                .padding(.top, 8)
            }
        }
        .onAppear {
            // Auto-trigger authentication on first appearance so the
            // user doesn't have to tap an extra button in the common
            // case. Manual button is available as a fallback if the
            // first prompt is dismissed.
            triggerAuth()
        }
    }

    private func triggerAuth() {
        guard !isAuthenticating else { return }
        isAuthenticating = true
        Task { @MainActor in
            await lock.authenticate()
            isAuthenticating = false
        }
    }
}
