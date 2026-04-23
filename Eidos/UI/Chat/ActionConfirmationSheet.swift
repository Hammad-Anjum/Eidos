import SwiftUI

/// Sheet that asks the user to confirm an `AppAction` before it fires.
/// Eidos never opens another app without this — it's the iOS-friendly
/// version of "cross-app control". Dismissal is non-destructive: the
/// action just gets dropped, nothing is sent.
struct ActionConfirmationSheet: View {
    let action: AppAction
    let registry: AppActionRegistry
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(spacing: 20) {
            Spacer(minLength: 20)

            Image(systemName: action.systemImage)
                .font(.system(size: 48))
                .foregroundStyle(.tint)

            Text(action.confirmationTitle)
                .font(.title3.bold())
                .multilineTextAlignment(.center)

            if let body = action.confirmationBody {
                ScrollView {
                    Text(body)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding()
                        .background(Color.secondary.opacity(0.1))
                        .clipShape(RoundedRectangle(cornerRadius: 10))
                        .textSelection(.enabled)
                }
                .frame(maxHeight: 200)
            }

            if !registry.canOpen(action) {
                Label(
                    "The target app isn't installed.",
                    systemImage: "exclamationmark.triangle"
                )
                .font(.footnote)
                .foregroundStyle(.orange)
            }

            Text("You'll tap Send in the target app yourself — Eidos never sends anything on its own.")
                .font(.caption)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)

            Spacer()

            HStack(spacing: 12) {
                Button("Cancel", role: .cancel) {
                    registry.dismiss(action)
                    dismiss()
                }
                .buttonStyle(.bordered)
                .controlSize(.large)
                .frame(maxWidth: .infinity)

                Button {
                    Task {
                        await registry.execute(action)
                        dismiss()
                    }
                } label: {
                    Label("Open", systemImage: "arrow.up.right.square.fill")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
                .disabled(!registry.canOpen(action))
            }
        }
        .padding()
        .presentationDetents([.medium, .large])
    }
}
