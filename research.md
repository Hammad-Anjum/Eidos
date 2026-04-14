# Eidos — Research & Architectural Exploration

Deep dives on ideas being evaluated for inclusion in the build. **Distinct from [notes.md](notes.md)** — that file is "what we know is true and have committed to." This file is "what we're considering, with the trade-off analysis."

Each section ends with a **Recommendation** — accept, reject, or defer (with conditions).

---

## Contents

1. [Idea 1 — A compact OpenClaw-style agent loop on top of Gemma 4](#idea-1--a-compact-openclaw-style-agent-loop-on-top-of-gemma-4)
2. [Idea 2 — Vectorless RAG (PageIndex) instead of, or alongside, vector RAG](#idea-2--vectorless-rag-pageindex-instead-of-or-alongside-vector-rag)
3. [Cross-cutting: total inference budget per user turn](#cross-cutting--total-inference-budget-per-user-turn)
4. [Source links](#source-links)

---

## Idea 1 — A compact OpenClaw-style agent loop on top of Gemma 4

> "Android has an OpenClaw app that allows running agents on your phone. Is it possible to build a smaller, compact version of OpenClaw as an app/feature that connects directly to Gemma 4 enabling agentic workflows rather than using the 'agentic skills' provided by Google AI Edge?"

### What OpenClaw actually is

OpenClaw (originally "Clawdbot" / "Moltbot") is an open-source autonomous agent project by Peter Steinberger, released November 2025 and gone viral in early 2026. Key facts:

- **MIT-licensed, local-first.** Agent state lives as Markdown files on disk; no required cloud backend for state.
- **LLM-agnostic by design.** It connects to *external* LLMs — Claude, DeepSeek, OpenAI's GPT, etc. The "local" part is the agent runtime, **not** the model.
- **UX is messaging-app-first.** Multi-channel inbox: Signal, Telegram, Discord, WhatsApp, Slack, Matrix, iMessage, etc. The user talks to the agent via whatever messaging platform they already use.
- **Portable skill format.** Skills are defined in a community-extensible format that can be shared between OpenClaw instances.
- **Android setup is non-trivial.** Runs in Termux/Ubuntu on Android (i.e. it's a Linux process running inside a chroot-equivalent), with Google Assistant App Actions integration to let users trigger it via voice.
- **Substantial security surface.** Trend Micro and others have flagged prompt-injection risks; China restricted state use of OpenClaw in March 2026 over privacy concerns. Because the agent has access to email, calendars, messaging, etc., a misconfigured instance is dangerous.

**The honest assessment**: OpenClaw is a *full app platform*, not a library. Most of its value sits in the **integrations** (the 20+ messaging channels, the Markdown skill format, the multi-channel inbox model) and in the **agent loop** (Plan-then-Execute style with Markdown memory). The "agent runs locally" framing is partially marketing — by default it talks to cloud LLMs.

### What "Google AI Edge agentic skills" actually provide

Three distinct things, often conflated:

1. **Gemma 4 native function calling.** Trained into the model. The model emits structured tool-call tokens via constrained decoding. One inference call per tool decision.
2. **FunctionGemma 270M** ([huggingface.co/google/functiongemma-270m-it](https://huggingface.co/google/functiongemma-270m-it)). A tiny specialised model that translates natural language directly into function calls. Designed to run *next to* a larger generative model so the heavy lifting of tool routing is offloaded to a 270M parameter helper.
3. **Agent Skills** in Google AI Edge Gallery — the iOS/Android demo app showing multi-step autonomous workflows entirely on-device, with tool calling, RAG, and a loop runtime. This is the "agent runtime" part, packaged as Google's reference impl.

So when the spec said "use Google AI Edge agentic skills," it meant: use Google's loop runtime + Gemma 4's native function calling + (optionally) FunctionGemma as a router.

### What we'd actually be building if we rolled our own

Not "OpenClaw on iOS" — that would mean cloning a chat-platform integration layer we don't need (Eidos has its own chat UI, doesn't talk to Signal/Telegram). The salvageable parts:

- **The agent loop pattern** (Plan-and-Execute, ReAct, ReWOO, etc.)
- **Markdown agent memory** (which ironically aligns naturally with our SwiftData `@Model` approach — same conceptual shape, different storage)
- **A portable skill format** (already drafted in our `SkillProtocol`)

What we'd write:
1. A `Planner` actor that takes a user goal + available skills and produces a plan (an ordered list of steps, each step naming a skill + parameters)
2. An `Executor` actor that runs the plan step-by-step, dispatching to skills and feeding results back
3. An optional `Replanner` that revisits the plan after each step if a step fails or returns unexpected output
4. A `PlanTrace` model for showing the user what the agent is doing

This is on top of the existing `SkillRegistry` and `RAGPipeline`. Not a rewrite — a layer above.

### ReAct vs Plan-and-Execute for our constraints

This matters because the choice determines our **per-turn inference budget** on a battery-and-thermal-constrained device.

| | ReAct | Plan-and-Execute |
|---|---|---|
| **Inference calls per task** | N+1 where N is the number of steps. Each step = think + act + observe = at least one model call. | 1 plan call + 1 call per step (often deterministic, sometimes a small follow-up). Replanning adds 1 more if needed. |
| **Latency** | High — each step is sequential and includes a model think. | Medium — plan is one expensive call up front; execution can stream / parallelise / use deterministic code. |
| **Battery / thermal cost** | High. Many model calls = many decode passes = sustained Neural Engine load. | Lower. Model is hit once for planning; execution is mostly cheap. |
| **Failure recovery** | Naturally adaptive — sees observation, adjusts next step. | Brittle unless replanning is wired. |
| **Quality on small models (2–4B)** | Mediocre — small models drift over many think/act loops, lose the goal. | Better — small models can produce a flat plan in one shot, then execute mechanically. |
| **Implementation complexity** | Lower (it's a while-loop). | Higher (planner + executor + replanner + plan model). |

The literature (research papers on small-LLM agent loops, the [bot-with-plan](https://github.com/krasserm/bot-with-plan) project, Microsoft and Anthropic agent-pattern guides) is **strongly aligned**: for small on-device models in resource-constrained environments, **Plan-and-Execute beats ReAct** on every axis except adaptive failure recovery — and that gap closes when you add a Replanner.

### Recommendation: build a Plan-and-Execute layer, but **defer the rich agent loop to Phase 6+**

**Accept the idea conditionally.**

For Phase 3 (the original RAG + skills milestone), do the **simple thing**: use Gemma 4's native function calling in a single-pass loop. The model decides per-turn whether to call a tool. This is a 1-shot agent, not multi-step.

For **Phase 6+** (after the core app is shipping), add a Plan-and-Execute layer on top:

- New file: `Eidos/Agents/Planner.swift` — calls `GemmaSession` once to produce a plan from a user goal + the `SkillRegistry.enabledSkills` schema. Plan is structured JSON via Gemma's constrained decoding.
- New file: `Eidos/Agents/Executor.swift` — walks the plan, dispatches to `SkillRegistry`, captures results.
- New file: `Eidos/Agents/Replanner.swift` — invoked when an executor step fails or returns `isError = true`. Calls `GemmaSession` again with the failure context to produce a revised tail of the plan.
- New file: `Eidos/Agents/PlanTrace.swift` — `@Observable` model the chat UI subscribes to, so the user sees "🔧 Searching knowledge base… ✓ Found 3 results, 📅 Checking calendar…" in real time.
- Storage: plan traces persist as a sibling of `Conversation` so users can review what the agent did.

What we **don't** copy from OpenClaw:
- Multi-channel messaging integrations (Signal/Telegram/etc.) — irrelevant, Eidos has its own UI
- Markdown skill format — we use `SkillProtocol` which is more type-safe and works better with Swift
- Termux/Linux runtime — irrelevant, we're a native iOS app
- Cloud LLM connectors — explicitly forbidden by §B14 (zero egress)

What we **do** borrow:
- The Plan-and-Execute pattern
- The "user-visible plan trace" UX
- The notion that agent memory should be inspectable (we get this from SwiftData by default)

**Why defer to Phase 6**: Phase 3 needs to ship the *baseline* RAG-with-tools experience first. Adding a multi-step planner before that ships is feature creep. And we'll have real device data on per-turn inference cost by the time Phase 6 starts, which de-risks the planner's energy/thermal impact.

**Updated phase impact**:
- Phase 3 stays as planned: single-pass function calling, 1 model call per user message.
- Phase 6 gains a new sub-section: "Agent Loop (Plan-and-Execute on top of skills)."

### Open questions for Phase 6

1. **Plan format.** JSON via constrained decoding (matches A2's existing approach for tool calls)? Or natural-language steps that get re-parsed?
2. **Replanning trigger.** Just on `SkillResult.isError == true`, or also on heuristics like "retrieved zero KB hits when expecting some"?
3. **Plan caching.** If the user asks the same goal twice, can we replay the plan without re-running the planner? Probably yes, with a content-hash key.
4. **User intervention.** Should the user be able to pause/edit/approve the plan before execution starts? OpenClaw does this. It's a privacy-positive UX but adds friction.

---

## Idea 2 — Vectorless RAG (PageIndex) instead of, or alongside, vector RAG

> "Is it possible to ditch vector databases and vector-based RAG and switch to vectorless RAG (such as PageIndex), or should both be implemented because they have their own trade-offs?"

### What PageIndex actually is

PageIndex ([github.com/VectifyAI/PageIndex](https://github.com/VectifyAI/PageIndex)) is a "vectorless, reasoning-based RAG" approach with two phases:

**1. Indexing (one-time, per document, expensive)**
- Take a document (typically a long PDF — book, financial statement, legal contract, manual)
- Use an LLM to infer a hierarchical table-of-contents tree: chapter → section → paragraph
- Generate an LLM-written summary for **each node** in the tree
- Store the tree as nested JSON / structured data — no vectors anywhere

**2. Retrieval (per query, also expensive but smarter)**
- LLM examines the top-level chapter summaries
- Decides which chapter probably contains the answer
- Drills into that chapter, examines its section summaries
- Continues until reaching the leaf node with the actual content
- Returns the leaf as context for the answering LLM call

It's literally "the LLM walks the document outline like a human reading the table of contents." No embeddings, no chunking, no cosine similarity.

**Reported strengths**: 98.7% accuracy on FinanceBench (a benchmark for QA over financial reports), beating vector RAG. Strong on long, well-structured single documents where the structure carries semantic meaning.

**Reported weaknesses**:
- **Multi-document scaling is bad.** Tree-building cost grows linearly with documents, and a multi-doc query has to walk multiple trees.
- **Indexing is LLM-expensive.** Every node summary is an LLM call. A 50-page PDF with ~100 nodes is ~100 inference calls just to index.
- **Retrieval is also LLM-expensive.** Each tree-walking step is another model call. A 4-level tree = at least 4 calls per query.
- **Bad fit for short / unstructured content.** A voice note, a single paragraph from a chat, a tweet — there's no "structure" to walk.

### Why PageIndex's strengths *don't* match Eidos's content profile

Eidos's knowledge base is dominated by **short, unstructured, high-volume** content:

| Source | Typical length | Structure |
|---|---|---|
| Voice notes | 1–5 sentences | None |
| Calendar events | 1 line + a few fields | Schema, but flat |
| Contacts | A few key:value pairs | Flat schema |
| WhatsApp messages | Many short messages, conversational | Implicit by sender + time |
| Email | Few paragraphs to a few pages, threaded | Header + body |
| Web clips | A paragraph to a full article | HTML, lossy |
| Manual notes | A sentence to a paragraph | None |

Compare to PageIndex's sweet spot: a 100-page financial statement with chapter/section/subsection structure. Eidos's content is the *opposite*. A tree-walking LLM has nothing to walk for a voice note.

**Even worse**: most queries will span multiple sources. "What did Sarah say about the project last week?" has to look at WhatsApp + email + calendar + notes simultaneously. PageIndex would have to build a separate tree per source and walk all of them — exactly the multi-document scenario where it's known to be weak.

### Cost analysis on-device

This is the hard constraint that decides it. Numbers below are rough but order-of-magnitude correct for Gemma 4 E2B (4-bit) on iPhone 13 Pro.

| Operation | Vector RAG (current) | PageIndex |
|---|---|---|
| **Index a 1-paragraph voice note** | 1 embedding call (~50ms on Neural Engine) | 1+ LLM summary call (~2–5s on iPhone) |
| **Index a 50-page PDF** | ~100 embedding calls (~5s) | ~100 LLM summary calls (~3–8 minutes) |
| **Query latency** | Single dot-product scan (~5–20ms via vDSP) | 3–6 sequential LLM tree-walking calls (~6–30s) |
| **Storage per chunk** | 384–512 floats = 1.5–2 KB | Variable, typically 50–500 bytes per node summary |
| **Battery cost per query** | Negligible (no inference) | Significant (multiple full inference passes) |
| **Thermal pressure under load** | Minimal | High during indexing AND querying |

The numbers that should jump out:

- **Indexing a single shared PDF could take 3–8 minutes of sustained on-device inference.** That's an unusable share-and-wait UX. You'd need to backgound the work, deal with iOS suspension, and surface progress.
- **Query latency of 6–30 seconds** is much worse than vector RAG's 5–20ms. The user is waiting on the model to walk a tree before the *answering* model call even starts.
- **Battery cost is the killer.** Every query becomes 4–7 model calls instead of 1. On an iPhone 13 Pro running Gemma 4 E2B, this scales linearly with queries-per-day and would visibly hurt battery life.

### When PageIndex *does* make sense for Eidos

There's a narrow but real use case: **the user explicitly imports a long structured document they care about deeply and want to query repeatedly.**

Examples:
- A book they're studying
- A multi-hundred-page legal contract
- A long technical manual
- A tax return or financial statement

For those documents, a one-time multi-minute indexing cost is acceptable in exchange for dramatically better question answering. The user opts in by tapping "build deep index" on a specific document.

Everything else — short notes, messages, web clips, voice memos — should keep using the existing hybrid vector + keyword RRF search from Phase 1. It's faster, cheaper, and well-matched to the content shape.

### Recommendation: dual-track, with PageIndex as an **opt-in Phase 6+ feature** for select documents

**Accept the idea conditionally.** Vector RAG remains the default. PageIndex becomes an optional secondary index for specific documents.

**Architecture sketch (Phase 6+)**:

- New `EntrySource` value: `.deepIndexed` (or add a flag to `KnowledgeEntry.metadata`)
- New `@Model`: `PageIndexNode { id, parentID, title, summary, depth, leafContent }` — the tree, persisted in SwiftData like everything else
- New file: `Eidos/KnowledgeBase/PageIndexBuilder.swift` — async actor that takes a long document, calls Gemma to summarise nodes, persists the tree. Runs as a background `BGProcessingTask` so it survives iOS suspension.
- New file: `Eidos/KnowledgeBase/PageIndexRetriever.swift` — alternate retrieval path that walks a stored tree using Gemma calls. Used only when the query is routed to a deep-indexed entry.
- **Routing**: `KnowledgeRepository.search` first runs the existing hybrid RRF over everything, then if the top result happens to be a `.deepIndexed` entry, optionally invokes the tree walker for that entry's tree to refine the snippet. This gives PageIndex's accuracy on the documents that benefit, without paying its cost on the documents that don't.
- **UX**: a "Build deep index" button on the KB browser entry detail view, only visible for entries longer than ~5000 characters. Tapping kicks off the background build with a progress indicator.

**Why dual-track and not full replacement**:
- Replacing vector RAG would require LLM inference on every query — kills battery and adds 6–30s latency
- Replacing vector RAG would require LLM inference on every ingestion — makes voice notes feel broken
- Multi-document queries (the dominant case for a personal assistant) are vector RAG's strength
- Long-document deep dives (the rare case) are PageIndex's strength

**Why not just stick with vector RAG**:
- Long structured documents *do* benefit measurably from PageIndex's approach — the FinanceBench results aren't fake
- A privacy-first personal AI that handles your tax return, your medical records, or a contract you're reading should give the best possible answers on those high-stakes docs
- The cost is bounded: it only kicks in when the user explicitly opts in for a specific document

**Why defer to Phase 6**:
- Phase 3 needs a working baseline RAG first, and Phase 1 already delivered it
- Real-device latency numbers from Phase 2 + 3 will tell us whether the multi-call retrieval cost is tolerable or impossible on iPhone 13 Pro
- PageIndex is enhancement, not foundation

### Open questions for Phase 6

1. **Background indexing under iOS suspension.** A 5-minute index build won't fit in a single foreground session. Need `BGProcessingTask` with checkpointing, so a partial tree survives a kill.
2. **Does Gemma 4 E2B produce good enough node summaries?** PageIndex's published numbers are with much larger models. The summarisation quality bottleneck is real — bad summaries break tree walking.
3. **Tree storage cost.** A 100-node tree with ~200-byte summaries is ~20 KB. Cheap. But for a power user with 50 deep-indexed docs, that's still under 1 MB. Fine.
4. **UX for "still indexing."** The user shares a PDF, taps "deep index," and is told to come back in 5 minutes. How do we surface progress? A persistent banner? A notification? (No push, so local notification only.)
5. **Failure mode**: what if the model produces malformed JSON during tree-building? Retry with a smaller chunk, or fall back to flat embedding? Need a tested fallback path.

---

## Cross-cutting — total inference budget per user turn

Both ideas above bump the per-turn inference cost. Worth modelling explicitly.

**Phase 1 reality (today, what we ship)**:
- Embed query: 1 small NLContextualEmbedding call (~10ms, Neural Engine, no battery hit)
- Vector search: vDSP dot product (~5ms, no inference)
- Generate answer: 1 Gemma 4 streaming call
- **Total: 1 large model call per turn.**

**Phase 3 plan (single-pass function calling)**:
- Same as Phase 1, but the single Gemma call may emit a tool invocation
- If a tool fires, dispatch + 1 follow-up generation call
- **Total: 1 to 2 large model calls per turn.**

**Hypothetical Phase 6 with full Plan-and-Execute**:
- Plan call: 1 large model call
- Per step: 0 (deterministic) to 1 (skill needs reasoning) model calls
- Replanner if a step fails: +1 model call
- Final synthesis: 1 model call
- **Total: 3 to ~6 large model calls per turn for a multi-step task.**

**Hypothetical Phase 6 with PageIndex query path on a deep-indexed doc**:
- Embed query: 1 small call
- Vector pre-route: ~5ms
- Tree walking: 3 to 6 medium model calls (each examines a few summaries and decides)
- Final synthesis: 1 large call
- **Total: 4 to 7 large model calls per turn.**

**Worst case (both features active, multi-step plan that involves a deep-indexed doc lookup)**:
- ~10–12 large model calls per user message
- Each call is ~3–10 seconds on iPhone 13 Pro running Gemma 4 E2B
- Total turn time: ~30 seconds to 2 minutes
- Battery cost: very high

**Constraint to bake in now**: any feature that pushes per-turn cost above ~3 large model calls needs an explicit user opt-in (a setting or a per-message gesture). The default conversational mode stays at 1–2 model calls per turn.

This constraint should land in [notes.md](notes.md) Design Constraints when the dust settles on Phase 6.

---

## Source links

### OpenClaw / agent loops
- [OpenClaw GitHub](https://github.com/openclaw/openclaw)
- [OpenClaw — Wikipedia](https://en.wikipedia.org/wiki/OpenClaw)
- [OpenClaw — official site](https://openclaw.ai/)
- [Trend Micro — Viral AI, Invisible Risks: What OpenClaw Reveals](https://www.trendmicro.com/en_us/research/26/b/what-openclaw-reveals-about-agentic-assistants.html)
- [ReAct vs Plan-and-Execute: A Practical Comparison](https://dev.to/jamesli/react-vs-plan-and-execute-a-practical-comparison-of-llm-agent-patterns-4gh9)
- [Pre-Act paper — multi-step planning improves acting in LLM agents](https://arxiv.org/html/2505.09970v2)
- [Architecting Resilient LLM Agents: Plan-and-Execute](https://arxiv.org/pdf/2509.08646)
- [bot-with-plan — separation of planning concerns in ReAct](https://github.com/krasserm/bot-with-plan)
- [Bring state-of-the-art agentic skills to the edge with Gemma 4 — Google Developers](https://developers.googleblog.com/bring-state-of-the-art-agentic-skills-to-the-edge-with-gemma-4/)
- [On-Device Function Calling in Google AI Edge Gallery](https://developers.googleblog.com/on-device-function-calling-in-google-ai-edge-gallery/)
- [FunctionGemma 270M — Hugging Face](https://huggingface.co/google/functiongemma-270m-it)

### PageIndex / vectorless RAG
- [PageIndex GitHub](https://github.com/VectifyAI/PageIndex)
- [PageIndex — official intro](https://pageindex.ai/blog/pageindex-intro)
- [Vectorless RAG: How PageIndex Works (2026 Guide)](https://www.buildfastwithai.com/blogs/vectorless-rag-pageindex-guide)
- [Vectorless Reasoning-Based RAG — Microsoft Community Hub](https://techcommunity.microsoft.com/blog/azuredevcommunityblog/vectorless-reasoning-based-rag-a-new-approach-to-retrieval-augmented-generation/4502238)
- [PageIndex RAG vs Traditional RAG: I Tested Both](https://medium.com/@shubhamnv2/pageindex-rag-vs-traditional-rag-i-tested-both-heres-what-actually-works-in-2026-5a990726a80f)
- [Beyond Vector Databases — DigitalOcean tutorial](https://www.digitalocean.com/community/tutorials/beyond-vector-databases-rag-without-embeddings)
- [Vector vs Vectorless RAG — Why Embeddings Still Matter](https://medium.com/@abhijit.khuperkar/vector-vs-vectorless-rag-556893b8f098)
- [Proxy-Pointer RAG — vectorless accuracy at vector RAG scale](https://towardsdatascience.com/proxy-pointer-rag-achieving-vectorless-accuracy-at-vector-rag-scale-and-cost/)
