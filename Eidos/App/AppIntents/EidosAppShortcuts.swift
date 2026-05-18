import Foundation
import AppIntents

/// Top Siri phrases discoverable via "Hey Siri, ..." and Spotlight.
/// AppShortcuts limits: max 10 shortcuts, parameters can only interpolate
/// AppEntity / AppEnum (not String / Date), so parameterless phrases.
///
/// Trimmed for the medical-helper pivot (2026-04-29). Tomorrow this list
/// grows back when `OpenMedModeIntent`, `LogDoseTakenIntent`, and
/// `NextDoseIntent` ship.
struct EidosAppShortcuts: AppShortcutsProvider {

    static var appShortcuts: [AppShortcut] {
        // Primary "Open Eidos" shortcut — Home destination. This is the
        // one that wins the iPhone 15 Pro+ Action Button slot when a
        // user binds Eidos. Listed first because `AppShortcutsProvider`
        // surfaces these in order: first one appears in
        // Settings → Action Button → Shortcut → Eidos as the default
        // pick.
        AppShortcut(
            intent: OpenEidosHomeIntent(),
            phrases: [
                "Open \(.applicationName)",
                "Launch \(.applicationName)",
            ],
            shortTitle: "Open Eidos",
            systemImageName: "house.fill"
        )

        AppShortcut(
            intent: OpenEidosChatIntent(),
            phrases: [
                "Talk to \(.applicationName)",
            ],
            shortTitle: "Talk to Eidos",
            systemImageName: "bubble.left.and.bubble.right.fill"
        )

        AppShortcut(
            intent: OpenEidosMemoryIntent(),
            phrases: [
                "Open my \(.applicationName) memory",
            ],
            shortTitle: "Browse memory",
            systemImageName: "brain"
        )

        AppShortcut(
            intent: MarkImportantIntent(),
            phrases: [
                "Remember forever in \(.applicationName)",
            ],
            shortTitle: "Core memory",
            systemImageName: "star.fill"
        )

        AppShortcut(
            intent: RecentMemoriesIntent(),
            phrases: [
                "Recent in \(.applicationName)",
            ],
            shortTitle: "Recent memories",
            systemImageName: "clock"
        )
    }
}
