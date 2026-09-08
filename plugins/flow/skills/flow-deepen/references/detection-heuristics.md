---
name: detection-heuristics
description: The full deepening-opportunity detection catalogue for flow-deepen — the five smell families with greppable signals and before→after deepening moves, the AI "improve architecture" guardrails (with WHY each makes things worse), the AFK/HITL tag decision table, the three-part behavior-preserving acceptance-criteria pattern, the deepening task template, and a worked example. Load this in full before Phase 2.
---

# Deepening detection heuristics

Run the grep signals — do not eyeball. Thresholds are starting heuristics from Ousterhout's *A Philosophy of Software Design* operationalized for tooling; they are NOT bright lines (Ousterhout gives the rectangle metaphor, not numbers). Calibrate per codebase.

## Family 1 — Shallow modules (interface cost ≈ implementation cost)

| Signal | Detection | Deepening move (before → after) |
|---|---|---|
| **Ratio heuristic** | `(total LOC ÷ public method count) < 20` → likely shallow. Count: `grep -c 'public ' src/Foo.ts` vs `wc -l`. | Consolidate one-liner wrappers into fewer, deeper methods. |
| **Classitis chain** | One logical op needs 3+ classes composed in a required order. | `new ObjectInputStream(new BufferedInputStream(new FileInputStream(path)))` → `Deserializer.fromFile(path)` — one entry point, buffering defaulted, composition hidden. |
| **Anemic class** | `grep -E 'public (get\|set)[A-Z]'` > 80% of public methods, no action verbs (validate/compute/render/merge). | `address.getZip().startsWith('9')` → `address.isWestCoast()` — pull the external computation inside. |
| **Shallow class size** | total LOC ≤ (public method count × 3) → ~3-line methods, all wrappers. | Collapse into the caller or give real behavior. |

## Family 2 — Interface leakage (a decision reflected in >1 place)

| Signal | Detection | Deepening move |
|---|---|---|
| **Comment bleed** | Interface docstring contains `internally`, `buffer`, `cache`, `thread`, `retry`, `loop`, `flush`, `lock`, `pool`. | `/** Reads user data. Internally uses a 4KB buffer, retries 3×. */` → `/** Returns the user for id, or null. */` — hide the implementation words or raise the abstraction. |
| **Config explosion** | > 3 numeric/duration constructor params (`*Ms`, `*Seconds`, `*Size`, `int`, `boolean`). | `new HttpClient(host, port, connectTimeoutMs, readTimeoutMs, maxRetries, retryDelayMs, maxConns)` → `new HttpClient(host)` with sane internal defaults + optional options object. Each tuning param is a decision pushed to every caller. |
| **Temporal type leak** | Same internal type imported by two modules not in a shared-contract layer: `grep -rn 'RawChunk\|CHUNK_SIZE\|chunked' --include='*.ts'` in both `transport/` and `serializer/`. | Move the shared representation behind one owning module; the wire-format decision should live in one place. |

## Family 3 — Poor locality (knowledge scattered by execution order)

| Signal | Detection | Deepening move |
|---|---|---|
| **Temporal decomposition** | `grep -rE 'class .*(Reader\|Parser\|Validator\|Transformer\|Writer\|Applier\|Handler\|Step\|Stage\|Processor\|Runner)'` AND the cluster shares imports of one domain type. | `ConfigReader` + `ConfigValidator` + `ConfigApplier` (all know the format) → `Config.load(path)` — one class owns the format, validates on load. |
| **Pass-through variable** | A param in a signature, never read in the body, only forwarded to a nested call across 3+ frames (e.g. `requestId` threaded for logging). | Promote to a shared `RequestContext` passed once at the boundary (Ousterhout lists context/thread-local/global — all have trade-offs; do not harden to one). |

## Family 4 — Layer / abstraction mismatch (a layer that adds no vocabulary)

| Signal | Detection | Deepening move |
|---|---|---|
| **Pass-through method** | Body is a single forward to a same-named subordinate. `grep -A3 'def ' f.py \| grep -B1 'return self\.'`. > 2 per class is a red flag. | `UserService.find(id){return repo.find(id)}` → delete the layer OR give it real behavior (validation, caching, events). |
| **Same-named chain** | One verb identical across Controller→Service→Repository→db. | `save→save→save→save` → keep only layers that introduce a NEW concept (e.g. Service introduces "publish user-saved event"); delete the rest. |
| **Decorator trap** | Class implements interface I, holds a field of type I, method count == I's. `Logging*`/`Caching*`/`Retrying*` wrappers. | `LoggingX`+`CachingX`+`RetryingX` → `X(cached=true, retries=3, logger=…)` — compose behaviors inside one class. |
| **Feature-named API** | `grep -rE 'ForDashboard\|OnSignup\|ForSettings\|ForProfile'`. | `fetchUserDataForDashboard(id)` → `fetchUser(id)` — remove the caller's context from the name; the method needs only domain knowledge. |
| **Boolean-flag method** | `processPayment(amount, isRetry, skipFraudCheck, useLegacyPath)`. | Split into named methods or internalize the decision with a default. Each flag is a special-purpose escape hatch pushed up. |
| **Conjoined methods** | Two calls always appear together with no logic between (`begin/end`, `open/close`), or a docstring says "must be called before/after X". | Merge, or return a `Session` from `begin()` that exposes `send()` and auto-closes. |
| **Exception taxonomy explosion** | `grep -rE 'class [A-Z][a-zA-Z]*(Exception\|Error) extends'` > 5 in one module where callers catch the base anyway. | Catch implementation exceptions at the boundary, re-throw one `StorageException` with the cause. Before adding a try/catch, ask if the error can be defined out of existence (clamp/widen the contract). |

## Family 5 — Tests coupled to internals (break on internal restructure)

| Signal | Detection | Deepening move |
|---|---|---|
| **Structural mirroring** | One test class per production class; tests break on behavior-preserving restructure. | Rewrite tests against the public seam's observable behavior; internal helpers then need no new test classes. |
| **Over-mocking** | `find . -name '*.test.ts' \| xargs grep -l 'mock\|jest.fn\|vi.fn' \| wc -l` > 60% of test files; or tests import `__internal`/`internals/` or touch `module._private`. | Characterize at the public seam; mock only true external boundaries (network, clock, fs). |

---

## Guardrails — how an "improve architecture" agent makes things WORSE

Apply as a hard filter in Phase 2. Each is a documented way AI refactors destroy value — discard candidates that hit any of them.

- **Frozen-debt treatment** (Tornhill). Refactoring a low-churn stable file. WHY it's worse: complexity is only a cost where change is frequent; touching frozen code spends the team's risk budget for zero benefit — negative ROI. Filter: `git log --follow --oneline -- <file> | wc -l`; churn < 2 in 6 months → drop.
- **Rule-of-Three violation** (Metz). Extracting a shared abstraction from two instances. WHY: "duplication is far cheaper than the wrong abstraction" — the third consumer reveals the real shape; extract early and you get a leaky param or a rewrite, costlier than the duplication. Filter: < 3 instances → wait.
- **Over-abstraction / premature seam** (DHH test-induced design damage; Fowler). A single-implementation interface, no test fake, no runtime swap. WHY: LLMs over-generalize the enterprise "interface + Impl" pattern; the result is a shallow module where interface complexity == implementation complexity. Filter: `grep -rE 'interface.*\|.*Impl'` — one impl, never mocked → drop.
- **Speculative generality** (Fowler/YAGNI). Plugin hooks, strategy registries, factories "for the future." WHY: the more abstract a design looks, the higher its surface-quality score to a model — but the plugin system has no plugins and every future reader must learn the extension mechanism. Filter: no current consumer → drop.
- **Rewrite disguised as refactor** (Fowler). Wholesale replacement under a "refactor" label. WHY: a model has no hard line between restructure and rewrite; the output that looks most "improved" is often a rewrite that diverges on edge cases and destroys git blame. Filter: a slice whose blast radius is > ~5 files or rewrites a working module → it is not a deepening.
- **Refactoring without tests** (Feathers). Restructuring code with no coverage or with structural-mirror tests. WHY: a green type-check is not behavioral preservation — types describe shape, not value; structural tests pass because file layout is preserved, not because behavior is. Filter: no seam to characterize at → characterize first or drop.
- **Test deletion to go green** (Beck, observed in agents). An agent deletes a failing test to get a green bar. WHY: the model has a green-bar reward signal and deletion is the shortest path. Guard: the characterization-test commit gate makes test count monotonic — a slice that reduces the suite is rejected.
- **Scope creep**. Expanding from one module to adjacent subsystems. WHY: models optimize for thoroughness and see "related improvements" as helpful. Filter: keep each slice to the modules named in `## What ships`.

---

## AFK vs HITL — tag decision

A deepening is behavior-preserving and test-gated, so the **default is AFK**. Escalate to **HITL** only on:

1. **Interface-shape decision** — the seam hides a real fork (single method with options object vs two methods; which ownership boundary). Name the options.
2. **External-contract change** — any caller *outside the module boundary* must change an import or call site (public API, DB schema, serialization format).
3. **Public-symbol deletion** — removing a symbol other teams consume.
4. **Bug-or-feature surprise** — the characterization test reveals current behavior that may be a bug; a human decides preserve-vs-fix (fix is a separate intentional commit). Tag these `AFK (pending characterization test — may escalate to HITL)`.

A HITL rationale MUST name the decision: *"Needs a human for: interface shape — Option A (one method + options object) vs Option B (two methods)."* Lead the user with a recommended option and the why.

---

## Acceptance-criteria pattern (mandatory three parts, in order)

Every deepening slice's `## Acceptance criteria` has exactly these three, and **no AC may require a NEW test case to pass** (that is feature work — split it):

1. **Characterization test first** — `Given the module at its current public interface, When the full suite runs, Then all tests stay green, AND a characterization test pinning current observable output is committed BEFORE the structural change.`
2. **Seam observability** — `Given the deepened module, When the seam is exercised through its public interface, Then the output is byte-for-byte identical to the pre-refactor output for every input in the characterization fixture.`
3. **Measurable interface reduction** — `Given a caller of the new interface, When it uses the deepened method/class, Then it requires [N fewer parameters / N fewer constructor calls / N fewer imports] than before.` This is what makes it a deepening, not a rename — it must be measurable at the call site.

---

## Deepening task template

A deepening is a `TASKS.md` line in the K-B grammar, nothing else. Append one `## Phase N — Deepening`
section to the spec's `TASKS.md`, then one line per deepening under it:

```markdown
## Phase N — Deepening
Goal: <the anti-pattern family + the detection signal that found it + the before→after at the call site>.
Independent test: `<the suite>` — green byte-for-byte with no new test case added.
- [ ] T014 Caller deserializes a file with one factory call, not 3 — files: src/io/deserializer.ts, tests/io/deserializer.char.test.ts — verify: `npm test -- tests/io/deserializer.char.test.ts`
- [ ] T015 UserStore returns StoreError, callers drop the db import — files: src/store/user.ts, tests/store/user.char.test.ts — verify: `npm test -- tests/store/user.char.test.ts` — after: T014
- [ ] CHK016 human-decide — client shape: one method + options object (recommended) vs two methods — verify: human: user picks a shape
```

Line rules that `flow lint` enforces, so get them right in the draft:

- The **description** states call-site-observable behavior ("caller creates a user with one method call
  instead of three"), never a layer ("extract the repository interface") — that is horizontal.
- **`files:`** is a comma-separated list with no globs, and it must include the characterization test file.
  Two `[P]` tasks in the same wave whose `files:` intersect are an ERROR.
- **`verify:`** is the characterization test's own command. A `verify:` that requires a NEW behavioral
  test case to pass is feature work, not a deepening.
- **`after:`** serializes same-module tasks so the earlier one pins the seam. Only tag `[P]` when the
  `files:` are genuinely disjoint.
- **HITL** deepenings are `CHK###` lines with `verify: human: <observable>`, placed before the `T###`
  that depends on the decision. Everything else is a plain `T###`.
- The three-part behavior-preserving pattern (characterization-test-first → byte-for-byte seam
  observability → measurable interface reduction) lives in the phase `Goal:` and the descriptions.
  Anything that does not fit on the line goes in `NOTES.md`, never in a parallel file.

---

## Worked example

**Detected**: `UserStore.ts` (churn 9 in 6 months — high) has `find/save/delete/list`, each a one-line forward to `db.*` of the same name. Signal: same-named method chain + ratio 14 LOC ÷ 4 methods. The merged feature work added three call sites that all go `new UserStore(db).find()` then immediately `db`-shaped error handling.

**T014** (AFK → plain task): *"Caller fetches a user with one call and store-level errors, not raw db errors."* Characterization test pins current `find()` output and the current error shape first → byte-for-byte preserved → caller drops the db import and the per-call error branch (interface reduction). Deepening: `UserStore` aggregates db exceptions into one `StoreError` at its boundary and the pass-through methods gain real behavior (or collapse). No `after:`.

**T015** (AFK, `— after: T014`): *"Caller lists users without passing a page-size tuning param."* Config-explosion signal: `list(pageSize, prefetch, cacheTtlMs)`. Same module as T014 → serialized so T014's characterization test pins the seam first, and neither line may carry `[P]`.

Both are behavior-preserving, both characterization-test-gated, and both land as lines in `.specs/<NNN>/TASKS.md` for /flow:next to build unchanged.

