## Session log — 2026-04-24 — project analysis / architecture gaps

### Goal

Assess Eidos as a product + architecture: what is already strong, what is weak, where the privacy / trust / reliability loopholes are, and which structural changes would improve odds of shipping a believable v1.

### Context checked first

- `masterplan.md` current-state table and Phase 8 / Phase 10 sections
- `KNOWN_LIMITATIONS.md`
- `architecture.md`
- latest prior conversation log from 2026-04-23
- key runtime files: `AppContainer`, `RAGPipeline`, `PromptTemplates`, `GemmaSession`, `EgressGuard`, `ContextBuilder`, `MemoryCrystallizer`, `ChatViewModel`, `AmbientSnapshot`, `ShareViewController`, skill implementations

### High-confidence strengths

- The moat is correctly chosen: memory + action + privacy receipts, not raw frontier-model IQ.
- The repo is more mature than the project story implies: widgets, App Intents, diagnostics, safety gate, long-context packing, tool loop, and share-extension wiring all exist.
- The code shows real device-first thinking: `DeviceProfile`, thermal caps, `MemoryProbe`, lazy embedding load, capped tool hops, simulator mocks.
- The observability work in Phase 8 is the right move before wider testing.
- The memory system has a good instinct: durable tiers, decay, reconciliation, exportability, and user-auditable storage.

### Structural risks / loopholes

1. Prompt-injection risk on the action path.
   - Retrieved notes are injected into the same prompt that receives the tool catalogue.
   - `RAGPipeline` dispatches tool calls directly once parsed.
   - `CreateReminderSkill` mutates state immediately without a user confirmation step.

2. EgressGuard is a strong claim with a narrower implementation.
   - Current guard is `URLProtocol.registerClass`, which only covers some URL loading paths.
   - `KNOWN_LIMITATIONS.md` already admits this is advisory, not absolute.

3. The engineering bar is not yet enforced mechanically.
   - Production code still contains `try!`, raw `NSError`, and many `try?` / silent-failure paths.
   - This is process debt, not just cleanup debt.

4. Documentation drift is now large enough to hurt trust.
   - `architecture.md` is still for “SOMA” and references an old stack.
   - `KNOWN_LIMITATIONS.md` still says there is no real share extension, widget/live activity, App Intents, metrics, or conversation browser.

5. Ambient context is built but not fully exploited.
   - `AmbientSnapshotAssembler` exists in `AppContainer`, but the snapshot is not part of the core chat loop.
   - The “right now” advantage is under-realized.

6. Persistence edges are not transactional enough yet.
   - Share-extension queue is a shared JSON array file, which is fragile under concurrent writes.
   - Memory and conversation saves still have silent-failure paths.

### Recommended architecture direction

1. Add an `ActionPolicyEngine`.
   - Every skill declares: read/write, side-effect class, confirmation rule, rollback support, required user intent.
   - Only user-turn authority can unlock mutating tools.
   - Retrieved notes, imports, and fetched content can never authorize a write.

2. Split memory into:
   - append-only evidence ledger
   - derived fact store
   - rendered markdown audit view
   This keeps the current “inspectable memory” UX while making updates, deletions, migrations, and future Android parity easier.

3. Replace the share-extension queue with a spool directory.
   - One file per pending ingestion item.
   - Atomic append, no read-modify-write race, better crash recovery.

4. Create a deterministic “fast lane” for common actions.
   - Reminders, date parsing, scheduling, contact resolution, and navigation should prefer local parsers / rules first.
   - Let Gemma handle ambiguity and language, not every action parse.

5. Introduce receipts everywhere.
   - Answer receipts: which memories / notes / live sources were used.
   - Action receipts: what was proposed, confirmed, executed, and how to undo it.
   - Memory receipts: what new fact was saved and from which turn.

6. Keep Phase 10a / 10b deferred.
   - User touched both phases this session.
   - Upstream dependency remains the same: ship and harden Phase 8/9 first, especially trust boundaries and action safety.

### Suggested next steps

1. Harden trust boundaries before adding more capability.
2. Update stale docs so the repo’s stated state matches reality.
3. Add lint / CI guards for forbidden failure patterns.
4. Build an action-policy layer before enabling more mutating tools.
5. Wire ambient context into chat as ephemeral, non-durable context.

### Files most relevant to the analysis

- `masterplan.md`
- `KNOWN_LIMITATIONS.md`
- `architecture.md`
- `Eidos/RAG/RAGPipeline.swift`
- `Eidos/Inference/PromptTemplates.swift`
- `Eidos/Platform/EgressGuard.swift`
- `Eidos/Platform/AmbientSnapshot.swift`
- `Eidos/Skills/Builtin/RemindersSkill.swift`
- `Eidos/UI/Chat/ChatViewModel.swift`
- `EidosShareExtension/ShareViewController.swift`

### Repo changes this session

- Added this session note only.
- No architecture or plan change was committed to `masterplan.md`.
- No `history.md` update: analysis session, but no product-direction decision was finalized.
