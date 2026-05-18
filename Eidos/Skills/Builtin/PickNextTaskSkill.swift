import Foundation

/// Decision-paralysis assistant for the AuADHD audience.
///
/// When the user says "what now" / "brain stopped" / "I have N things",
/// Gemma calls this skill with the user's current `energy_level` (0-4).
/// The skill reads two on-device data sources:
///   - **Active priorities** from `MemoryManager.index.records(tier: .activePriorities)`
///   - **Next calendar event** from `CalendarSource.fetchEvents(daysAhead: 1)`
///
/// And returns ONE pick + a 5-minute commitment script. Never a list.
/// Never alternatives. The whole point of the skill is to collapse
/// "many things" into "one thing right now."
///
/// Pick heuristic by energy:
///   - 0-1 (burnout / low): pick the entry with the simplest title
///         (proxy: shortest title length). Two-minute commitment.
///   - 2 (okay): pick the lowest-priority-number (P1 > P2 > P3) — the
///         most-load-bearing priority. Five-minute commitment.
///   - 3-4 (good / high): same as 2 but ten-minute commitment.
///
/// If a calendar event is < 90 minutes out, mention it as context
/// (not as the picked task) so the user has a built-in stop signal.
struct PickNextTaskSkill: Skill {

    let name = "pick_next_task"
    let description = "Pick ONE task from the user's active priorities + calendar, sized to their current energy. Call when the user signals decision fatigue."

    let parametersSchema: String = """
    {
      "energy_level": "integer 0-4 — 0=burnout, 2=okay, 4=high. Ask the user if unknown."
    }
    """

    let memory: MemoryManager
    let calendar: CalendarSource

    func invoke(parameters: [String: AnyCodable]) async -> SkillResult {
        // Defense-in-depth on the energy signal. The chat path delivers
        // energy as plain text in the user prompt ("…energy is 2 out
        // of 4…") and relies on Gemma to extract it into the tool call.
        // When that extraction misses (or rounds, or hallucinates), we
        // fall back to the persisted Home-slider value so the user's
        // explicit slider input still drives the pick.
        //
        // `.object(forKey:) as? Int` (rather than `.integer(forKey:)`)
        // lets us distinguish "unset" from a real `0` (= burnout).
        let toolParamEnergy = parameters["energy_level"]?.intValue
        let storedEnergy = UserDefaults.standard.object(forKey: "eidos.auadhd.energyLevel") as? Int
        let energy = max(0, min(4, toolParamEnergy ?? storedEnergy ?? 2))

        // Pull active priorities. `MemoryIndex.records(tier:)` is fast
        // (in-memory metadata only).
        let priorities = await memory.index.records(tier: .activePriorities)

        guard !priorities.isEmpty else {
            return .success(
                "Nothing on your priority list yet. Start with whatever's been " +
                "tugging at you the most. Two minutes — just to break the seal."
            )
        }

        // Heuristic selection per energy.
        let pick: MemoryIndexRecord = {
            switch energy {
            case 0...1:
                // Burnout: pick the simplest-looking task (shortest title).
                return priorities.min(by: { $0.title.count < $1.title.count })
                    ?? priorities[0]
            default:
                // Okay-or-better: pick the highest-priority entry.
                // MemoryPriority is rawValue-based (P1 = 1 ... P5 = 5);
                // lower raw value = higher priority.
                return priorities.min(by: { $0.priority.rawValue < $1.priority.rawValue })
                    ?? priorities[0]
            }
        }()

        let timeHint: String
        switch energy {
        case 0...1: timeHint = "Just two minutes. Just enough to start."
        case 2:     timeHint = "Five minutes. That's the whole commitment."
        default:    timeHint = "Ten minutes. Then check back in."
        }

        var reply = "Start with: \(pick.title). \(timeHint)"

        // Optional context: next event in < 90 min as a stop signal.
        let upcoming = await calendar.fetchEvents(daysAhead: 1)
        if let nextEvent = upcoming.first(where: { $0.startDate > Date() }) {
            let mins = max(0, Int(nextEvent.startDate.timeIntervalSinceNow / 60))
            if mins > 0 && mins < 90 {
                reply += " (You have \(mins) minutes before \(nextEvent.title).)"
            }
        }

        // Touch the entry so the decay engine reflects that this
        // priority got attention. Errors are logged (not surfaced) —
        // a stale timestamp shouldn't block the pick from reaching
        // the user, but a silent failure pattern would hide a real
        // disk problem.
        Task.detached { [memory, id = pick.id] in
            do {
                try await memory.touch(id: id)
            } catch {
                EidosLogger.shared.log(.warn, category: .memory,
                    event: "pick_next_task.touch.failed",
                    message: error.localizedDescription,
                    payload: ["entry_id": id.uuidString]
                )
            }
        }

        return .success(reply)
    }

    /// Reads-only access to the in-memory index + calendar. The calendar
    /// permission flow lives in onboarding / Settings — if the user
    /// hasn't granted it, the skill still returns a useful pick from
    /// memory alone, so we report `.available` here unconditionally.
    func availability() async -> SkillAvailability { .available }
}
