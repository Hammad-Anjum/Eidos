import SwiftUI

struct OnboardingView: View {
    @Environment(AppContainer.self) private var container

    var body: some View {
        VStack(spacing: 24) {
            Image(systemName: "lock.shield.fill")
                .font(.system(size: 64))
                .foregroundStyle(.tint)
            Text("Welcome to Eidos")
                .font(.largeTitle.bold())
            Text("Your private, on-device AI assistant. No data ever leaves your iPhone.")
                .multilineTextAlignment(.center)
                .foregroundStyle(.secondary)
            Spacer()
        }
        .padding()
    }
}
