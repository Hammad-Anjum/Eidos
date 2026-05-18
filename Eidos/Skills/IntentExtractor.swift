import Foundation

/// Pure-Swift intent extractor for chat messages.
///
/// Scans the user's text for reminder/todo phrasing and, when it hits,
/// returns a `Suggestion` the chat view can offer as a one-tap save.
/// Pattern-based rather than Gemma-classified because:
///
///   1. **Latency** — Gemma adds 5–15s per turn; this needs to be
///      instant or the chip lands after the user has scrolled past.
///   2. **Hallucination** — for "should this be saved" the answer is
///      always either obvious or non-obvious. A model has nothing to
///      add over keyword matching.
///   3. **Auditable** — the user-facing chip extracts an exact phrase
///      from their own message. They can read the original and the
///      extracted title side by side.
///
/// The trigger phrases are deliberately narrow: only sentences the
/// user actively asked Eidos to remember are caught. Soft signals
/// ("I want to call my mom sometime") never fire because they would
/// surface a chip after every casual message and the audience would
/// (rightly) start treating chips as noise.
enum IntentExtractor {

    /// What was detected. Title is the extracted action phrase
    /// (suitable for use as a `MemoryEntry.title`); originalPhrase is
    /// the matched substring (so the UI can show the user *why* this
    /// was suggested).
    struct Suggestion: Equatable, Sendable {
        let title: String
        let originalPhrase: String
        let kind: Kind

        enum Kind: String, Sendable {
            case reminder    // "remind me to X" / "don't let me forget X"
            case todo        // "I should X" / "I need to X"
        }
    }

    /// Returns a suggestion if the user message contains an explicit
    /// reminder/todo trigger phrase; nil otherwise. Matching is
    /// case-insensitive and limited to the first hit so we never
    /// flood the chat with multiple chips off one message.
    static func extract(from userMessage: String) -> Suggestion? {
        let normalized = userMessage
            .replacingOccurrences(of: "\n", with: " ")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalized.isEmpty else { return nil }

        // Reminder triggers — explicit "Eidos, hold onto this for me"
        // phrasing. Longest patterns first so "don't let me forget" doesn't
        // get short-circuited by "remind me".
        let reminderTriggers = [
            "don't let me forget to ",
            "don't let me forget ",
            "do not let me forget to ",
            "remind me later to ",
            "remind me to ",
            "remind me about ",
        ]
        for trigger in reminderTriggers {
            if let range = normalized.range(of: trigger, options: .caseInsensitive) {
                let action = trimmedAction(after: range.upperBound, in: normalized)
                if !action.isEmpty {
                    return Suggestion(
                        title: capitalizeFirst(action),
                        originalPhrase: trigger + action,
                        kind: .reminder
                    )
                }
            }
        }

        // To-do triggers — slightly weaker signal but still explicit.
        let todoTriggers = [
            "i need to remember to ",
            "i should remember to ",
            "i have to remember to ",
            "i need to ",
            "i should ",
            "i have to ",
            "i gotta ",
        ]
        for trigger in todoTriggers {
            if let range = normalized.range(of: trigger, options: .caseInsensitive) {
                let action = trimmedAction(after: range.upperBound, in: normalized)
                if !action.isEmpty {
                    return Suggestion(
                        title: capitalizeFirst(action),
                        originalPhrase: trigger + action,
                        kind: .todo
                    )
                }
            }
        }

        return nil
    }

    // MARK: - Helpers

    /// Extracts the action phrase that follows a trigger. Stops at the
    /// first sentence-terminating punctuation so multi-sentence
    /// messages don't grab unrelated text into the suggested title.
    /// Caps length at 60 chars — anything longer reads as a paragraph,
    /// not a task title, in the priority list.
    private static func trimmedAction(after index: String.Index, in string: String) -> String {
        let rest = string[index...]
        let terminators: Set<Character> = [".", "!", "?", ";"]
        var end = rest.endIndex
        for (offset, char) in rest.enumerated() where terminators.contains(char) {
            end = rest.index(rest.startIndex, offsetBy: offset)
            break
        }
        let action = rest[..<end].trimmingCharacters(in: .whitespacesAndNewlines)
        return String(action.prefix(60))
    }

    private static func capitalizeFirst(_ string: String) -> String {
        guard let first = string.first else { return string }
        return first.uppercased() + string.dropFirst()
    }
}
