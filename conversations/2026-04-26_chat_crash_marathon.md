# 2026-04-26 — Chat-crash marathon (v3 -> v12)

Twelve-build session compressing what was meant to be one ship into
twelve. The headline lesson: every layer of the iPhone Gemma 4 stack
that we touched had at least one undocumented landmine. The actual
fixes are mundane individually; the value of this record is the
sequence of dead-ends so the next session doesn't repeat them.

## Context entering the session

- Single external tester (free Apple ID + AltStore + iPhone 17 Pro
  Max running iOS 26.3.1) with limited daily install quota.
- v3 already shipped before the session. App was launching but chat
  was crashing on send.
- Codebase: `mlx-swift-lm` + Gemma 4 E2B 4-bit, custom RAG pipeline,
  MD-backed memory, AppContainer DI, EgressGuard.

## Dead ends, in order

### Dead end 1: assumed prompt size killed chat (v7)
We diagnosed v6's chat crash as "the full RAG prompt is 10-15K tokens
and iPhone Metal can't prefill it". Built `RAGPipeline.chatLite()` that
ships a 250-char prompt. Chat still crashed. Prompt size alone wasn't
the issue.

### Dead end 2: assumed bigger prompt fixes the lying (v10)
After v9 made chat work, Gemma was fabricating tool calls
("Reminder set", "Alarm set"). Doubled the chatLite system prompt to
999 chars with markdown headers + smart quotes + the literal strings
"Reminder set". Chat broke completely. Had to revert.
LESSON: Gemma 4 E2B's chat template tokenization is sensitive to
markdown content + smart quotes + instruction-content strings.
chatLite prompts must be plain ASCII.

### Dead end 3: assumed cacheLimit cap helps memory (v10)
Set `MLX.Memory.cacheLimit = 256 MB` thinking it would force eager
release. It blocked legitimate KV-cache allocation for chat-length
outputs. Removed in v11.
LESSON: don't manually cap MLX cache on iPhone. Trust the default.
`Memory.clearCache()` between calls is the right tool, not the cap.

### Dead end 4: thought the lock alone was enough (v10 -> v11)
Added FIFO inference lock to `generateText` but missed
`generateMultimodal`. Image upload still raced briefing. Refactored
in v11 to extract `runGuardedGeneration` helper that both paths use.
LESSON: when adding cross-cutting safety mechanisms, refactor first,
add the mechanism in the shared helper. "Add to one path then the
other" leaks regressions.

## Real bugs found and fixed

| Build | Bug | Root cause | Fix |
|---|---|---|---|
| v6 | Launch crash, EXC_BREAKPOINT in DeviceProfile.formFactor | static-let lazy init called `MainActor.assumeIsolated` from off-main | warmUp() on MainActor in EidosApp.init(); nonisolated(unsafe) backing |
| v9 | Chat 2nd-call crash, no Swift error | mlx-swift-lm ModelContainer state reuse on iPhone Metal | `MLX.Memory.clearCache()` between every generation, matches BenchmarkHelpers practice |
| v10 | Mic crash with `OSStatus -50` | `.spokenAudio` mode not valid for `.record` category on iOS 26.3.1 | Use `.measurement` mode (Apple's documented SFSpeechRecognizer pattern) |
| v10 | Image "token count mismatch" | `UserInput(messages:, images:)` doesn't inject placeholders | `UserInput(chat: [Chat.Message])` with images on last user message |
| v10 | "New conversation" tap crash mid-stream | SwiftData rows torn down while streaming Task still appending | Guard `newConversation()` on `isGenerating` |
| v11 | Speech permission crash | TCC callbacks inherited MainActor isolation from the @MainActor enclosing class, trapped when called off-main | `@Sendable` on every TCC + audio-engine + recognition-task closure |
| v12 | Chat crashes silently mid-stream after v11 fixes | MainActor starvation from per-token UI redraws, plus reverted pre-flight memory check | Token-batched UI updates (60ms throttle), pre-flight `isMemoryConstrained`, NSUncaughtException + signal handlers, scenePhase memory-pressure observer |

## Architectural invariants captured (now in CLAUDE.md and developer_log.txt)

1. `DeviceProfile.warmUp()` runs on MainActor before any background actor reads `formFactor`.
2. `MLX.Memory.clearCache()` between every generation is mandatory on iPhone.
3. Every TCC / audio / speech-recognition callback inside a `@MainActor` class must be `@Sendable`.
4. `AVAudioSession.record` pairs with `.measurement`, never `.spokenAudio`.
5. `ChatViewModel` throttles UI updates to ~60ms during streaming.
6. `generateText` and `generateMultimodal` both funnel through `runGuardedGeneration(...)`.
7. Pre-flight `DeviceProfile.isMemoryConstrained` check before any prefill.
8. Diagnostics > Smoke test pane is the regression baseline.
9. `chatLite` system prompt: ASCII-only, no markdown, no instruction-content strings.

## Decisions locked

- **Engine**: stay on MLX Swift (Apple-native, best Apple-Silicon fit).
- **Model**: Gemma 4 E2B 4-bit (community-fork PRs unmerged in mlx-swift-lm; we accept that risk in exchange for the model's quality fit for the use case — strongest available multimodal model that fits iPhone envelope).
- **Logging discipline**: codified in CLAUDE.md `## Logging discipline` section. Every meaningful action gets a labeled log entry.
- **Defer to v11+**: re-enable RAG / tools / ambient incrementally behind feature flags after v12 on-device validation.

## Open at session end

- v12 awaiting on-device test (tester unavailable).
- `architecture_audit_2026-04-27.md` produced with 10 ACTION items.
- `work_log_2026-04-27.md` tracks the mass-implementation sweep starting immediately after this record.
