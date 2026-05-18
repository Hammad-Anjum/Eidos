import SwiftUI

/// Lets the user swap between Gemma 4 variants (E2B ↔ E4B). Swapping:
///   1. Marks the new variant as selected (`eidos.variant` UserDefault).
///   2. If the new variant's files aren't on disk, kicks off a download.
///   3. Unloads the current model and loads the new one.
///
/// All steps flow through `ModelDownloader` so the existing download UI
/// (progress bar, thermal guards, phase transitions) just works.
struct ModelSwitcherView: View {

    @Environment(AppContainer.self) private var container
    @State private var selectedVariant: GemmaVariant
    @State private var isSwapping = false
    @State private var errorMessage: String?

    init() {
        // Initial selection reflects the currently-active variant at
        // view construction — re-evaluated when the user taps a row.
        _selectedVariant = State(initialValue: .defaultForDevice)
    }

    var body: some View {
        let dl = container.modelDownloader
        Form {
            Section {
                ForEach(GemmaVariant.selectableCases, id: \.self) { variant in
                    variantRow(variant, isCurrent: variant == dl.selectedVariant)
                        .contentShape(Rectangle())
                        .onTapGesture {
                            guard variant.isAvailableOnThisDevice else { return }
                            selectedVariant = variant
                        }
                }
            } header: {
                Text("Available models")
            } footer: {
                Text("External tester builds use E2B only until real-device model loading is validated. Larger variants stay dev-only for now.")
                    .font(.caption2)
            }

            if selectedVariant != dl.selectedVariant {
                Section {
                    Button {
                        Task { await performSwap() }
                    } label: {
                        HStack {
                            if isSwapping {
                                ProgressView()
                                    .controlSize(.small)
                                    .padding(.trailing, 6)
                                Text("Switching…")
                            } else {
                                Image(systemName: "arrow.2.squarepath")
                                Text("Switch to \(selectedVariant.displayName)")
                            }
                        }
                        .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(isSwapping)
                } footer: {
                    if let msg = errorMessage {
                        Text(msg).font(.caption).foregroundStyle(.red)
                    } else {
                        let approxGB = selectedVariant.approximateDiskBytes / 1_000_000_000
                        Text("Switching will download ~\(approxGB) GB if you don't already have this model on device. The app will briefly become unavailable during the load.")
                            .font(.caption2)
                    }
                }
            }
        }
        .navigationTitle("Switch model")
        #if os(iOS)
        .navigationBarTitleDisplayMode(.inline)
        #endif
        .onAppear { selectedVariant = dl.selectedVariant }
    }

    // MARK: - Row

    @ViewBuilder
    private func variantRow(_ variant: GemmaVariant, isCurrent: Bool) -> some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text(variant.displayName)
                    .font(.body)
                Text("~\(variant.approximateDiskBytes / 1_000_000_000) GB  ·  \(variant.descriptionText)")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            if isCurrent {
                Label("Active", systemImage: "checkmark.seal.fill")
                    .labelStyle(.iconOnly)
                    .foregroundStyle(.green)
            } else if selectedVariant == variant {
                Image(systemName: "largecircle.fill.circle")
                    .foregroundStyle(.tint)
            } else {
                Image(systemName: "circle")
                    .foregroundStyle(.secondary)
            }
        }
        .opacity(variant.isAvailableOnThisDevice ? 1 : 0.4)
    }

    // MARK: - Swap logic

    private func performSwap() async {
        isSwapping = true
        errorMessage = nil
        defer { isSwapping = false }

        let dl = container.modelDownloader
        EidosLogger.shared.log(.info, category: .model, event: "model.swap.start", payload: [
            "from": dl.selectedVariant.rawValue,
            "to": selectedVariant.rawValue,
        ])

        // Unload the currently loaded model so it releases RAM before
        // the new one is mmap'd.
        await container.gemma.unload()

        // Persist the new selection FIRST. `ModelDownloader.download`
        // consults `selectedVariant` to decide where to write.
        dl.selectedVariant = selectedVariant
        dl.clearDownloadedModelState()

        await dl.download(variant: selectedVariant)

        switch dl.phase {
        case .ready:
            EidosLogger.shared.log(.info, category: .model, event: "model.swap.done")
        case .failed(let msg):
            errorMessage = msg
            EidosLogger.shared.log(.error, category: .model, event: "model.swap.failed",
                message: msg, failure: .modelLoad)
        default:
            errorMessage = "Unexpected phase: \(dl.phase)"
        }
    }
}

// MARK: - Supplementary ViewModel glue

private extension GemmaVariant {
    /// Short description shown in the row. Kept here rather than on the
    /// enum itself because it's UI copy and may change without affecting
    /// the model config source of truth.
    var descriptionText: String {
        switch self {
        case .e2b: "1B params · faster, lower RAM"
        case .e4b: "4B params · slower, higher quality"
        }
    }
}
