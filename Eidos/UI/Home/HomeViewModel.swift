import Foundation

/// Tiny view-model for the AuADHD Home surface.
///
/// All meaningful state on Home lives directly in the view — the
/// energy slider via `@AppStorage`, sheet flags via `@State`. This
/// view-model exists only to compute the time-of-day greeting once
/// at construction so the body doesn't recompute it on every
/// re-render.
@MainActor
@Observable
final class HomeViewModel {
    let greeting: String

    init() {
        self.greeting = HomeViewModel.greetingForNow()
    }

    static func greetingForNow() -> String {
        let h = Calendar.current.component(.hour, from: Date())
        switch h {
        case 5..<12:  return "Good morning"
        case 12..<17: return "Good afternoon"
        case 17..<22: return "Good evening"
        default:      return "Hello"
        }
    }
}
