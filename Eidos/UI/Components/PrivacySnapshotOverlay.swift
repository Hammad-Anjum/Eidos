import SwiftUI

/// Full-screen opaque overlay shown whenever the app's `scenePhase`
/// is anything other than `.active`. Prevents iOS's app-switcher
/// snapshot from capturing the user's chat or memory content. Privacy
/// table-stakes for an on-device AI product.
///
/// Layered ABOVE the chat/memory UI in `EidosApp.body` via `.overlay`.
struct PrivacySnapshotOverlay: View {
    var body: some View {
        ZStack {
            // Solid background so a snapshot taken at any moment after
            // scenePhase changes to .inactive shows only the brand,
            // never the underlying content.
            LinearGradient(
                colors: [
                    Color(.systemBackground),
                    Color.accentColor.opacity(0.18),
                ],
                startPoint: .top,
                endPoint: .bottom
            )
            .ignoresSafeArea()

            VStack(spacing: 14) {
                Image(systemName: "lock.shield")
                    .font(.system(size: 56, weight: .light))
                    .foregroundStyle(.tint)
                Text("Eidos")
                    .font(.title2.weight(.semibold))
                Text("Private and on-device")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }
        }
        .accessibilityHidden(true)
    }
}

#Preview {
    PrivacySnapshotOverlay()
}
