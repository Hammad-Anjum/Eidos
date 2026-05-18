import Foundation

enum MemoryCrystallizerError: Error, LocalizedError {
    case emptyConversation
    case modelReturnedNoMemories
    case malformedResponse(String)

    var errorDescription: String? {
        switch self {
        case .emptyConversation: "Nothing to crystallize — conversation is empty."
        case .modelReturnedNoMemories: "Model produced no memories for this session."
        case .malformedResponse(let s): "Crystallizer response was malformed: \(s)"
        }
    }
}

/// End-of-session digestion. Feeds the conversation to Gemma with an
/// extraction prompt and stores the model's distilled notes as
/// `MemoryEntry` records.
///
/// Runs asynchronously when a chat ends — should be cheap enough (a few
/// hundred output tokens) to run on a short timeout.
actor MemoryCrystallizer {

    private let gemma: GemmaSession
    private let manager: MemoryManager
    /// Optional. When set, every newly persisted memory is indexed
    /// into the embedding-based recall service so the next chat
    /// turn can find it semantically (not just by keyword). Wired
    /// post-init by `AppContainer` since `MemoryRecallService`
    /// depends on services that also depend on Gemma -> avoids a
    /// retain cycle.
    private(set) var recallService: MemoryRecallService?

    init(
        gemma: GemmaSession,
        manager: MemoryManager,
        recallService: MemoryRecallService? = nil
    ) {
        self.gemma = gemma
        self.manager = manager
        self.recallService = recallService
    }

    /// Late-binds the recall service. Used by `AppContainer` to break
    /// the dependency cycle.
    func attachRecallService(_ service: MemoryRecallService) {
        self.recallService = service
    }

    /// Extracts memorable facts from a conversation and persists them.
    /// Returns the list of newly-created entries.
    ///
    /// **Safety**: conversations that trip the SafetyGate on any user turn
    /// are NOT crystallized — we don't want crisis language persisted into
    /// long-term memory via Gemma-generated summaries. Any such run is
    /// logged and returns an empty array.
    @discardableResult
    func crystallize(
        conversation: [(role: String, content: String)],
        defaultTier: MemoryTier = .topic,
        defaultPriority: MemoryPriority = .p3
    ) async throws -> [MemoryEntry] {
        guard !conversation.isEmpty else { throw MemoryCrystallizerError.emptyConversation }

        // Skip crystallization entirely if any user turn trips the safety
        // gate. We don't want a crisis conversation distilled into a
        // permanent "memory" — it should fade, not persist.
        for turn in conversation where turn.role == "user" {
            if case .refuse(let reason, _) = SafetyGate.evaluate(turn.content) {
                EidosLogger.shared.log(
                    .warn, category: .safety,
                    event: "crystallizer.skip.safety",
                    message: "Skipping crystallization — user turn tripped SafetyGate",
                    payload: ["reason": reason.rawValue],
                    failure: .safetyGateTriggered
                )
                return []
            }
        }

        let messages = PromptTemplates.crystallization(conversation: conversation)
        let stream = try await gemma.generate(messages: messages)

        var raw = ""
        for try await chunk in stream { raw += chunk }

        let items = try parse(raw)
        guard !items.isEmpty else { throw MemoryCrystallizerError.modelReturnedNoMemories }

        // Reconciliation pass: compare candidates against existing memory
        // and decide ADD / UPDATE / DELETE / NONE. Deduplicates the
        // classic "same fact stored five times" bug.
        //
        // If reconciliation throws (Gemma error, malformed JSON, thermal
        // abort) we log it and fall through to insert-all rather than
        // swallowing the failure — duplicates are recoverable, but a
        // silent crystallizer regression is invisible without the log.
        let decisions: [ReconciliationDecision]
        do {
            decisions = try await reconcile(candidates: items)
        } catch {
            EidosLogger.shared.log(.error, category: .memory,
                event: "crystallizer.reconcile.failed",
                message: error.localizedDescription,
                payload: ["candidate_count": items.count]
            )
            decisions = []
        }

        // Apply decisions. Fall back to naive insert-all if the
        // reconciliation pass produced no usable decisions (model
        // returned malformed JSON, etc.) — we'd rather duplicate than
        // lose a fact.
        var saved: [MemoryEntry] = []
        if decisions.isEmpty {
            EidosLogger.shared.log(.warn, category: .memory,
                event: "crystallizer.reconcile.fallback",
                message: "Reconciliation produced no decisions; falling back to insert-all."
            )
            saved.reserveCapacity(items.count)
            for item in items {
                let entry = MemoryEntry(
                    tier: item.tier ?? defaultTier,
                    title: item.title,
                    body: item.body,
                    priority: item.priority ?? defaultPriority,
                    tags: item.tags
                )
                let stored = try await manager.save(entry)
                saved.append(stored)
            }
        } else {
            saved = try await applyDecisions(
                decisions: decisions,
                candidates: items,
                defaultTier: defaultTier,
                defaultPriority: defaultPriority
            )
        }

        EidosLogger.shared.metric(.memory, event: "crystallizer.run", values: [
            "candidates": items.count,
            "saved": saved.count,
            "decisions": decisions.count,
        ])

        // Embedding-based recall: index every newly-persisted memory
        // so the next chat turn can find it semantically (not just by
        // keyword). Wrapped in a Task so we don't block the chat
        // teardown path on embedding work — the recall service is
        // crash-safe per its own try/catch.
        if let recall = recallService, !saved.isEmpty {
            let entries = saved
            Task.detached {
                for entry in entries {
                    // Conflict surfacing: before indexing, check
                    // whether this new fact looks semantically close
                    // to an existing P1/P2 (core identity / active
                    // priority) memory. If it is, log a conflict
                    // candidate so a future UI can prompt the user
                    // to reconcile ("Earlier you said X. This new
                    // statement says Y. Which is right?"). Today we
                    // only LOG; the actual reconciliation prompt is
                    // a separate UX deliverable.
                    let similar = await recall.similarHighPriority(
                        to: entry.title + " " + entry.body,
                        threshold: 0.55,
                        maxResults: 3
                    )
                    if !similar.isEmpty {
                        EidosLogger.shared.log(
                            .info, category: .memory,
                            event: "crystallizer.conflict-candidate",
                            payload: [
                                "new_entry_id": entry.id.uuidString,
                                "new_title": entry.title,
                                "similar_count": similar.count,
                                "top_score": Double(similar[0].score),
                                "top_existing_title": similar[0].entry.title,
                            ]
                        )
                    }
                    await recall.indexEntry(entry)
                }
            }
        }
        return saved
    }

    // MARK: - Reconciliation (mem0-style ADD/UPDATE/DELETE/NONE)

    /// Decision emitted by the reconciler.
    struct ReconciliationDecision: Sendable {
        enum Action: String, Sendable {
            case add = "ADD"
            case update = "UPDATE"
            case delete = "DELETE"
            case none = "NONE"
        }
        let action: Action
        let candidateIndex: Int
        let existingID: UUID?
        let mergedTitle: String?
        let mergedBody: String?
        let tier: MemoryTier?
        let priority: MemoryPriority?
        let reason: String
    }

    /// Runs the reconciliation turn: for each candidate, finds existing
    /// memories with similar titles (naive title-substring match for
    /// now; a future version can use semantic similarity via
    /// EmbeddingService), asks Gemma to decide ADD/UPDATE/DELETE/NONE.
    private func reconcile(candidates: [CrystallizedItem]) async throws -> [ReconciliationDecision] {
        // Gather existing memories similar to any candidate. Title-
        // substring match is intentionally coarse — we want a
        // generous candidate pool and let Gemma do the fine matching.
        var existing: [MemoryEntry] = []
        var seenIDs = Set<UUID>()
        for candidate in candidates {
            let lower = candidate.title.lowercased()
            let words = lower.split(separator: " ").filter { $0.count >= 4 }
            for word in words {
                let records = await manager.index.search(titleSubstring: String(word))
                for record in records where seenIDs.insert(record.id).inserted {
                    if let entry = try? await manager.load(id: record.id) {
                        existing.append(entry)
                    }
                }
            }
        }

        // If there's nothing to reconcile against, everything is an ADD.
        guard !existing.isEmpty else {
            return candidates.enumerated().map { (idx, c) in
                ReconciliationDecision(
                    action: .add, candidateIndex: idx,
                    existingID: nil,
                    mergedTitle: c.title, mergedBody: c.body,
                    tier: c.tier, priority: c.priority,
                    reason: "no existing similar memory"
                )
            }
        }

        let candidatesJSON = encodeCandidates(candidates)
        let existingJSON = encodeExisting(existing)
        let messages = PromptTemplates.reconciliation(
            candidatesJSON: candidatesJSON,
            existingJSON: existingJSON
        )
        let stream = try await gemma.generate(messages: messages)
        var raw = ""
        for try await chunk in stream { raw += chunk }
        return parseReconciliation(raw)
    }

    private func applyDecisions(
        decisions: [ReconciliationDecision],
        candidates: [CrystallizedItem],
        defaultTier: MemoryTier,
        defaultPriority: MemoryPriority
    ) async throws -> [MemoryEntry] {
        var saved: [MemoryEntry] = []
        for d in decisions {
            switch d.action {
            case .add:
                guard d.candidateIndex >= 0, d.candidateIndex < candidates.count else { continue }
                let c = candidates[d.candidateIndex]
                let entry = MemoryEntry(
                    tier: d.tier ?? c.tier ?? defaultTier,
                    title: d.mergedTitle ?? c.title,
                    body: d.mergedBody ?? c.body,
                    priority: d.priority ?? c.priority ?? defaultPriority,
                    tags: c.tags
                )
                let stored = try await manager.save(entry)
                saved.append(stored)

            case .update:
                guard let id = d.existingID,
                      var existing = try await manager.load(id: id) else { continue }
                if let t = d.mergedTitle { existing.title = t }
                if let b = d.mergedBody { existing.body = b }
                if let tier = d.tier { existing.tier = tier }
                if let prio = d.priority { existing.priority = prio }
                let stored = try await manager.save(existing)
                saved.append(stored)

            case .delete:
                guard let id = d.existingID else { continue }
                try? await manager.delete(id: id)

            case .none:
                continue
            }
        }
        return saved
    }

    /// Encodes candidate facts as a JSON array for the reconciliation prompt.
    private func encodeCandidates(_ items: [CrystallizedItem]) -> String {
        let payload: [[String: Any]] = items.enumerated().map { (i, c) in
            var o: [String: Any] = [
                "index": i,
                "title": c.title,
                "body": c.body,
            ]
            if !c.tags.isEmpty { o["tags"] = c.tags }
            if let t = c.tier { o["tier"] = t.rawValue }
            if let p = c.priority { o["priority"] = p.rawValue }
            return o
        }
        let data = (try? JSONSerialization.data(withJSONObject: payload, options: [.prettyPrinted])) ?? Data()
        return String(data: data, encoding: .utf8) ?? "[]"
    }

    /// Encodes existing-memory matches as a JSON array for the prompt.
    private func encodeExisting(_ entries: [MemoryEntry]) -> String {
        let payload: [[String: Any]] = entries.map { e in
            [
                "id": e.id.uuidString,
                "title": e.title,
                "body": e.body,
                "tier": e.tier.rawValue,
                "priority": e.priority.rawValue,
            ]
        }
        let data = (try? JSONSerialization.data(withJSONObject: payload, options: [.prettyPrinted])) ?? Data()
        return String(data: data, encoding: .utf8) ?? "[]"
    }

    /// Parses Gemma's reconciliation JSON into typed decisions. Robust to
    /// prose wrappers (same trick as `extractJSONArray`).
    private func parseReconciliation(_ raw: String) -> [ReconciliationDecision] {
        guard let arrayString = extractJSONArray(raw),
              let data = arrayString.data(using: .utf8),
              let any = try? JSONSerialization.jsonObject(with: data) as? [[String: Any]] else {
            return []
        }
        return any.compactMap { dict in
            guard let actionStr = dict["action"] as? String,
                  let action = ReconciliationDecision.Action(rawValue: actionStr),
                  let idx = dict["candidate_index"] as? Int else { return nil }
            let existingID = (dict["existing_id"] as? String).flatMap(UUID.init(uuidString:))
            let tier = (dict["tier"] as? String).flatMap(MemoryTier.init(rawValue:))
            let priority = (dict["priority"] as? Int).flatMap(MemoryPriority.init(rawValue:))
            return ReconciliationDecision(
                action: action,
                candidateIndex: idx,
                existingID: existingID,
                mergedTitle: dict["merged_title"] as? String,
                mergedBody: dict["merged_body"] as? String,
                tier: tier,
                priority: priority,
                reason: (dict["reason"] as? String) ?? ""
            )
        }
    }

    // MARK: - Parsing

    /// One unit produced by the model. Tier/priority are optional — the
    /// caller provides defaults when the model doesn't specify.
    struct CrystallizedItem: Sendable {
        var title: String
        var body: String
        var tags: [String]
        var tier: MemoryTier?
        var priority: MemoryPriority?
    }

    /// Extracts the first balanced `[...]` JSON array from `raw` (the model
    /// often wraps its output in prose) and decodes it.
    func parse(_ raw: String) throws -> [CrystallizedItem] {
        guard let arrayString = extractJSONArray(raw) else {
            throw MemoryCrystallizerError.malformedResponse("no JSON array found")
        }
        guard let data = arrayString.data(using: .utf8) else {
            throw MemoryCrystallizerError.malformedResponse("non-UTF8")
        }
        guard let any = try JSONSerialization.jsonObject(with: data) as? [[String: Any]] else {
            throw MemoryCrystallizerError.malformedResponse("not an array of objects")
        }

        return any.compactMap { dict in
            guard let title = dict["title"] as? String, !title.isEmpty,
                  let body = dict["body"] as? String, !body.isEmpty else {
                return nil
            }
            let tags = dict["tags"] as? [String] ?? []
            let tier = (dict["tier"] as? String).flatMap(MemoryTier.init(rawValue:))
            let priority = (dict["priority"] as? Int).flatMap(MemoryPriority.init(rawValue:))
            return CrystallizedItem(
                title: title, body: body, tags: tags,
                tier: tier, priority: priority
            )
        }
    }

    /// Finds the first top-level `[` … `]` JSON array in `raw`.
    /// Scans with a bracket counter; respects string literals so `[` /
    /// `]` inside strings don't confuse it.
    private func extractJSONArray(_ raw: String) -> String? {
        var depth = 0
        var start: String.Index?
        var inString = false
        var escape = false
        for i in raw.indices {
            let c = raw[i]
            if escape { escape = false; continue }
            if inString {
                if c == "\\" { escape = true }
                else if c == "\"" { inString = false }
                continue
            }
            switch c {
            case "\"": inString = true
            case "[":
                if depth == 0 { start = i }
                depth += 1
            case "]":
                depth -= 1
                if depth == 0, let s = start {
                    return String(raw[s...i])
                }
            default: break
            }
        }
        return nil
    }
}
