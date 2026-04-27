import Foundation
import AppIntents

/// Top-10 Siri phrases we want discoverable via "Hey Siri, ..." and
/// Spotlight. AppShortcuts has hard limits:
///   • Maximum 10 shortcuts per app
///   • Phrases can ONLY interpolate AppEntity / AppEnum parameters —
///     not String / Date — so we use parameterless phrases and let
///     Siri prompt for input when needed.
///
/// The full catalogue of 23 intents lives in `EidosIntents.swift` —
/// they're all usable as Shortcut actions inside the Shortcuts app.
struct EidosAppShortcuts: AppShortcutsProvider {

    static var appShortcuts: [AppShortcut] {
        AppShortcut(
            intent: OpenEidosChatIntent(),
            phrases: [
                "Talk to \(.applicationName)",
                "Open \(.applicationName)",
            ],
            shortTitle: "Talk to Eidos",
            systemImageName: "bubble.left.and.bubble.right.fill"
        )

        AppShortcut(
            intent: GenerateDigestIntent(),
            phrases: [
                "What's my \(.applicationName) briefing",
                "Read my briefing in \(.applicationName)",
            ],
            shortTitle: "Today's briefing",
            systemImageName: "sparkles"
        )

        AppShortcut(
            intent: WhatDoIKnowAboutIntent(),
            phrases: [
                "What do I know in \(.applicationName)",
                "Search my memory with \(.applicationName)",
            ],
            shortTitle: "What I know about",
            systemImageName: "person.text.rectangle"
        )

        AppShortcut(
            intent: AddNoteIntent(),
            phrases: [
                "Save a note to \(.applicationName)",
                "Remember this in \(.applicationName)",
            ],
            shortTitle: "Save note",
            systemImageName: "square.and.pencil"
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
            intent: LogCommitmentIntent(),
            phrases: [
                "I made a promise in \(.applicationName)",
                "Log a commitment in \(.applicationName)",
            ],
            shortTitle: "Log commitment",
            systemImageName: "handshake.fill"
        )

        AppShortcut(
            intent: CreateReminderIntent(),
            phrases: [
                "Remind me via \(.applicationName)",
            ],
            shortTitle: "Create reminder",
            systemImageName: "bell.badge"
        )

        AppShortcut(
            intent: WhatsOnTodayIntent(),
            phrases: [
                "What's on today in \(.applicationName)",
            ],
            shortTitle: "Today's calendar",
            systemImageName: "calendar"
        )

        AppShortcut(
            intent: NextUpIntent(),
            phrases: [
                "What's next in \(.applicationName)",
            ],
            shortTitle: "What's next",
            systemImageName: "arrow.forward.circle"
        )

        AppShortcut(
            intent: SendWhatsAppIntent(),
            phrases: [
                "Send a WhatsApp via \(.applicationName)",
            ],
            shortTitle: "WhatsApp",
            systemImageName: "bubble.left.and.bubble.right"
        )
    }
}
