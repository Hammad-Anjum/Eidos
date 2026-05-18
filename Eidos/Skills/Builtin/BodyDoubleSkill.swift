import Foundation

/// Body-doubling skill — the AuADHD-audience differentiator.
///
/// "Body doubling" is the consistently most-requested unmet need across
/// r/ADHD, r/autism, and r/AuDHD: the simple fact of another presence in
/// the room makes initiating an executive-function task easier. Existing
/// paid options (Focusmate, Caveday, Flow Club) charge $20+/mo for a
/// cloud-mediated Zoom partner. Eidos offers the same affordance fully
/// on-device, voice-first, no human required, no network egress.
///
/// This skill is the data-layer end of the feature. The session
/// experience itself lives in `BodyDoublingView`:
///   1. The view dispatches this skill once when the user taps Start.
///   2. The skill writes a `MemoryEntry` (`.recentSession`, P3, tagged
///      `body-double` + `body-double-YYYY-MM-DD`) so the user can later
///      ask "what did I sit with this week" via semantic recall.
///   3. The skill returns the canonical opening line —
///      *"I'm here. Start whenever."* — which the view speaks aloud.
///   4. The view then owns the timer, the halfway check-in, and the
///      closing line. No further Gemma round-trips during the session.
///
/// Why no Gemma personalization in v1: latency + thermal cost of an
/// inference during a presence flow undermines the whole point of the
/// flow — calm. Halfway and closing lines are deterministic; the Gemma
/// hook can be added later behind a feature flag once we have HRV
/// signal to gate it on.
struct BodyDoubleSkill: Skill {

    let name = "start_body_double"
    let description = "Begin a silent body-double session — set a timer, sit with the user, check in once at the halfway mark, and acknowledge the close. Call when the user says they want to 'sit with' a task, asks for body doubling, or wants company while they work."

    let parametersSchema: String = """
    {
      "task": "string — short description of what the user said they're working on; may be empty",
      "duration_minutes": "integer — 5, 10, 15, or 25 typically; clamped to 2-60"
    }
    """

    let memory: MemoryManager

    func invoke(parameters: [String: AnyCodable]) async -> SkillResult {
        let task = (parameters["task"]?.stringValue ?? "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let rawDuration = parameters["duration_minutes"]?.intValue ?? 10
        let duration = max(2, min(60, rawDuration))

        let displayTask = task.isEmpty ? "open session" : task
        let title = "Sat with — \(String(displayTask.prefix(40)))"
        let body: String = {
            if task.isEmpty {
                return "Open body-double session.\nDuration: \(duration) minutes."
            }
            return "With: \(task)\nDuration: \(duration) minutes."
        }()

        let entry = MemoryEntry(
            tier: .recentSession,
            title: title,
            body: body,
            priority: .p3,
            tags: ["body-double", "body-double-\(Self.dayTag())"]
        )
        do {
            _ = try await memory.save(entry)
        } catch {
            EidosLogger.shared.error(
                .skill,
                event: "body_double.memory.save.failed",
                error: error,
                failure: .memoryWrite
            )
            // Soft-fail: the user still gets the acknowledgment.
            // Losing the audit row of a body-double session is a v2
            // problem, not a session-blocker.
        }

        // Opening line adapts to the inferred emotional register of
        // the user's task description. Direction is always toward
        // calm/normal — never matching high energy upward (mirror-up
        // amplifies dysregulation for AuDHD adults; the audience-
        // safer prescription is mirror-down + ground). The four
        // archetypes are deterministic (no Gemma roundtrip, no
        // hallucination risk, no latency) and key off vocabulary the
        // user actually used. Fallback is the canonical line.
        let opener = Self.openingLine(for: task)
        return .success(opener)
    }

    func availability() async -> SkillAvailability { .available }

    /// Tone-aware opening line. Four archetypes plus a neutral
    /// fallback. The chooser is keyword-based — fast, reliable, and
    /// auditable. Word lists deliberately small to keep matches
    /// confident; ambiguous text falls through to the neutral line
    /// rather than risking the wrong register.
    static func openingLine(for task: String) -> String {
        let intent = task.lowercased()

        // Anxious / overwhelmed → calming, breath-led.
        let anxiousMarkers = [
            "panic", "anxious", "anxiety", "freaking out",
            "scared", "stressed", "overwhelmed", "racing",
        ]
        if anxiousMarkers.contains(where: { intent.contains($0) }) {
            return "Slow it down with me. We'll start when you've taken one full breath."
        }

        // Sad / heavy → hopeful but quiet, never minimizing the weight.
        let heavyMarkers = [
            "sad", "depressed", "heavy", "hopeless", "exhausted",
            "burnt out", "burned out", "drained", "empty",
        ]
        if heavyMarkers.contains(where: { intent.contains($0) }) {
            return "It's been heavy. I'm here. Start whenever feels possible."
        }

        // Energetic / ambitious → steady-supportive (mirror-down).
        // Honors the energy without amplifying it; the goal is a
        // sustainable session, not a sprint that ends in a crash.
        let energeticMarkers = [
            "excited", "let's go", "on a roll", "pumped",
            "ambitious", "ready", "fired up",
        ]
        if energeticMarkers.contains(where: { intent.contains($0) }) {
            return "Good energy. Let's keep it steady. Start whenever."
        }

        // Procrastinating / stuck — neutral nudge, no judgment.
        let stuckMarkers = [
            "procrastinating", "avoiding", "putting off",
            "can't start", "won't start", "stuck",
        ]
        if stuckMarkers.contains(where: { intent.contains($0) }) {
            return "Five minutes is enough to begin. I'm here. Start whenever."
        }

        // Neutral fallback — the canonical audience-research-validated
        // phrasing: presence, not coaching.
        return "I'm here. Start whenever."
    }

    /// `yyyy-MM-dd` in the user's current calendar. Used so memory tags
    /// stay tied to the natural concept of "today's sessions" even when
    /// queried weeks later.
    private static func dayTag() -> String {
        let f = DateFormatter()
        f.calendar = Calendar(identifier: .gregorian)
        f.locale = Locale(identifier: "en_US_POSIX")
        f.dateFormat = "yyyy-MM-dd"
        return f.string(from: Date())
    }
}
