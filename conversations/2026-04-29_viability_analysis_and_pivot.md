# 2026-04-29 — Viability analysis, SKG novelty critique, and pivot proposal

**Audience**: cofounder. **Read time**: ~10 minutes. **Status**: decision document, not yet locked into `masterplan.md`.

---

## TL;DR

1. **The SKG (Self-Knowledge Graph) is not novel.** Each of its four claimed pillars (on-device, zero-corpus cold start, decay-managed, user-centric topology) has prior art shipping today. mem0g, YourMemory, Karpathy's LLM Wiki, Apple Personal Context, PersonalAI (arxiv 2506.17001), FadeMem, and PersonaAgent collectively cover the design space. SKG is competent engineering, not a research contribution.
2. **The current Eidos pitch ("private on-device AI assistant for everyone, $2.99 skill packs") is unlikely to be commercially viable.** AI-app annual retention is 21.1%, monthly is 6.1% (RevenueCat 2026). Privacy preference does not convert to purchase at scale (FTC PrivacyCon, replicated). Apple ships Phase 2 Personal Context in iOS 27 (September 2026) for free. Hardware floor (iPhone 15 Pro+) caps TAM at ~30% of installed base.
3. **The technical stack we have built is the exact stack a regulated-vertical product needs.** Gemma 4 E2B + MLX + EgressGuard + persona system + markdown memory + 23 App Intents = HIPAA-safe AI for solo therapists.
4. **Recommended pivot: Eidos for Clinicians.** HIPAA-safe AI for licensed mental-health practitioners. SOAP/DAP note drafting, treatment-plan support, session prep, voice-memo → structured note pipeline. $40-80/month per seat. Same engine, different audience, 10x the price, mandatory privacy (not preferential).
5. **What to do this week**: validate demand on r/therapists; do not start SKG-1; refocus Phase 9 on a single Clinician persona; freeze the consumer pitch pending validation.

---

## 1. SKG novelty critique — synthesized

The SKG architecture (ten fixed top-level categories + 3-tier classifier + per-category Markdown + lazy SQLite `entity_mentions` index) was framed in [`conversations/2026-04-27_phase82_and_skg.md`](2026-04-27_phase82_and_skg.md) as "genuinely novel — no shipping product hits all four [pillars]."

The four-pillar combination claim does not survive an hour of literature search.

| Pillar | Prior art | Strength of novelty |
|---|---|---|
| On-device | Apple Personal Context (iOS 26.4 / 27), Apple Foundation Models, YourMemory (DuckDB local), Letta-local, Obsidian + local LLMs, Rewind, Private LLM | None |
| Zero-corpus cold start | Default behavior of mem0, Letta/MemGPT, YourMemory, FadeMem, SecondBrain.io | None |
| Decay-managed | YourMemory (Ebbinghaus, +16pp recall vs Mem0 on LoCoMo), FadeMem (LML/SML), ACT-R-inspired LLM agents (HAI 2026), mem0 importance-weighting | None |
| User-centric star topology | PersonalAI (arxiv 2506.17001), PersonaAgent w/ GraphRAG (2511.17467), Apple Personal Context, mem0g entity graph, Letta archival blocks | Marginal — it is a *simplification* of existing personal KGs, not an extension |
| Combination of all four | YourMemory hits 3-4; mem0g hits 3 | Disputed |

**SKG's actual contribution** (when honestly framed): a constrained-device instantiation of the LLM-Wiki + mem0g lineage, with a star-schema topology and a tiered classifier, packaged in Swift for Gemma E2B on iPhone. This is a workshop paper, not a NeurIPS submission.

**Practical implications**:
- Drop "genuinely novel" from any external-facing copy. It will not survive due diligence.
- Reframe SKG as "engineering applied to constraints," not as architectural innovation.
- Build SKG only behind a measurable retrieval-quality gate (a 50-prompt eval set scored against the existing per-tier MD baseline). Without that gate, "SKG is better" is unfalsifiable.
- Consider porting YourMemory (MIT, Ebbinghaus decay, beats mem0 on LoCoMo by 16pp) to Swift instead of building SKG from scratch. The build-vs-buy analysis was not done.

Full critique with caveats (architectural, time, hardware, security, strategic) and prior-art citations preserved in earlier session notes.

---

## 2. Apple competitive landscape — current state

| Phase | Ships | What's actually live |
|---|---|---|
| Siri 2.0 Phase 1 — **already live** | iOS 26.4 (Spring 2026) | Gemini-powered Siri with on-screen awareness + basic context awareness |
| Siri 2.0 Phase 2 — not yet | iOS 27, September 2026 | Full Personal Context: emails, messages, files, photos build a personal knowledge graph |
| Reveal | WWDC 2026, June 8 | Keynote reportedly Siri-overhaul-focused; Phase 2 details expected |

**The pivotal datum**: Siri is **Gemini-powered**, confirmed by Apple in January 2026. This means Apple has structurally given up the pure on-device privacy story for the Siri product. AppleInsider editorial: *"Don't give Gemini your personal data, wait for Apple Intelligence-powered Siri."*

This is a marketing gift to any competitor with a credible *zero-egress* claim — but only a marketing gift. It does not solve distribution, retention, or willingness-to-pay.

---

## 3. Bull vs Bear — the four critical questions

Two parallel agents researched the consumer pitch independently. Sources tracked back to Reddit, Product Hunt, RevenueCat, TechCrunch, FTC PrivacyCon, and the AI Graveyard.

| Q | Bull | Bear | Honest read |
|---|---|---|---|
| **Viable?** | Privacy market is real: Proton $500M ARR, Signal 70-100M MAU, ATT opt-out 65%, r/LocalLLaMA 266K. 0.005% of 1.56B iPhones = $2.3M ARR. | Pre-2020 apps capture 69% of subscription revenue; 2025+ apps capture 3%. AI Graveyard: 738 dead projects. Rewind ($350M valuation), Humane ($240M), Rabbit, Tome, OpenAI Sora — all dead or pivoted. | **Bear wins on app-economy data; bull wins on niche-survivor data.** Indie privacy apps sustain, but it's a 10-year journey, not a 2-year exit. |
| **Why succeed/fail?** | Apple's Gemini deal cracked the privacy narrative. 23 App Intents shipped; Shortcuts is organic distribution. | Apple ships the same product, free, on every iPhone. iPhone 15 Pro+ floor caps TAM at ~30%. Local LLM is 21-37x more battery (Greenspector). Apple Foundation Models in 3 lines of Swift. | **Bear wins on gravity; bull wins on positioning gift.** Solo dev cannot outshout Apple. |
| **Innovative?** | Slopes won an Apple Design Award without academic novelty. Obsidian ($5-25M ARR) proved markdown ships. Innovation = bundle + framing + execution. | "Building Offline RAG on iOS with Gemma" is a Medium tutorial. SwiftLM, LocalLLMClient, LLMFarm, Locally AI, Private LLM, Screenpipe, AnyLanguageModel — open-source clones already exist. | **Both right.** Eidos is product-innovative, not technically novel. The bundle is real but copyable. Moat is execution + audience trust, not architecture. |
| **Will they pay?** | Day One ~$4.8M ARR. Reflection.app $69/yr. Saner.AI $8-20/mo despite poor execution. RevenueCat: AI apps monetize at 2x pre-AI ARPU. | AI annual retention **21.1%**; monthly **6.1%**. ~80% of yearly subs churn before year-end. FTC PrivacyCon: paying for apps doesn't actually buy privacy; stated preference does not translate to purchase. Bango: $60/mo on 4 AI subs already, fatigue setting in. DuckDuckGo Privacy Pro launched 2024, analysts question conversion. | **Bear wins decisively.** Privacy-as-a-feature does not monetize; only privacy-as-a-compliance-requirement does. |

### The single most important number

**AI app monthly retention: 6.1% (RevenueCat 2026).** 94 of every 100 paying users gone in 12 months. This is a structural problem with the AI consumer category, not with Eidos specifically. No engineering quality fixes it. CAC has to be near-zero for the LTV math to work.

### The single most important finding

**Privacy preference does not convert to purchase.** FTC PrivacyCon (Han et al.) compared free and paid versions of identical apps; paying did not actually buy privacy, and the privacy claim did not drive enough purchases to matter. Replicated across multiple studies for ~6 years. Signal monetizes through donations from a 70-100M MAU base; Proton monetizes by pairing privacy with mission-critical email; Obsidian monetizes by pairing privacy with knowledge-of-record. None of them sells "privacy + AI assistance" — that bundle has not yet been shown to convert.

---

## 4. Verdict

**Eidos as currently scoped is not a viable venture and is borderline as a sustainable indie business.**

The bull case is not wrong about the audience existing. It is wrong about the audience paying for *AI assistance* specifically. The privacy audience already gets along without an AI assistant. They will not pay $4.99/mo for one when ChatGPT does more for $20 and Siri 2.0 does enough for free.

The central insight: **privacy converts only when paired with a high-stakes, recurring, mission-critical use case where cloud AI is not legally usable.** Compliance > preference. Liability > vibes.

---

## 5. Niche pivot — ranked by viability

All viable pivots share three properties:
- **Compliance or adversarial threat model** — user *cannot* use cloud AI, not just prefers not to.
- **10x higher willingness to pay** — $20-80/month, not $4.99.
- **Defined acquisition channel** — professional associations, vertical communities, advocacy orgs.

| # | Niche | Why it works | Price | Channel |
|---|---|---|---|---|
| **1** | **Solo HIPAA-bound therapists** | Cannot put client notes in ChatGPT. ~700K licensed therapists in US. r/therapists 200K+. APA/NASW reachable. | $40-80/mo | Therapist Reddit, APA conferences, Psychotherapy.net, podcast sponsorships |
| **2** | Solo lawyers / paralegals | Attorney-client privilege legally compromised by cloud AI. ABA has explicitly warned. | $50-150/mo | State bar journals, ABA TECHSHOW |
| **3** | Domestic-abuse / stalking-aware users | Adversarial threat model. Mission-critical. Plausible deniability via biometric lock + snapshot overlay (already shipped Phase 8.2). | Free via NGO sponsorship; $5-10/mo otherwise | NNEDV Safety Net, women's shelters |
| **4** | Investigative journalists | Cannot risk cloud logging sources. Already use Signal/SecureDrop. | $30-60/mo, often org-paid | Freedom of the Press Foundation, IRE, foundation grants |
| **5** | HNW / executives / political / celebrity | Bodyguards-of-information market. Personal-assistant-class needs but cloud-incompatible. | $200-500/mo white-glove | Family-office network, exec EAs |
| **6** | Field workers / aviators / mariners / military | Genuine offline operational need. | $20-50/mo, org-paid | Aviation/marine pro channels, MWR, expedition outfitters |

---

## 6. Recommended pivot path: therapist-first

### Why therapist-first wins

- **Mandatory privacy**: HIPAA + state licensing + ethics codes. Cloud AI use is a documented liability — not preference, *liability*.
- **Existing willingness to pay**: TherapyNotes / SimplePractice / TheraNest already charge $40-80/month. We slot into that tier.
- **Reachable audience**: ~700K US-licensed therapists; r/therapists 200K+; APA conferences; Psychotherapy.net podcast network.
- **Single corpus does most of the work**: DSM-5-TR, ICD-10 mental-health codes, public-domain CBT/DBT/ACT materials, session-note templates. None require cloud LLM.
- **Defensible**: Apple will not ship a HIPAA-certified therapist AI in iOS 27. Cloud AI literally cannot be used here. Regulatory moat Apple cannot trespass into cheaply.
- **Pricing math works**: 1,000 therapists x $40/mo x 12 = $480K ARR. 5,000 = $2.4M ARR. Achievable single-founder + cofounder.

### What we keep (architecture is 80% there)

- Gemma 4 E2B + MLX Swift engine
- `EgressGuard` (now a *compliance feature*, not a vibes feature)
- Persona system → single Clinician persona for v1
- Markdown memory → per-client encrypted clinical-note vaults
- App Intents → "log session," "draft SOAP," "review treatment plan"
- Privacy snapshot overlay + biometric lock (Phase 8.2) → now compliance-load-bearing
- `SpeechTranscriber` + share extension → session voice → transcript pipeline

### What we de-prioritize

- General-purpose chat (it is not the wedge)
- $2.99 skill packs (replaced by single $40-80/mo SaaS seat)
- Phase 9 multi-persona dispatch (collapse to single Clinician for v1; revive multi-persona post-PMF)
- Full SKG (still useful, eval-gated, lower priority)

### What we add

- DSM-5-TR / ICD-10 mental-health corpus bundling
- SOAP / DAP / BIRP note templates
- Voice memo → structured-note pipeline (extend `SpeechTranscriber`)
- HIPAA Business Associate Agreement template (for org sales)
- Per-client encrypted vaults with audit log (every fact recall logged so the clinician can show their work in a deposition)
- Targeted onboarding: clinician profile, license number, jurisdiction, scope of practice

---

## 7. Decisions needed (this week)

1. **Validate demand before committing.** Post in r/therapists: *"Solo therapists — would you pay $40/mo for an AI that helps with SOAP notes if it ran 100% on your iPhone with no cloud?"* Track upvotes, comments, DMs. Reach out to 10 clinicians directly. Demand them to break v0.
2. **Freeze the consumer pitch** until validation lands. Do not write more masterplan copy around the consumer story.
3. **Do not start SKG-1.** Reasoning preserved in this doc. SKG-lite (per-category index files only) is acceptable if measured against a benchmark; full SKG is parked.
4. **Confirm v12 on-device validation** with the existing tester before any architectural change. The `[BLOCKER]` in `developer_log.txt` SECTION 4 still applies.
5. **Decide on the therapist pivot** by 2026-05-15. If validation is positive, lock the pivot in `masterplan.md` and rename the v1 product surface to "Eidos for Clinicians."
6. **Watch WWDC 2026 (June 8).** Phase 2 Personal Context details drop. Adjust positioning if Apple announces something we did not expect.
7. **Do a build-vs-buy review on YourMemory** before committing 24h to SKG. MIT-licensed, on-device, +16pp over mem0 on LoCoMo. Porting to Swift may deliver the memory upgrade for less effort than SKG.

---

## 8. Open questions for cofounder

- Are we comfortable with the vertical pivot, or do we want to attempt the consumer pitch first as a learning exercise?
- Budget for a HIPAA audit (~$10-30K). Do we have the runway, or do we need a clinician design partner who can sponsor it through their practice?
- Compliance certification: SOC 2 Type II? Or stay below the threshold by selling to solo practitioners who are themselves the covered entity?
- Founding-team cap: solo dev for 6 product lines is documented burnout territory. Do we add a clinician advisor / co-founder to reach the audience credibly?
- If validation kills the therapist pivot, which #2-#6 pivot is the fallback?

---

## 9. Sources (load-bearing only)

**SKG novelty**:
- [Mem0 / Mem0g (arXiv 2504.19413)](https://arxiv.org/abs/2504.19413)
- [YourMemory — Ebbinghaus decay, +16pp over Mem0 on LoCoMo](https://github.com/sachitrafa/YourMemory)
- [PersonalAI (arXiv 2506.17001)](https://arxiv.org/abs/2506.17001)
- [Karpathy LLM Wiki tweet](https://x.com/karpathy/status/2040572272944324650)
- [Apple Personal Context — Siri's on-device knowledge graph](https://www.macrumors.com/2025/09/03/llm-siri-with-search-early-2026/)

**Apple competitive state**:
- [MacRumors — Google confirms Gemini-Powered Siri](https://www.macrumors.com/2026/04/22/google-gemini-powered-siri-2026/)
- [AppleInsider — Don't give Gemini your personal data](https://appleinsider.com/articles/26/01/14/dont-give-gemini-your-personal-data-wait-for-apple-intelligence-powered-siri)
- [AppleInsider — WWDC 2026 focus is iOS 27 Siri overhaul](https://appleinsider.com/articles/26/04/19/wwdc-2026s-focus-will-be-on-ios-27s-siri-overhaul)

**Viability data**:
- [RevenueCat — State of Subscription Apps 2026](https://www.revenuecat.com/state-of-subscription-apps/)
- [TechCrunch — AI apps struggle with retention](https://techcrunch.com/2026/03/10/ai-powered-apps-struggle-with-long-term-retention-new-report-shows/)
- [FTC PrivacyCon — paying for apps doesn't buy privacy (Han et al.)](https://www.ftc.gov/system/files/documents/public_events/1415032/privacycon2019_han_comparing_privacy_behaviors_of_free_vs_paid_apps.pdf)
- [Greenspector — local AI 29x more energy](https://greenspector.com/en/artificial-intelligence-smartphone-autonomy/)
- [Callstack — Local LLMs on Mobile are a Gimmick](https://www.callstack.com/blog/local-llms-on-mobile-are-a-gimmick)
- [TechCrunch — Rewind pivots away from local-first](https://techcrunch.com/2024/04/17/a16z-backed-rewind-pivots-to-build-ai-powered-pendant-to-record-your-conversations/)
- [TechCrunch — Humane AI Pin dead, HP buys for $116M](https://techcrunch.com/2025/02/18/humanes-ai-pin-is-dead-as-hp-buys-startups-assets-for-116m/)
- [TechCrunch — OpenAI shuts down Sora](https://techcrunch.com/2026/03/24/openais-sora-was-the-creepiest-app-on-your-phone-now-its-shutting-down/)

**Indie precedent (validates niche path, not consumer pitch)**:
- [Slopes — solo iOS dev, $1M ARR, 9 years](https://www.revenuecat.com/blog/growth/slopes-from-indie-side-hustle-to-1m-in-arr-and-an-apple-design-award/)
- [Obsidian usage / revenue](https://fueler.io/blog/obsidian-usage-revenue-valuation-growth-statistics)
- [Proton story — $500M ARR](https://stealthcloud.ai/intelligence/proton-story-billion-dollar-privacy/)

---

## 10. Next file to update

If the cofounder agrees with the pivot direction, the next change is to [`masterplan.md`](../masterplan.md):

- Update "Vision" — replace "AI that does what Siri can't" with the clinician framing.
- Add a new "Phase 8.5 — Vertical pivot to clinician market" between Phase 8.3 (SKG, deferred) and Phase 9 (skills/personas, scope-collapsed).
- Move Phase 9 explicitly to "single Clinician persona; multi-persona deferred to post-PMF."
- Add a "Current State" row marking SKG as deferred pending eval-set construction.
- Note WWDC 2026 (June 8) as a calibration checkpoint.

End of memo.
