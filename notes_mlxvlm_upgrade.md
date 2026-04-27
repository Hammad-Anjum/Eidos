[NOTES] 2026-04-27 — NEXT-10: MLXVLM upgrade audit
================================================================

NOT a code change. This is a written audit of where the MLXVLM
upgrade stands today and the concrete steps to land it. We
intentionally don't ship the swap in this sweep because it touches
the inference path and the chat-stability story is still being
validated on-device after the v12 + Phase 8.2 changes.

CURRENT STATE
-------------
- `Eidos/Inference/GemmaSession.swift` imports both `MLXLLM` and
  `MLXVLM` (the latter via `#if canImport(MLXVLM)`).
- `runGuardedGeneration` -> `container.prepare(input:)` ->
  `container.generate(input:parameters:)` is the current path.
  This works for both MLXLLM and MLXVLM containers because the
  shared `ModelContainer` API is the same.
- `generateMultimodal` builds `UserInput(chat: [Chat.Message])`
  with images attached to the last user message. The
  `MessageGenerator` resolves to the model-specific message
  generator (Qwen2VLMessageGenerator, Gemma4MessageGenerator,
  etc.) at prepare time.
- The actual model load happens via
  `loadModelContainer(from:using:)` which is from MLXLMCommon.
  That helper is NEUTRAL between MLXLLM and MLXVLM — it just
  reads `config.json` and dispatches to the right factory.

WHAT THE UPGRADE ACTUALLY MEANS
-------------------------------
"MLXVLM upgrade" is misleading shorthand. The reality is:

(a) For Gemma 4 E2B, mlx-community ships a single
    `mlx-community/gemma-4-e2b-it-4bit` repo. Its `config.json`
    declares vision support. So when we call
    `loadModelContainer(...)`, MLXLMCommon reads the config and
    automatically picks the VLM-capable factory. We don't need
    to change which framework we IMPORT.
(b) The actual gating bug is upstream: `mlx-swift-lm` doesn't yet
    register the gemma4 architecture (Issue #389, PRs #180/#185/
    #187 unmerged as of 2026-04-27). Until those land OR we
    fork-pin, image inference produces "architecture unknown"
    errors regardless of which import path we use.
(c) Our existing `generateMultimodal` code is correct in shape.
    What's missing is upstream support for the model.

CONCRETE STEPS TO ACTUALLY LAND IMAGE
--------------------------------------
1. Watch mlx-swift-lm Issue #389 + the three PRs. When they
   merge and a new release is tagged:
     - bump `Package.resolved` for mlx-swift-lm
     - re-run `xcodegen generate`
     - test image upload smoke path on simulator (mock) +
       physical device
2. If the wait becomes blocking for a hackathon / ship date:
     - fork mlx-swift-lm
     - cherry-pick PR #185 (text gemma4 register) at minimum,
       PR #180 (vision/MoE) if image is required
     - point `project.yml` at the fork URL
     - this is reversible — flip back when upstream lands

VALIDATION CHECKLIST WHEN IT'S TIME
------------------------------------
- DiagnosticsView -> Smoke test still passes after the package
  update. (Confirms text inference didn't regress.)
- New end-to-end image test: take a photo, send "describe this",
  verify a non-empty reply.
- Memory regression tests still green.
- KnownLimitations.md updated to remove the "image not yet
  supported" entry.

DECISION
--------
Defer the swap. The `runGuardedGeneration` shape we have today
is forward-compatible — when upstream lands gemma4 support, the
swap is a Package.resolved bump + xcodegen, NOT a code change.
This audit is recorded so the next session knows the upgrade
isn't blocked on our side.
