# 2026-04-27 — Phase 8.2 sweep, NEXT-1..10 sweep, retrieval research, SKG architecture

Continuation of the work that started with the v3-v12 chat-crash marathon
(see `2026-04-26_chat_crash_marathon.md`). v12 is shipped to GitHub but
not yet on-device validated; tester unavailable. This session was a
parallel-track of code consolidation + architectural research while
waiting.

## Top-line outcomes

1. **Logging discipline codified** — added a `## Logging discipline` section to `CLAUDE.md` defining label vocabulary (`[SHIP]`, `[DEV]`, `[FIX]`, `[BUG]`, `[DECISION]`, `[INVARIANT]`, `[BLOCKER]`, `[REGRESSION]`, `[DEFERRED]`, `[RESEARCH]`) and per-entry format. `developer_log.txt` reformatted to match.
2. **Phase 8.2 sweep landed** — 10 audit ACTIONs + 2 META + tests, all built and compile-clean against iOS Release. See `architecture_audit_2026-04-27.md` for the audit and `work_log_2026-04-27.md` for the per-action breakdown. Highlights: privacy snapshot overlay, biometric app lock, TLS hostname allowlist for HF download, structural prompt-injection defense, embedding-based memory recall, `InferenceSession` protocol, background nudge task scaffolding, regression tests.
3. **NEXT-1..10 sweep landed** — wired the dead code from Phase 8.2 into actual runtime paths. `MemoryRecallService` now constructed by `AppContainer` and called from `chatLite`. Curated tool catalogue available behind feature flag. Rolling token-budget conversation history. `NudgeBackgroundTask` registered in bootstrap. Mock `InferenceSession` + 6 chat-stream regression tests. Memory pinning UI. Conflict detection logging in crystallizer. Decay-report visible in Diagnostics. Onboarding privacy primer step. MLXVLM upgrade audit (defer until upstream lands gemma4).
4. **Retrieval architecture survey** — full research pass on GraphRAG, LightRAG, PageIndex, long-context CAG, hybrid (BM25+dense+RRF), Karpathy's April 2026 "LLM Wiki" pattern, embedding-model alternatives, and entity-storage approaches. Verdicts captured as `[DECISION]` entries in `developer_log.txt` and the full report in `research_retrieval_2026-04-27.md`.
5. **Self-Knowledge Graph (SKG) design** — user proposed a new memory architecture: zero-corpus cold start, user-centric topology, classification-driven append, decay-managed growth. Validated as the right architecture for Eidos's specific constraints. Specifically a synthesis that's distinct from GraphRAG / LightRAG / Karpathy's wiki / hybrid retrieval — the combination of all four properties (on-device + zero-corpus + decay + user-centric) is genuinely novel.

## Architectural decisions locked

Captured as `[DECISION]` entries in `developer_log.txt`:

- **Engine**: stay on MLX, keep Gemma 4 E2B 4-bit. Accept community-fork risk on `mlx-swift-lm` gemma4 PRs (still unmerged) in exchange for Apple-native runtime + best-fit multimodal model.
- **Database**: NO cloud (Supabase, etc.) — contradicts zero-egress. Stay on SwiftData (chat) + Markdown files (memory) + in-memory `VectorStore`. Future addition: `sqlite-vec` for persistent vector index.
- **Language**: NO C / C++ / Python / Rust rewrite. Swift is correct for everything that runs on iPhone. Apple frameworks (MLX, NLContextualEmbedding, Accelerate, AVFoundation) already wrap C/C++/Metal under the hood.
- **Retrieval**: hybrid BM25 + dense embeddings + RRF fusion is the 2026 best-practice path. Skip GraphRAG / LightRAG / PageIndex entirely (all infeasible on-device at single-user scale). Skip 128K context dump (OOM past 16-32K tokens on iPhone).
- **Embeddings**: keep `NLContextualEmbedding` as default. Pilot **EmbeddingGemma 308M** as opt-in upgrade behind a flag once we have a measured quality gap. Don't switch blind — Apple doesn't publish MTEB.
- **Entities**: YAML frontmatter tags + lazy SQLite `entity_mentions` table. NO first-class knowledge graph. Break-even where graphs pay off is 10K+ entities AND multi-hop relational queries; Eidos won't have either for years.
- **Memory architecture**: pivot to Self-Knowledge Graph (SKG) — categorize crystallized facts into ~10 fixed top-level categories at write time (3-tier classifier: NLTagger + keyword rules → NLContextualEmbedding centroid cosine → Gemma fallback). Per-category Markdown file as the canonical artifact. User-centric topology means edges are mostly user→category→fact with cross-references via entity tags.

Captured as `[INVARIANT]` entries in `developer_log.txt`:

- Storage layer ordering: Markdown files are SOURCE OF TRUTH; SwiftData / FTS5 / vector / entity indexes are DERIVED ARTIFACTS rebuilt from the markdown on change.
- Retrieval cost cap: no retrieval path may execute more than 1 LLM forward pass per chat turn. The single allowed pass is the chat reply itself.
- Plus all the v3-v12 invariants (DeviceProfile.warmUp, MLX.Memory.clearCache between calls, @Sendable on TCC callbacks, AVAudioSession .measurement mode, ChatViewModel 60ms throttle, runGuardedGeneration funnel, pre-flight isMemoryConstrained check, ASCII-only chatLite system prompt).

## Build verification

Both sweeps verified clean:
- Phase 8.2 sweep build: `** BUILD SUCCEEDED **` (zero errors, only pre-existing C++17 lints in `mlx-swift` package).
- NEXT-1..10 sweep build: `** BUILD SUCCEEDED **` (zero new errors).

## Files written this session

| File | Purpose |
|---|---|
| `developer_log.txt` (extended) | Phase 8.2 + NEXT-1..10 + DECISION/INVARIANT entries from research |
| `work_log_2026-04-27.md` | Per-action file:symbol map for both sweeps; canonical for one-by-one validation |
| `architecture_audit_2026-04-27.md` | 5-domain audit (core arch, tool calling, memory, security, background); 10 prioritized ACTIONs |
| `research_retrieval_2026-04-27.md` | Full retrieval architecture survey + verdicts; canonical for future retrieval questions |
| `notes_mlxvlm_upgrade.md` | NEXT-10 audit notes (defer until upstream gemma4 PRs land) |
| `CLAUDE.md` (extended) | New "Logging discipline" section codifying label vocabulary + format |
| `conversations/2026-04-26_chat_crash_marathon.md` | Session record for the v3-v12 marathon |
| `conversations/2026-04-27_phase82_and_skg.md` | This file |

Plus ~25 Swift files added or modified across `Eidos/`. See `work_log_2026-04-27.md` for the file:symbol map.

## What's pending

- v12 + Phase 8.2 + NEXT-1..10 on-device validation by tester (still unavailable as of 2026-04-27 evening).
- **SKG implementation** — `SKG-1` through `SKG-9` defined and ready, ~24 hours of focused work. User decision pending: start now or wait for v12 validation. Replaces the earlier `BRAIN-A/B/C` proposal — SKG is sharper.
- BG nudge task wiring landed in code but `Info.plist` `BGTaskSchedulerPermittedIdentifiers` + `UIBackgroundModes: [processing]` were added to `project.yml` and need an xcodegen regen + IPA build to take effect on device.
- AppContainer wires `MemoryRecallService` and registers `NudgeBackgroundTask` — both surfaces exist but need on-device exercise to confirm they work.
- Eight regression tests exist (Phase8_2 + ChatStreamRegression) but the test target hasn't been run end-to-end via `xcodebuild test` this session — only the app target was built.

## Open architectural questions

- At what user-memory-count does retrieval latency become user-visible on iPhone 17 Pro Max with hybrid retrieval? Not measured.
- What's the actual retrieval-quality delta between `NLContextualEmbedding` and `EmbeddingGemma 308M` on Eidos's domain? Apple doesn't publish MTEB so requires in-house eval.
- Does iOS 26 Foundation Models include a usable on-device embedding API beyond `NLContextualEmbedding`? Documentation is sparse.
- For the SKG: should categories be FIXED (10 top-level) or EXTENSIBLE? Current proposal is fixed top-level + free-form sub-tags. Worth user input before building.

## Decisions deferred

- LiteRT-LM engine swap — explicitly declined per user direction (stay on MLX with Gemma 4).
- MLXVLM image upgrade — blocked on `mlx-swift-lm` upstream merging gemma4 PRs (#180/#185/#187). When that lands, swap is a `Package.resolved` bump, not a refactor.
- Lock-screen widget for memory capture — deferred from audit ACTION-7. Needs a new Xcode target; risky to add mid-stability-validation.
- Apple Watch app — deferred. Audience too small to prioritize before product-market fit.
- True knowledge-graph DB — explicitly REJECTED. Personal-scale doesn't justify the complexity.

## Next session

Most likely entry point: **SKG-1** (define categories + ship `_profile.md` template) — the user proposed the SKG architecture and we validated it; the next step is to begin implementation. ~1 hour for SKG-1. Then SKG-2..9 in sequence (~24 hours total).

Alternative entry: package v13 IPA (Phase 8.2 + NEXT-1..10 absorbed) for the tester so they can validate when they're back, in parallel with starting SKG work.
