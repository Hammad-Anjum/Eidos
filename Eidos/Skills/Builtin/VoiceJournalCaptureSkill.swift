import Foundation

/// Voice-journal capture for AuADHD users.
///
/// Flow: user taps the Journal tile on Home → mic opens →
/// `SpeechTranscriber` streams an on-device transcript → user taps
/// Stop → the transcript is handed to this skill → one memory entry
/// is persisted, tagged `journal:` plus a date tag for recall.
///
/// Design notes:
/// - This is **bypass-the-Gemma** by design. Calling the crystallizer
///   on every voice journal would be expensive (Gemma forward pass)
///   and lossy (the crystallizer compresses; we want the user's words
///   preserved). The crystallizer can run later, on demand, over the
///   raw journal entries.
/// - Tagging convention: `journal:` (the surface) + `journal-YYYY-MM-DD`
///   (the date) + any user-provided `topics` (e.g. `re:work`, `re:sarah`).
/// - Tier: `recentSession`. Priority P3. Decays naturally.
/// - **No Gemma fact extraction in v1.** v2 will run the existing
///   crystallizer over recent journal entries on a schedule.
struct VoiceJournalCaptureSkill: Skill {

    let name = "voice_journal_capture"
    let description = "Save a voice-journal monologue to on-device memory tagged for later recall. Call after the user finishes a journal recording."

    let parametersSchema: String = """
    {
      "transcript": "string — verbatim user monologue, as transcribed by SFSpeechRecognizer",
      "topics": ["string — optional topical tags like 're:work', 're:sarah', empty array if none"]
    }
    """

    let memory: MemoryManager

    func invoke(parameters: [String: AnyCodable]) async -> SkillResult {
        guard let transcript = parameters["transcript"]?.stringValue?
                .trimmingCharacters(in: .whitespacesAndNewlines),
              !transcript.isEmpty
        else {
            return .failure("Nothing to journal — I didn't catch anything.")
        }

        // Topic tags come from either explicit user-supplied entries
        // (an optional UI affordance on the Journal screen) or, more
        // typically, are empty for v1. Defensive: ignore non-string
        // array entries and the empty string.
        let topics: [String] = (parameters["topics"]?.arrayValue ?? [])
            .compactMap { $0.stringValue?.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
            .map { tag in
                // Normalize: lowercase + ensure `re:` prefix on bare names.
                let lower = tag.lowercased()
                if lower.contains(":") { return lower }
                return "re:\(lower)"
            }

        let dateTag = Self.dateFormatter.string(from: Date())
        var tags = ["journal", "journal-\(dateTag)"]
        tags.append(contentsOf: topics)

        // Title: a short, useful preview. First ~50 chars of the
        // transcript so the user can scan their memory browser.
        let title = "Journal — " + String(transcript.prefix(50))
            .replacingOccurrences(of: "\n", with: " ")

        let entry = MemoryEntry(
            tier: .recentSession,
            title: title,
            body: transcript,
            priority: .p3,
            tags: tags
        )

        do {
            _ = try await memory.save(entry)
        } catch {
            // Last-resort recovery: dump the verbatim transcript to a
            // tmp file so the user's words aren't lost on disk-full /
            // permission errors. The user came here BECAUSE the app
            // promised pocket presence — silently losing what they
            // just said breaks that contract harder than a save error
            // we surface and recover from.
            let recoveryURL = Self.writeRecoveryFile(transcript: transcript, tags: tags)
            EidosLogger.shared.error(.skill,
                event: "voice_journal_capture.memory.save.failed",
                error: error, failure: .memoryWrite,
                extra: ["recovery_path": recoveryURL?.path ?? "<recovery-write-failed>"])
            if recoveryURL != nil {
                return .failure("Couldn't save permanently — your words are safe in Recovery. Try again in a moment.")
            }
            return .failure("Couldn't save journal: \(error.localizedDescription)")
        }

        let topicSummary = topics.isEmpty
            ? ""
            : " (tagged: \(topics.joined(separator: ", ")))"
        return .success("Saved.\(topicSummary)")
    }

    func availability() async -> SkillAvailability { .available }

    // MARK: - Private

    private static let dateFormatter: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.dateFormat = "yyyy-MM-dd"
        return f
    }()

    private static let recoveryTimestampFormatter: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.dateFormat = "yyyy-MM-dd HH:mm:ss"
        return f
    }()

    /// Writes a verbatim transcript copy to a tmp recovery file when the
    /// primary memory save fails. Returns the URL on success, nil if
    /// the recovery write itself failed.
    ///
    /// Path: `FileManager.temporaryDirectory/journal-recovery/<uuid>.md`.
    /// The OS may clear the temp directory between launches; that's
    /// acceptable for a last-resort path. A v2 worker can promote
    /// these files to a persistent dead-letter queue on next launch.
    private static func writeRecoveryFile(transcript: String, tags: [String]) -> URL? {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("journal-recovery", isDirectory: true)
        do {
            try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        } catch {
            return nil
        }
        let url = dir.appendingPathComponent("journal-\(UUID().uuidString).md")
        let body = """
        # Journal recovery — \(recoveryTimestampFormatter.string(from: Date()))

        Tags: \(tags.joined(separator: ", "))

        ---

        \(transcript)
        """
        do {
            try body.write(to: url, atomically: true, encoding: .utf8)
            return url
        } catch {
            return nil
        }
    }
}
