import SwiftUI
#if canImport(UIKit)
import UIKit
#endif

/// Preview-before-share sheet for the Eidos session report.
///
/// **Critical safety pattern.** The report includes Gemma-summarized
/// sections (themes, notable entries). LLM output going to a
/// professional reader without a verification pass is the failure mode
/// this sheet exists to prevent. The user MUST see and have an
/// opportunity to edit before tapping Share.
///
/// Flow:
///   1. Sheet opens, generation runs in the background.
///   2. While generating: spinner with "Generating on-device…" status.
///   3. When ready: full markdown rendered, with Edit / Share / Cancel.
///   4. Tapping Edit swaps into a `TextEditor` so the user can redact
///      or rewrite anything.
///   5. Tapping Share hands the markdown to the iOS share sheet via
///      `MemoryExporter.share(URL)`. The user picks the destination —
///      Eidos never sends.
///
/// Modular: this view depends only on `AppContainer` (for memory +
/// gemma) and `TherapistReportBuilder`. No changes to existing flows.
struct SessionReportPreviewView: View {

    @Environment(AppContainer.self) private var container
    @Environment(\.dismiss) private var dismiss

    @State private var markdown: String = ""
    @State private var phase: Phase = .generating
    @State private var isEditing: Bool = false
    @State private var generationError: String?

    private enum Phase: Equatable {
        case generating
        case ready
        case failed
    }

    var body: some View {
        NavigationStack {
            content
                .navigationTitle("Session report")
                #if os(iOS)
                .navigationBarTitleDisplayMode(.inline)
                #endif
                .toolbar { toolbar }
                .task { await generate() }
        }
    }

    // MARK: - Content

    @ViewBuilder
    private var content: some View {
        switch phase {
        case .generating:
            generatingView
        case .ready:
            readyView
        case .failed:
            failedView
        }
    }

    private var generatingView: some View {
        VStack(spacing: 18) {
            Spacer()
            ProgressView()
                .controlSize(.large)
            Text("Generating on-device…")
                .font(.headline)
            Text("Eidos is summarizing the week from your private memory. This typically takes 10–30 seconds on iPhone.")
                .font(.callout)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 32)
            Spacer()
        }
    }

    private var readyView: some View {
        Group {
            if isEditing {
                TextEditor(text: $markdown)
                    .font(.callout.monospaced())
                    .padding(.horizontal, 8)
                    .padding(.top, 4)
            } else {
                ScrollView {
                    // Markdown-rendered preview. SwiftUI `Text` with
                    // `LocalizedStringKey` honors basic markdown
                    // (headings, bold, lists, blockquotes) without a
                    // third-party renderer.
                    Text(LocalizedStringKey(markdown))
                        .font(.callout)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .textSelection(.enabled)
                        .padding(16)
                }
            }
        }
        .safeAreaInset(edge: .bottom) {
            previewActionBar
        }
    }

    private var previewActionBar: some View {
        HStack(spacing: 10) {
            Button {
                isEditing.toggle()
            } label: {
                Label(isEditing ? "Done editing" : "Edit",
                      systemImage: isEditing ? "checkmark" : "pencil")
                    .frame(maxWidth: .infinity, minHeight: 44)
            }
            .buttonStyle(.bordered)

            Button {
                share()
            } label: {
                Label("Share", systemImage: "square.and.arrow.up")
                    .frame(maxWidth: .infinity, minHeight: 44)
            }
            .buttonStyle(.borderedProminent)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .background(.ultraThinMaterial)
    }

    private var failedView: some View {
        VStack(spacing: 14) {
            Spacer()
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.system(size: 48))
                .foregroundStyle(.orange)
            Text("Couldn't build the report.")
                .font(.headline)
            if let generationError {
                Text(generationError)
                    .font(.caption.monospaced())
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 24)
            }
            Button("Try again") {
                Task { await generate() }
            }
            .buttonStyle(.borderedProminent)
            Spacer()
        }
    }

    @ToolbarContentBuilder
    private var toolbar: some ToolbarContent {
        ToolbarItem(placement: .topBarLeading) {
            Button("Cancel") { dismiss() }
        }
    }

    // MARK: - Actions

    /// Pulls inputs, calls `TherapistReportBuilder.build(...)`, and
    /// commits the result into `markdown`. Switches `phase` once
    /// generation lands. Idempotent — calling again retries.
    private func generate() async {
        phase = .generating
        generationError = nil

        let memory = container.memoryManager
        let gemma = container.gemma

        // Records (metadata) — cheap, all in-memory.
        let allRecords = await memory.index.all

        // Journal bodies (only) — needed for Gemma summarization.
        // Keep the disk reads tight: load only entries tagged "journal"
        // whose updatedAt falls inside the rolling 7-day window.
        let calendar = Calendar.current
        let weekStart = calendar.date(byAdding: .day, value: -6, to: Date())
            .map { calendar.startOfDay(for: $0) } ?? Date()
        let weekJournalIDs = allRecords
            .filter { $0.tags.contains("journal") && $0.updatedAt >= weekStart }
            .map { $0.id }

        var journalBodies: [(date: Date, body: String)] = []
        for id in weekJournalIDs {
            if let entry = try? await memory.load(id: id) {
                journalBodies.append((date: entry.updatedAt, body: entry.body))
            }
        }

        let bytes = await memory.diskUsageBytes()
        let info = Bundle.main.infoDictionary
        let version = info?["CFBundleShortVersionString"] as? String ?? "?"
        let build = info?["CFBundleVersion"] as? String ?? "?"

        let inputs = TherapistReportBuilder.Inputs(
            allRecords: allRecords,
            journalBodies: journalBodies,
            memoryCount: allRecords.count,
            diskBytes: bytes,
            weekEnding: Date(),
            egressArmedAt: EgressGuard.installedAt,
            appVersion: version,
            appBuild: build
        )

        let result = await TherapistReportBuilder.build(inputs: inputs, gemma: gemma)
        markdown = result
        phase = .ready
    }

    /// Writes the (possibly user-edited) markdown to `tmp/` and hands
    /// the URL to `MemoryExporter.share()`. EgressGuard stays armed;
    /// the iOS share sheet is the only path out and the user picks it.
    @MainActor
    private func share() {
        do {
            let url = try TherapistReportBuilder.writeToTempFile(markdown, weekEnding: Date())
            MemoryExporter.share(url)
        } catch {
            generationError = "Couldn't write the report to the temporary folder. \(error.localizedDescription)"
            phase = .failed
            EidosLogger.shared.error(
                .memory,
                event: "session-report.write-failed",
                error: error, failure: .memoryWrite
            )
        }
    }
}
