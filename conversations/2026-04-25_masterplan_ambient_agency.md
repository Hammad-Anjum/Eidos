# 2026-04-25 — Masterplan ambient-agency update

## Context

The user asked to tighten the future roadmap around Eidos's core vision:

- not "another AI app"
- more like another part of the phone
- fewer commands over time, not more
- clear differentiation from conventional chat-first AI apps
- concrete additions to the masterplan so the long-term idea is buildable

## What changed

Updated `masterplan.md` to make the future plan more operational and less vague.

### 1. Added a new top-level product goal

`What We're Building` now explicitly includes:

- **Fades into the phone** — prepares, suggests, and quietly acts with permission so the best interaction is often no interaction

### 2. Added `Product Laws For Ambient Eidos`

Inserted a new cross-cutting section that future work must obey:

1. Situation solved > chat turn completed
2. Prepare more than you execute
3. Authority is earned, never assumed
4. Every action needs a receipt
5. Background work must be event-driven and battery-safe
6. Keep the human-audit layer (Markdown) while adding structured action state

This is the strategic guardrail against drifting into "small ChatGPT on iPhone."

### 3. Added `Phase 9.5 — Ambient Agency + Trust Rails`

New planned phase, explicitly prioritized as the core moat after Phases 8 and 9.

It defines the missing systems required for Eidos to feel like part of the phone:

- `AuthorityProfile` + `ActionPolicyEngine`
- structured stores for `people`, `commitments`, `routines`, `prepared_actions`, `receipts`
- `CommitmentLedger`
- `PeopleGraph`
- `RoutineGraph`
- `PreparationEngine`
- `SurfaceRouter` + `AttentionBudget`
- `ReceiptCenter`
- `SensitiveVault`
- `BackgroundTriggerMatrix`
- autonomy ladder: observe -> suggest -> draft -> confirm -> auto-act
- success metrics centered on fewer commands and more ambient value

### 4. Re-prioritized web/cloud work

`Phase 10a` (web search) and `Phase 10b` (hybrid cloud / JARVIS) remain in the plan, but their gates now explicitly come **after** ambient-agency work. The logic recorded in the masterplan:

- web/cloud are optional accelerants
- ambient agency + receipts are the actual product moat

### 5. Clarified product differentiation

`What Makes Eidos Different` now states the category thesis directly:

- conventional AI apps optimize answer quality per prompt
- Eidos optimizes continuity, initiative, and receipts
- the north-star is more life handled with fewer commands

### 6. Minor roadmap alignment

- `masterplan.md` last-updated date moved to `2026-04-25`
- Phase 2 real-device TODO now says `iPhone 15 Pro+ / iOS 26` to match the hardware floor already implied elsewhere

## Why this matters

Before this session, the plan had strong pieces:

- memory
- skills
- privacy
- widgets / intents / diagnostics
- future web + hybrid ideas

But it still lacked an explicit roadmap for how Eidos becomes:

- low-command
- phone-native
- trustworthy enough to act
- materially different from ordinary AI chat apps

`Phase 9.5` is the missing bridge between "smart local assistant" and "ambient agent with receipts."

## Open items

- `masterplan.md` still contains some older historical wording / counts that should be synced separately if we do a broader documentation cleanup pass.
- The repo still needs the real implementation of the autonomy systems defined here; this session only updated the plan.
- Current build/test issues were not part of this roadmap pass.

## Suggested next decision

After Phase 8 stabilizes and Phase 9 is better defined in implementation terms, the next strategic document pass should specify:

- the exact schema for `commitments`, `prepared_actions`, and `receipts`
- the user-facing permission ladder UI for `suggest / confirm / auto_act`
- the scoring model for `SurfaceRouter` and `AttentionBudget`
