import SwiftUI

/// Onboarding step 3 — captures the user's preferred name + the
/// primary reason they reached for Eidos. Both fields are optional;
/// the "Skip for now" button preserves the AuADHD design rule of
/// never demanding executive function.
///
/// What this seeds:
/// - Name → `UserDefaults` under `eidos.user.displayName`. The chat
///   path (`RAGPipeline.chat`) reads this and threads it into
///   `PromptTemplates.runtimeContextBlock(userDisplayName:)` so
///   Gemma addresses the user by name from the first turn.
/// - Purpose category → a P1 `MemoryEntry` in the `.coreIdentity`
///   tier, tagged `me:identity` + `purpose:<category>`. P1 never
///   auto-evicts, and the chat layer's `## What I remember` block
///   surfaces it on every turn. Optional custom text becomes the
///   memory body — also embedded into `MemoryRecallService` so
///   future semantic recall can find it.
///
/// Why a 5-category list + "in my own words" escape (not pure free
/// text): pure free-text demands the executive function the user
/// lacks at install time. Pure list pigeonholes. The hybrid lets
/// 90% of users tap once and the 10% with a specific story still
/// have a path. See the negotiation in
/// `plans/alright-lets-pivot-this-rippling-snowflake.md` for the
/// full rationale.
struct IdentityStep: View {
    @Environment(AppContainer.self) private var container

    /// `step` from `OnboardingView`; we mutate it on Continue / Skip
    /// to advance to the download step.
    @Binding var step: Int

    @State private var name: String = ""
    @State private var selectedPurpose: PurposeChoice?
    @State private var customText: String = ""
    @State private var isSaving = false
    @FocusState private var nameFocused: Bool
    @FocusState private var customFocused: Bool

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                header
                nameSection
                purposeSection
                Spacer(minLength: 24)
                actions
            }
            .padding(.horizontal, 24)
            .padding(.vertical, 28)
        }
        .scrollDismissesKeyboard(.interactively)
    }

    // MARK: - Sections

    private var header: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("So Eidos can show up for you")
                .font(.title2.bold())
            Text("Both fields are optional. You can change them in Settings later.")
                .font(.callout)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var nameSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("What should I call you?")
                .font(.headline)
            TextField("e.g. Sam", text: $name)
                .textInputAutocapitalization(.words)
                .autocorrectionDisabled(true)
                .submitLabel(.next)
                .focused($nameFocused)
                .onSubmit { nameFocused = false }
                .padding(12)
                .background(Color.secondary.opacity(0.10), in: RoundedRectangle(cornerRadius: 10))
                .accessibilityLabel("Your preferred name. Optional.")
        }
    }

    private var purposeSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("What brought you here?")
                .font(.headline)
            Text("Pick the one that fits today — it doesn't lock you in.")
                .font(.caption)
                .foregroundStyle(.secondary)

            VStack(spacing: 8) {
                ForEach(PurposeChoice.preset) { choice in
                    purposeRow(choice)
                }
                purposeRow(.custom)
            }

            if selectedPurpose == .custom {
                TextField(
                    "In my own words…",
                    text: $customText,
                    axis: .vertical
                )
                .lineLimit(3...6)
                .focused($customFocused)
                .padding(12)
                .background(Color.secondary.opacity(0.10), in: RoundedRectangle(cornerRadius: 10))
                .accessibilityLabel("Describe your reason in your own words.")
                .padding(.top, 4)
            }
        }
    }

    private var actions: some View {
        VStack(spacing: 8) {
            Button {
                Task { await save(skipping: false) }
            } label: {
                Text(isSaving ? "Saving…" : "Continue")
                    .frame(maxWidth: .infinity, minHeight: 44)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
            .disabled(isSaving)
            .accessibilityHint("Saves your name and reason, then continues to the model download.")

            Button("Skip for now") {
                Task { await save(skipping: true) }
            }
            .buttonStyle(.bordered)
            .controlSize(.small)
            .disabled(isSaving)
            .accessibilityHint("Skips this step. You can fill it in from Settings later.")
        }
        .padding(.top, 4)
    }

    private func purposeRow(_ choice: PurposeChoice) -> some View {
        let isSelected = selectedPurpose == choice
        return Button {
            selectedPurpose = choice
            if choice == .custom {
                // Defer focus so the field has time to render.
                Task { @MainActor in
                    try? await Task.sleep(nanoseconds: 100_000_000)
                    customFocused = true
                }
            } else {
                customFocused = false
            }
        } label: {
            HStack(alignment: .top, spacing: 12) {
                Image(systemName: choice.icon)
                    .font(.title3.weight(.semibold))
                    .foregroundStyle(.white)
                    .frame(width: 40, height: 40)
                    .background(choice.tint, in: RoundedRectangle(cornerRadius: 10))
                VStack(alignment: .leading, spacing: 2) {
                    Text(choice.label)
                        .font(.body.weight(.semibold))
                        .foregroundStyle(.primary)
                    Text(choice.hint)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.leading)
                }
                Spacer()
                if isSelected {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundStyle(.tint)
                }
            }
            .padding(12)
            .frame(maxWidth: .infinity, minHeight: 64)
            .background(
                RoundedRectangle(cornerRadius: 12)
                    .fill(isSelected
                          ? choice.tint.opacity(0.18)
                          : Color.secondary.opacity(0.08))
            )
        }
        .buttonStyle(.plain)
        .accessibilityLabel(choice.label)
        .accessibilityHint(choice.hint)
        .accessibilityAddTraits(isSelected ? [.isButton, .isSelected] : .isButton)
    }

    // MARK: - Persistence

    private func save(skipping: Bool) async {
        guard !isSaving else { return }
        isSaving = true

        if !skipping {
            // 1. Name → UserDefaults. Read by RAGPipeline on every
            //    chat turn so Gemma can address the user by name.
            let trimmedName = name.trimmingCharacters(in: .whitespacesAndNewlines)
            if !trimmedName.isEmpty {
                UserDefaults.standard.set(trimmedName, forKey: Self.nameKey)
            }

            // 2. Purpose → P1 memory entry in coreIdentity. Surfaces
            //    via `## What I remember` on every chat turn. Tagged
            //    `me:identity` (for the future memory-browser filter)
            //    and `purpose:<category>` (for any v2 skill that
            //    wants to branch on it).
            if let choice = selectedPurpose {
                await persistPurposeMemory(choice: choice,
                                           name: trimmedName.isEmpty ? nil : trimmedName)
                // 3. Mirror the tag onto UserDefaults so skills can
                //    read it without round-tripping through the
                //    memory store. Forward-compat for v2.
                UserDefaults.standard.set(choice.tagSuffix, forKey: Self.purposeKey)
            }
        }

        isSaving = false
        step += 1
    }

    private func persistPurposeMemory(choice: PurposeChoice, name: String?) async {
        let body: String = {
            switch choice {
            case .custom:
                let custom = customText.trimmingCharacters(in: .whitespacesAndNewlines)
                if custom.isEmpty {
                    return "User described their reason in their own words but left the field empty."
                }
                return custom
            default:
                return choice.hint
            }
        }()

        let title: String = {
            if let name {
                return "Why \(name) is here: \(choice.label)"
            }
            return "Why I'm here: \(choice.label)"
        }()

        let entry = MemoryEntry(
            tier: .coreIdentity,
            title: title,
            body: body,
            priority: .p1,
            tags: ["me:identity", "purpose:\(choice.tagSuffix)"],
            pinned: true
        )

        do {
            _ = try await container.memoryManager.save(entry)
            // Also push into the embedding recall index immediately
            // so the FIRST chat turn after onboarding can semantically
            // find this entry. Without this push the entry sits in
            // markdown until the next `rebuildIndex()` cycle, which
            // happens at app launch — meaning a user who chats right
            // after onboarding wouldn't get personalized recall on
            // turn 1.
            await container.memoryRecall.indexEntry(entry)
        } catch {
            EidosLogger.shared.error(.memory,
                event: "onboarding.identity.save.failed",
                error: error, failure: .memoryWrite)
        }
    }

    // MARK: - Persistence keys

    static let nameKey = "eidos.user.displayName"
    static let purposeKey = "eidos.user.purposeTag"
}

// MARK: - Purpose choice

/// The 5 curated purpose categories plus `.custom`.
///
/// Storage tag suffix (e.g. `daily_function`) is used both as the
/// `purpose:<...>` memory tag and the UserDefaults raw string. Stable
/// across builds — do NOT rename without a migration.
enum PurposeChoice: String, CaseIterable, Identifiable {
    case dailyFunction = "daily_function"
    case burnout = "burnout"
    case emotionalRegulation = "emotional_regulation"
    case selfDiscovery = "self_discovery"
    case memoryCapture = "memory_capture"
    case custom = "custom"

    /// The 5 preset cases shown in the grid. `.custom` is rendered
    /// separately below them so the visual hierarchy reads as
    /// "preset choices, then escape hatch."
    static let preset: [PurposeChoice] = [
        .dailyFunction, .burnout, .emotionalRegulation,
        .selfDiscovery, .memoryCapture
    ]

    var id: String { rawValue }
    var tagSuffix: String { rawValue }

    var label: String {
        switch self {
        case .dailyFunction: "Daily executive function"
        case .burnout: "Recovering from burnout"
        case .emotionalRegulation: "Grounding & RSD"
        case .selfDiscovery: "Figuring myself out"
        case .memoryCapture: "Remembering things"
        case .custom: "In my own words…"
        }
    }

    var hint: String {
        switch self {
        case .dailyFunction:
            "Starting things, finishing things, deciding what to do next."
        case .burnout:
            "I'm in a hard stretch and need a quiet companion, not a coach."
        case .emotionalRegulation:
            "Help me when criticism stings or everything is loud."
        case .selfDiscovery:
            "I'm new to AuDHD / ADHD / autism and want to understand the wiring."
        case .memoryCapture:
            "Voice journals, conversations, things I keep losing."
        case .custom:
            "Describe what you need in your own words. Saved as a private memory."
        }
    }

    var icon: String {
        switch self {
        case .dailyFunction: "checklist"
        case .burnout: "moon.zzz.fill"
        case .emotionalRegulation: "waveform.path.ecg"
        case .selfDiscovery: "person.crop.circle.dashed"
        case .memoryCapture: "brain.head.profile"
        case .custom: "pencil.line"
        }
    }

    var tint: Color {
        switch self {
        case .dailyFunction: .orange
        case .burnout: .indigo
        case .emotionalRegulation: .pink
        case .selfDiscovery: .teal
        case .memoryCapture: .purple
        case .custom: .gray
        }
    }
}
