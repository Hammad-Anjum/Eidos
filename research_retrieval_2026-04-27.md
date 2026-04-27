[RESEARCH] 2026-04-27 — Retrieval architecture for personal-scale on-device second brain
================================================================

Triggered by user question: should Eidos implement GraphRAG / LightRAG /
PageIndex, or does the markdown-first design hold up? What does Karpathy
actually do? Which embedding model on iPhone?

This file is the canonical source for the architectural decisions
recorded as [DECISION] entries in `developer_log.txt` on 2026-04-27.

================================================================
TL;DR
================================================================

For a single user with hundreds-to-low-thousands of personal memories
on iPhone 17 Pro Max running Gemma 4 E2B:

- GraphRAG / LightRAG / PageIndex: ALL infeasible on-device at this
  scale. Skip permanently.
- Long-context "fit everything in 128K": OOM/slow past ~16-32K tokens
  on iPhone. Skip as primary, use as fallback only.
- Hybrid retrieval (BM25 + dense embeddings + RRF fusion): 2026 best
  practice for this exact use case. Build this.
- Karpathy's April 2026 "LLM Wiki" pattern: directly validates our
  markdown-first design. Adopt his ingest/query/lint operation triad.
- Embedding model: keep NLContextualEmbedding as default;
  EmbeddingGemma 308M as opt-in upgrade behind a flag once we have a
  measured quality gap.
- Entities: YAML frontmatter tags + lazy SQLite `entity_mentions`
  index. No first-class knowledge graph.

================================================================
DECISION TABLE
================================================================

  Architecture                  Build cost    Run cost     Quality        Verdict
  ─────────────────────────────────────────────────────────────────────────────────
  GraphRAG (Microsoft)          ~5 LLM        Fan-out      Best in        SKIP
                                passes/chunk; query;        cloud
                                25-30 hr      heavy
                                phone-time
                                for 500
                                memories

  LightRAG (HKUST)              1 LLM pass    Cheap query  Mediocre       SKIP
                                /chunk        (~100 tokens) on Gemma 4
                                indexing      vs ~600K     E2B
                                              GraphRAG

  PageIndex (Vectify)           Low (one      Multi-step   Wrong          SKIP
                                summary       LLM walk     shape for
                                /section)     /query       personal
                                              -- expensive notes

  Hybrid (BM25 +                Near-zero     <1 ms        15-30% lift    BUILD
  dense + RRF)                  (SQLite       /query       over either
                                FTS5 built-in              alone

  128K context dump             Free          OOM past     "lost in       SKIP
  (CAG)                                       16-32K       middle" on
                                              tokens on    2B model
                                              iPhone

  Karpathy LLM Wiki             Marginal      Cheap        Proven by      ADOPT
  pattern                       (lint pass)   (markdown    Karpathy's    PATTERN
                                              read)        own use

================================================================
RECOMMENDED ARCHITECTURE FOR EIDOS
================================================================

  ┌──────────────────────────────────────────────────────────┐
  │                  USER ASKS A QUESTION                    │
  └────────────────────────┬─────────────────────────────────┘
                           │
                           ▼
       ┌───────────────────────────────────────────┐
       │           HYBRID RETRIEVAL                │
       │                                           │
       │  ┌──────────────┐    ┌──────────────────┐ │
       │  │ BM25 (FTS5)  │    │ Dense embeddings │ │
       │  │ keyword      │    │ NLContextual or  │ │
       │  │ "thai"       │    │ EmbeddingGemma   │ │
       │  │              │    │ cosine via vDSP  │ │
       │  └──────┬───────┘    └────────┬─────────┘ │
       │         │ top-K              │ top-K      │
       │         ▼                     ▼           │
       │   ┌─────────────────────────────────┐     │
       │   │   Reciprocal Rank Fusion (RRF)  │     │
       │   │   k=60, merge ranks not scores  │     │
       │   └────────────────┬────────────────┘     │
       └────────────────────┼──────────────────────┘
                            │  fused top-K
                            ▼
       ┌─────────────────────────────────────────┐
       │         INJECTION (existing)            │
       │  Sanitize via PromptTemplates           │
       │  Wrap in <untrusted> in user turn       │
       │  Hand to chatLite -> Gemma              │
       └─────────────────────────────────────────┘

  Storage (unchanged):
       ┌──────────────────────┐
       │  Memory/<tier>/*.md  │  <- source of truth (Karpathy)
       │  YAML frontmatter +  │
       │  Markdown body       │
       └──────────┬───────────┘
                  │
       ┌──────────┴───────────────────────┐
       │                                  │
       ▼                                  ▼
  ┌─────────────────┐           ┌──────────────────────┐
  │ SQLite FTS5     │           │ sqlite-vec           │
  │ (BM25)          │           │ (or in-memory        │
  │ rebuilt on .md  │           │  VectorStore today)  │
  │ change          │           │                      │
  └─────────────────┘           └──────────────────────┘

  Plus, for entity-anchored queries ("what do I know about Anna"):
       ┌────────────────────────────────────────┐
       │  SQLite entity_mentions table          │
       │  (entity, file, count, last_seen)      │
       │  derived lazily from frontmatter tags  │
       │  NO first-class knowledge graph        │
       └────────────────────────────────────────┘

================================================================
CONCRETE NEXT IMPLEMENTATIONS (ranked impact-to-effort)
================================================================

[BRAIN-A] BM25 over memory bodies via SQLite FTS5 + RRF fusion
  - Effort: ~3 hours
  - Impact: HIGH — single biggest retrieval-quality win
  - Files to add/touch:
      Eidos/Memory/MemoryFTSIndex.swift (new) — FTS5 wrapper
      Eidos/Memory/MemoryRecallService.swift — add hybridRecall()
        that fuses VectorStore.topK + FTS5 results via RRF
      Eidos/RAG/RAGPipeline.swift::chatLite — call hybridRecall

[BRAIN-B] Karpathy ingest/query/lint operation triad
  - Effort: ~2-3 hours
  - Impact: MEDIUM — quality + maintainability
  - Files:
      Eidos/Memory/MemoryLintEngine.swift (new) — periodic
        consistency-check pass (dangling tags, duplicate IDs,
        empty bodies, broken backlinks)
      NudgeBackgroundTask.swift — already has BG plumbing;
        extend to schedule lint passes
      DiagnosticsView — surface lint report alongside decay

[BRAIN-C] Entity-mention index (frontmatter tags + SQLite)
  - Effort: ~3 hours
  - Impact: HIGH — unlocks "what do I know about Anna"
  - Files:
      Eidos/Memory/EntityMentionStore.swift (new)
      MemoryCrystallizer — when extracting facts, also extract
        proper nouns into frontmatter `entities:` tag list
      MemoryRecallService — new memoriesMentioning(entity:) API

[BRAIN-D] EmbeddingGemma 308M opt-in pilot
  - Effort: ~4 hours (download path + flag + side-by-side eval)
  - Impact: UNKNOWN — depends on measurable quality gap vs
    NLContextualEmbedding which Apple doesn't publish MTEB for
  - Files:
      EidosFeatureFlags.swift — new useEmbeddingGemma flag
      EmbeddingService.swift — load EmbeddingGemma alongside,
        select per flag
      DiagnosticsView — add embedding-quality A/B switcher

[BRAIN-E] Karpathy raw/wiki separation
  - Effort: ~2 hours
  - Impact: MEDIUM (long-term reprocessing flexibility)
  - Files:
      Memory/raw/<conversation_id>.md — original transcript
      Memory/wiki/<tier>/<id>.md — crystallized facts (current
        location)
      MemoryCrystallizer — write to BOTH locations

================================================================
WHAT WE EXPLICITLY REJECT
================================================================

- GraphRAG: 25-30 hours of phone-grinding indexing per 500 memories
  even before query cost. No phone implementations exist for a reason.

- LightRAG: technically possible on Gemma 4 E2B; quality of entity
  extraction at 2B param scale is degraded enough that GitHub
  issue #284 in HKUDS/LightRAG is a live complaint. Not worth the
  complexity vs hybrid retrieval.

- PageIndex: assumes long structured docs (10-K filings, textbooks).
  Personal memory store is many small atomic notes. Wrong shape.

- 128K context dump (Cache-Augmented Generation): iPhone 17 Pro Max
  realistic safe ceiling is ~16-32K tokens before TPS becomes
  unbearable, well before OOM. We learned this the hard way during
  the v9-v12 chat-crash marathon.

- Cloud embeddings (text-embedding-3-large, voyage-3-large, etc.):
  contradicts the zero-egress architectural guarantee. Off the table.

- First-class knowledge graph (Neo4j, sqlite + edges-as-rows):
  break-even point where graphs pay off is ~10K entities AND
  multi-hop relational queries. Eidos won't have either for years,
  if ever.

================================================================
OPEN QUESTIONS (for follow-up research, not blocking)
================================================================

- What's the actual retrieval-quality delta between
  NLContextualEmbedding and EmbeddingGemma 308M on Eidos's
  domain (personal facts, conversation snippets)? Apple doesn't
  publish MTEB for NLContextualEmbedding so this requires a
  small in-house eval before BRAIN-D is justified.

- At what user-memory-count does retrieval latency become
  user-visible on iPhone 17 Pro Max? Hybrid (BM25 + cosine) at
  ~10K memories should still be sub-second on iOS, but we
  haven't measured.

- Does Apple Foundation Models (iOS 26) include a usable on-device
  embedding API beyond NLContextualEmbedding? Documentation is
  sparse; worth a check after iOS 26.4.

================================================================
SOURCES
================================================================

(All accessed 2026-04-27 via the research agent dispatch.)

- Microsoft GraphRAG: https://github.com/microsoft/graphrag
- LazyGraphRAG: https://www.microsoft.com/en-us/research/blog/lazygraphrag-setting-a-new-standard-for-quality-and-cost/
- LightRAG paper: https://arxiv.org/html/2410.05779v1
- LightRAG repo: https://github.com/HKUDS/LightRAG
- LightRAG quality issue on small models: https://github.com/HKUDS/LightRAG/issues/284
- PageIndex: https://github.com/VectifyAI/PageIndex
- "Don't Do RAG" (CAG): https://arxiv.org/html/2412.15605v1
- MobileRAG (Samsung): https://medium.com/@rushabh22runwal/mobilerag-how-on-device-rag-finally-becomes-fast-light-and-battery-friendly-676e197a8966
- iPhone 17 Pro MLX benchmarks: https://rickytakkar.com/blog_russet_mlx_benchmark.html
- sqlite-vec hybrid search: https://alexgarcia.xyz/blog/2024/sqlite-vec-hybrid-search/index.html
- OpenSearch RRF: https://opensearch.org/blog/introducing-reciprocal-rank-fusion-hybrid-search/
- Karpathy LLM Wiki gist: https://gist.github.com/karpathy/442a6bf555914893e9891c11519de94f
- VentureBeat on Karpathy's wiki: https://venturebeat.com/data/karpathy-shares-llm-knowledge-base-architecture-that-bypasses-rag-with-an
- EmbeddingGemma announcement: https://developers.googleblog.com/en/introducing-embeddinggemma/
- EmbeddingGemma paper: https://arxiv.org/pdf/2509.20354
- static-retrieval-mrl-en-v1: https://huggingface.co/sentence-transformers/static-retrieval-mrl-en-v1
- Apple NLContextualEmbedding docs: https://developer.apple.com/documentation/naturallanguage/nlcontextualembedding
