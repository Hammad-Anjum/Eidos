import WidgetKit
import SwiftUI
import AppIntents

/// Intents that live in the widget extension. `openURL` hops back into
/// the main app, which handles `eidos://chat` / `eidos://home` in its
/// `.onOpenURL` handler to route to the right tab.
@available(iOS 18.0, *)
struct WidgetOpenChatIntent: AppIntent {
    static let title: LocalizedStringResource = "Talk to Eidos"
    static let openAppWhenRun: Bool = true

    @MainActor
    func perform() async throws -> some IntentResult & OpensIntent {
        return .result(opensIntent: OpenURLIntent(URL(string: "eidos://chat")!))
    }
}

@available(iOS 18.0, *)
struct WidgetOpenBriefingIntent: AppIntent {
    static let title: LocalizedStringResource = "Eidos briefing"
    static let openAppWhenRun: Bool = true

    @MainActor
    func perform() async throws -> some IntentResult & OpensIntent {
        return .result(opensIntent: OpenURLIntent(URL(string: "eidos://home")!))
    }
}

// MARK: - Control widgets (iOS 18+)

@available(iOS 18.0, *)
struct EidosTalkControl: ControlWidget {
    var body: some ControlWidgetConfiguration {
        StaticControlConfiguration(kind: "com.hissamuddin.eidos.Widget.TalkControl") {
            ControlWidgetButton(action: WidgetOpenChatIntent()) {
                Label("Talk to Eidos", systemImage: "bubble.left.and.bubble.right.fill")
            }
        }
        .displayName("Talk to Eidos")
        .description("Open Eidos chat with one tap.")
    }
}

@available(iOS 18.0, *)
struct EidosBriefingControl: ControlWidget {
    var body: some ControlWidgetConfiguration {
        StaticControlConfiguration(kind: "com.hissamuddin.eidos.Widget.BriefingControl") {
            ControlWidgetButton(action: WidgetOpenBriefingIntent()) {
                Label("Eidos briefing", systemImage: "sparkles")
            }
        }
        .displayName("Today's briefing")
        .description("Open your Eidos morning briefing.")
    }
}
