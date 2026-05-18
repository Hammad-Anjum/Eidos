import Foundation

/// Hero skill for the AuADHD hackathon submission.
///
/// Gemma 4 looks at a photo of a cluttered scene (multimodal vision
/// input via `RAGPipeline.chat(image:)`), parses what's in frame, and
/// emits a tool call with three steps to start: a first action, plus
/// two follow-ups. This skill receives those parsed fields, persists a
/// short memory entry tagged `scene` + `look-mode`, and returns a
/// spoken-friendly 1-2 sentence response that the chat layer pipes to
/// `SpeechSynthesizer`.
///
/// Design notes:
/// - **No dose / no measurement** — this is the AuADHD pivot, not
///   medical. The output is encouragement-to-start, not instruction.
/// - **One commitment, then stop.** The spoken reply names only the
///   first action by name + a 5-minute time-box. The next two steps
///   are saved to memory but not narrated, so the user can pull them
///   when ready instead of being overwhelmed by a list.
/// - **No moralizing task value.** Never "important", "should", "must."
///   The CLAUDE.md AuADHD design rules block those words.
/// - Privacy: the photo never leaves the device; only the parsed
///   plan is persisted, as plain markdown.
struct BreakDownSceneSkill: Skill {

    let name = "break_down_scene"
    let description = "Break a photo of a cluttered scene into ONE 5-minute starting action and two follow-ups. Call when the user attaches a photo plus overwhelm language."

    let parametersSchema: String = """
    {
      "scene_description": "string — 2-3 sentence visual description of what you see",
      "first_action": "string — the SINGLE 5-minute action to start with",
      "next_two_steps": ["string — second step", "string — third step"]
    }
    """

    let memory: MemoryManager

    func invoke(parameters: [String: AnyCodable]) async -> SkillResult {
        guard let first = parameters["first_action"]?.stringValue?
                .trimmingCharacters(in: .whitespacesAndNewlines),
              !first.isEmpty
        else {
            return .failure("I couldn't pick a starting step. Try the photo again with better lighting.")
        }

        let description = (parameters["scene_description"]?.stringValue ?? "")
            .trimmingCharacters(in: .whitespacesAndNewlines)

        // `next_two_steps` is an array of strings; `AnyCodable.arrayValue`
        // returns `[AnyCodable]`, so unwrap each entry's stringValue.
        let next: [String] = (parameters["next_two_steps"]?.arrayValue ?? [])
            .compactMap { $0.stringValue?.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }

        // Persist the breakdown so the user can ask "what was the next
        // step" later. Tier = recentSession; decays naturally.
        let bodyLines: [String] = [
            description.isEmpty ? nil : "Scene: \(description)",
            "First: \(first)",
            next.isEmpty ? nil : "Next: \(next.joined(separator: " | "))",
        ].compactMap { $0 }
        let title = "Scene breakdown — \(String((description.isEmpty ? first : description).prefix(40)))"

        let entry = MemoryEntry(
            tier: .recentSession,
            title: title,
            body: bodyLines.joined(separator: "\n"),
            priority: .p3,
            tags: ["scene", "look-mode"]
        )
        do {
            _ = try await memory.save(entry)
        } catch {
            EidosLogger.shared.error(.skill,
                event: "break_down_scene.memory.save.failed",
                error: error, failure: .memoryWrite)
            // Soft-fail: still return the user-facing reply. Saving the
            // breakdown is nice-to-have, not load-bearing for the user.
        }

        // Spoken reply: name the first action, time-box it, and stop.
        // Never list the next two — the whole point of the skill is to
        // collapse "many things" into "one thing right now."
        return .success("Start with: \(first). Five minutes — that's the whole commitment.")
    }

    func availability() async -> SkillAvailability { .available }
}
