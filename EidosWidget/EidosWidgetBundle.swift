import WidgetKit
import SwiftUI

/// Widget bundle for Eidos.
///
/// Tonight (medical-helper pivot) this bundle only registers the iOS 18+
/// Control Widgets. Tomorrow we add:
///   - `MedCountdownWidget` (Home Screen + Lock Screen): next-dose countdown
///   - `MedDoseLiveActivity`: imminent-dose Lock Screen activity
///   - Tap-to-log Control Widget for one-touch dose logging
@main
struct EidosWidgetBundle: WidgetBundle {
    var body: some Widget {
        EidosTodayWidget()
        if #available(iOS 18.0, *) {
            EidosTalkControl()
        }
    }
}
