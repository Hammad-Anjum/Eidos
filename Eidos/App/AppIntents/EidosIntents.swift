import Foundation
import AppIntents

// App Intents are the Siri / Shortcuts / Action Button surface for
// Eidos. Trimmed to the medical-helper substrate (2026-04-29). The
// previous Eidos build shipped 24 intents; for the hackathon submission
// only utility intents survive. Tomorrow we add:
//   - OpenMedModeIntent          — quick-launch label capture
//   - LogDoseTakenIntent         — Control Widget single-tap log
//   - WhatDidITakeTodayIntent    — voice query, returns adherence summary
//   - NextDoseIntent             — voice "what's my next dose"

// MARK: - Navigation

/// Opens the app to the Home tab. This is the right default for the
/// iPhone 15 Pro+ Action Button binding — pressing the side button
/// should land the user on the highest-leverage surface (Sit With Me
/// hero + crisis chip + tile grid), not in chat. Users who want chat
/// can bind `OpenEidosChatIntent` instead via Settings → Action
/// Button → Shortcut → Eidos → Talk to Eidos.
struct OpenEidosHomeIntent: AppIntent {
    static let title: LocalizedStringResource = "Open Eidos"
    static let description = IntentDescription("Open Eidos to the Home tab — Sit With Me, energy, and the four quick-action tiles.", categoryName: "Navigation")
    static let openAppWhenRun = true

    @MainActor
    func perform() async throws -> some IntentResult {
        NotificationCenter.default.post(name: .eidosJumpToTab, object: AppTab.home)
        return .result()
    }
}

struct OpenEidosChatIntent: AppIntent {
    static let title: LocalizedStringResource = "Talk to Eidos"
    static let description = IntentDescription("Open Eidos and start a conversation.", categoryName: "Chat")
    static let openAppWhenRun = true

    @MainActor
    func perform() async throws -> some IntentResult {
        NotificationCenter.default.post(name: .eidosJumpToTab, object: AppTab.chat)
        return .result()
    }
}

struct OpenEidosMemoryIntent: AppIntent {
    static let title: LocalizedStringResource = "Browse my memory"
    static let description = IntentDescription("Open the Eidos memory browser — the audit log of every dose and fact Eidos remembers.", categoryName: "Memory")
    static let openAppWhenRun = true

    @MainActor
    func perform() async throws -> some IntentResult {
        NotificationCenter.default.post(name: .eidosJumpToTab, object: AppTab.memory)
        return .result()
    }
}

// MARK: - Memory utilities

struct MarkImportantIntent: AppIntent {
    static let title: LocalizedStringResource = "Remember this forever"
    static let description = IntentDescription("Save something as a P1 core memory that never auto-expires.", categoryName: "Memory")
    static let openAppWhenRun = false

    @Parameter(title: "Fact")
    var fact: String

    @MainActor
    func perform() async throws -> some IntentResult & ProvidesDialog {
        let manager = MemoryManager()
        let entry = MemoryEntry(
            tier: .coreIdentity,
            title: String(fact.prefix(40)),
            body: fact,
            priority: .p1,
            tags: ["core", "siri-capture"]
        )
        _ = try? await manager.save(entry)
        return .result(dialog: IntentDialog("Saved to core memory."))
    }
}

struct RecentMemoriesIntent: AppIntent {
    static let title: LocalizedStringResource = "Recent memories"
    static let description = IntentDescription("Show your five most recently touched memory entries.", categoryName: "Memory")
    static let openAppWhenRun = false

    @MainActor
    func perform() async throws -> some IntentResult & ProvidesDialog & ReturnsValue<String> {
        let manager = MemoryManager()
        try? await manager.rebuildIndex()
        let top = await manager.index.topK(5)
        let summary = top.map(\.title).joined(separator: " · ")
        let message = summary.isEmpty ? "No recent memories." : summary
        return .result(value: summary, dialog: IntentDialog(stringLiteral: message))
    }
}

struct SearchMemoryIntent: AppIntent {
    static let title: LocalizedStringResource = "Search memory"
    static let description = IntentDescription("Find memory entries mentioning a keyword.", categoryName: "Memory")
    static let openAppWhenRun = false

    @Parameter(title: "Keyword")
    var keyword: String

    @MainActor
    func perform() async throws -> some IntentResult & ProvidesDialog & ReturnsValue<String> {
        let manager = MemoryManager()
        try? await manager.rebuildIndex()
        let lowered = keyword.lowercased()
        let all = await manager.index.all
        let hits = all.filter {
            $0.title.lowercased().contains(lowered)
                || $0.tags.contains(where: { $0.lowercased().contains(lowered) })
        }
        if hits.isEmpty {
            return .result(value: "", dialog: IntentDialog("Nothing about \(keyword) in my memory."))
        }
        let summary = hits.prefix(5).map(\.title).joined(separator: " · ")
        return .result(value: summary, dialog: IntentDialog("\(hits.count) matches: \(summary)"))
    }
}
