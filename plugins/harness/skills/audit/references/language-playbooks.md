---
name: audit-language-playbooks
description: Per-language expert anti-pattern catalogs (Python, TypeScript, Rust, Go) for the /audit skill's correctness and performance agents. Condensed from 2024-2026 practitioner consensus. Load by correctness/performance agents at Phase 1 based on detected stack.
---

# Language Playbooks — Anti-Patterns Agents Actually Hunt For

**This reference is loaded conditionally by the correctness and performance audit agents based on Phase 0 recon stack detection. Each section contains the non-obvious anti-patterns that separate expert review from linter output.**

The `what to check` lists are what the agent grep/AST-searches for. The `why` columns are the `failure_scenario` the agent cites. The `tooling` commands are run before or alongside the grep.

---

## Python (3.11-3.13)

### Modern Python Anti-Patterns (Non-Obvious)

**`asyncio.gather` considered legacy for error-sensitive code**

```python
# LEGACY — first exception cancels gather but orphans other running tasks
results = await asyncio.gather(a(), b(), c())

# EXPERT 3.11+ — all tasks cancelled on first failure, structured ExceptionGroup
async with asyncio.TaskGroup() as tg:
    task_a = tg.create_task(a())
    task_b = tg.create_task(b())
```

Failure scenario: `gather(a(), b(), c())` where `a()` raises at t=1s. `b()` and `c()` continue running until completion (orphaned tasks), then their return values are discarded. If `b()` was writing to a DB, the write completes but the caller never sees it. Resource leak + correctness bug.

**Flag**: `asyncio.gather(` in production code. Suggest `TaskGroup` for 3.11+. `return_exceptions=True` is a subtler smell — it swallows `BaseException` subclasses including `KeyboardInterrupt` and `SystemExit`.

---

**PEP 695 `type` statement runtime trap**

```python
type Url = str                          # creates TypeAliasType, NOT a type

isinstance(x, Url)                       # TypeError at runtime
issubclass(Url, str)                     # TypeError at runtime
class Subclass(Url): ...                 # TypeError at runtime
```

`Url: TypeAlias = str` is still the bare value at runtime. `type Url = str` is a new `TypeAliasType` object — breaks `isinstance`/`issubclass`/inheritance.

**Flag**: Ruff `UP040` autofix applied to code that uses the alias in runtime isinstance/subclass/inheritance. Grep for `isinstance(.*Url)` before allowing UP040.

---

**`@lru_cache` / `@cache` on instance methods**

Mechanism: `lru_cache` includes `self` in the key. The module-level cache holds a strong reference to the instance, preventing GC for the process lifetime.

```python
class MyService:
    @functools.lru_cache(maxsize=128)   # BAD — leaks instances
    def expensive(self, key: str) -> Result: ...
```

Failure scenario: service instantiated per request. Each instance is cached indefinitely. Memory grows linearly with request count → OOM after ~10k requests.

**Fix options**: decorate bound method in `__init__`, move cached function out of class, use `@staticmethod` / `@classmethod`, or switch to per-instance cache. Exception: `@lru_cache` on `Enum` methods is safe (singletons).

**Flag**: Ruff `B019`.

---

**`asyncio.gather` + `return_exceptions=True` swallowing `BaseException`**

```python
results = await asyncio.gather(a(), b(), c(), return_exceptions=True)
for r in results:
    if isinstance(r, BaseException):  # must be BaseException, not Exception
        raise r
```

Failure scenario: `KeyboardInterrupt` raised in `a()` is captured as a return value, not propagated. The process hangs or behaves erratically because the signal is swallowed.

---

**Structural pattern matching capture trap**

```python
match command:
    case float:       # WRONG — binds variable named "float", matches everything
        ...
    case float():     # CORRECT — class pattern, isinstance(command, float)
        ...

COMMANDS = {"quit", "help"}
match user_input:
    case COMMANDS:    # WRONG — creates variable named COMMANDS, matches everything
        ...
    case _ if user_input in COMMANDS:   # Correct
        ...
```

Failure scenario: `case float:` at position 0 in a match block matches ANY input, making every subsequent case dead code. No runtime error, no warning.

**Flag**: `case [lowercase-name]:` where the name is a known built-in type or constant.

---

**`@dataclass` `hash=False, eq=True` contract violation**

```python
@dataclass
class Thing:
    id: int = field(hash=True, eq=True)
    data: str = field(hash=False, eq=True)  # BROKEN
```

Two objects can be equal (`==`) but have different hashes — violates Python's `a == b implies hash(a) == hash(b)` requirement. Silently corrupts dict/set behavior.

---

**f-strings in logging calls (breaks lazy evaluation)**

```python
# BAD — format string evaluated even at DEBUG level
logger.debug(f"Processing {len(expensive_computation())} items")

# GOOD — interpolation deferred until log level check
logger.debug("Processing %s items", len(expensive_computation()))
```

**Flag**: Ruff `G004`.

---

**Sync blocking in async context**

`time.sleep`, `requests.get`, stdlib `open`, any CPU-bound loop blocks the entire event loop thread. Single `time.sleep(0.1)` delays every other coroutine.

**Flag**: Ruff `ASYNC100` / `ASYNC101` / `ASYNC110`. Grep for `time\.sleep\|requests\.\|urllib` inside `async def`.

---

**pandas `.apply(axis=1)` on DataFrames**

100–700x slower than vectorized operations. The `.str.split()` accessor LOOKS vectorized but internally runs a Python function per row. For string ops, measure before assuming pandas API is fast.

---

### Python Tooling Commands

```bash
# Ruff with expert rule set
ruff check . \
  --select E,F,W,I,UP,B,SIM,TRY,RUF,C4,PTH,ANN,RET,ISC,TC,ASYNC \
  --ignore E501,ANN101,ANN102  \
  --output-format=json > .audit/ruff.json

# Rule categories:
# B   = flake8-bugbear (B019 = lru_cache on methods)
# SIM = simplification (SIM117 nested with, SIM118 dict iteration)
# TRY = exception anti-patterns
# UP  = pyupgrade (UP040 = type statement — review before autofix)
# TC  = TYPE_CHECKING import separation
# PTH = prefer pathlib
# ASYNC = async-specific lints

# Format check (non-mutating)
ruff format --check .

# Type checking — pick ONE
pyright --project . --outputjson > .audit/pyright.json   # strict inference
mypy . --strict --show-error-codes --no-error-summary > .audit/mypy.txt
# ty check . --output-format json                         # if available (Astral's new checker)

# Dead code (not in ruff)
vulture . --min-confidence 80

# Security
bandit -r . -f json -o .audit/bandit.json --skip B101

# lru_cache on methods
ruff check . --select B019

# Logging f-strings
ruff check . --select G

# Async issues
ruff check . --select ASYNC
```

---

## TypeScript (5.0-5.8+)

### TypeScript Anti-Patterns (Non-Obvious)

**`any` is viral — it poisons inference through the entire call chain**

```typescript
function parse(raw: any): any        // every downstream binding becomes any
// vs
function parse(raw: unknown): User { // caller must narrow
  if (!isUser(raw)) throw new Error("Invalid");
  return raw;
}
```

Failure scenario: `fetchUser()` returns `any`. Every destructured field, mapped array, filtered result silently loses type safety. Unlike `unknown` (demands narrowing), `any` infects without signal.

**Flag**: `@typescript-eslint/no-explicit-any` + `no-unsafe-*` rules. `tsc --noEmit 2>&1 | grep "implicitly has an 'any' type"` catches implicit any only.

---

**`interface extends` vs intersection `&` performance cliff**

```typescript
// BAD — intersection recomputed on every type check
type Props = BaseProps & { extra: string }

// GOOD — interfaces cached by name, 10x+ faster in large component trees
interface Props extends BaseProps { extra: string }
```

Failure scenario: TypeScript issue #58559 — React project with nested prop intersections saw 12-second type-check times. Converting to `interface extends` dropped to sub-second.

**Flag**: `type Props = X & Y` in React component prop declarations. Suggest `interface Props extends X` with the member added.

---

**`for-await-of` over promise array (serial execution bug)**

```typescript
// WRONG — 50 DB calls serially, O(n × latency)
for await (const id of ids) {
  results.push(await fetchUser(id))
}

// RIGHT — parallel, O(max latency)
const results = await Promise.all(ids.map(fetchUser))
```

Failure scenario: 50 user IDs, each fetch takes 100ms. Serial: 5s total. Parallel: 100ms total. This is the single most common async performance bug.

**Flag**: `for await (const x of xs)` where `xs` is an array of promises or a call producing promises.

---

**Non-null assertion `!` as permanent workaround**

Every `!` is a lie to the compiler with no runtime safety net. `?.` produces `undefined`; `!` throws a cryptic "Cannot read properties of undefined" downstream, not at the assertion site.

**Flag**: `@typescript-eslint/no-non-null-assertion` (warning).

---

**Enums and tree-shaking / `erasableSyntaxOnly` incompatibility**

```typescript
enum Color { Red, Green, Blue }
// Emits an IIFE at runtime with reverse mapping — not tree-shakeable
```

Alternatives:
```typescript
const Direction = { Up: "UP", Down: "DOWN" } as const;
type Direction = typeof Direction[keyof typeof Direction];
// Zero runtime overhead, fully tree-shakeable
```

Additional traps: `const enum` breaks `isolatedModules` consumers; numeric enums accept any number; Node.js 23.6+ native TS stripping bans enums.

**Flag**: `enum` in public API / library code. `tsc --erasableSyntaxOnly` would reject it.

---

**`noUncheckedIndexedAccess` missing from strict**

`strict: true` does NOT enable `noUncheckedIndexedAccess`. Without it, `arr[0]` has type `T`, not `T | undefined` — missing index bugs.

Other flags experts add beyond `strict`:
- `noUncheckedIndexedAccess`
- `exactOptionalPropertyTypes`
- `noImplicitOverride`
- `verbatimModuleSyntax`
- `noPropertyAccessFromIndexSignature`

**Flag**: missing these in `tsconfig.json` if the project claims strict typing.

---

**Floating promises (unhandled rejection)**

```typescript
useEffect(() => {
  fetchData().then(setData);  // floating — rejection silently swallowed
  return () => { /* ... */ };
}, []);
```

**Flag**: `@typescript-eslint/no-floating-promises`. Biome ≤2.0 does NOT have this rule — a "Biome-only" setup has a real safety gap here.

---

**ESM `.js` extension required in `.ts` source**

In Node.js ESM mode with `moduleResolution: "Node16"` or `"NodeNext"`:

```typescript
import { foo } from "./utils.js"   // correct in ESM TypeScript
import { foo } from "./utils"      // runtime error in Node ESM
```

Most common Node.js ESM migration failure.

---

### TypeScript Tooling Commands

```bash
# Type check
tsc --noEmit --diagnostics > .audit/tsc.txt

# Dead code (knip — modern, ts-prune is deprecated)
npx knip --reporter compact > .audit/knip.txt

# Circular deps
npx madge --circular --extensions ts,tsx ./src > .audit/cycles.txt

# ESLint with type-aware rules (REQUIRED for promise safety)
# eslint.config.js must use @typescript-eslint/recommended-type-checked
npx eslint --format json . > .audit/eslint.json

# Bundle analysis (find barrel file tree-shaking killers)
# Framework-specific; skip if no bundler detected

# TypeScript trace for perf hot spots
tsc --generateTrace /tmp/ts-trace
# Then open chrome://tracing on trace.json
```

---

## Rust (Edition 2024)

### Rust Anti-Patterns (Non-Obvious)

**`Box<dyn Error>` erases variant information**

```rust
// BAD — caller can't distinguish "not found" from "permission denied"
fn load() -> Result<Data, Box<dyn Error>>

// GOOD (library) — thiserror enum preserves variants
#[derive(thiserror::Error, Debug)]
enum LoadError {
    #[error("not found: {0}")]
    NotFound(String),
    #[error("permission denied")]
    PermissionDenied,
}
```

Failure scenario: caller needs to retry on "not found" but give up on "permission denied". With `Box<dyn Error>`, the only option is downcast_ref (brittle) or string matching (breaks on i18n).

Rule: `thiserror` for libraries, `anyhow` for applications. Never `Box<dyn Error>` in library public API. Never `anyhow` in library public API (forces transitive dep).

---

**`.clone()` as borrow-checker escape hatch**

A `.clone()` at a call site (not inside a data structure method) usually means a function signature accepts `T` when it should accept `&T`, or a type should be `Copy` and isn't.

Failure scenario: `String` parameter forces callers to allocate even for static literals. Accept `impl AsRef<str>` or `&str` and allocate inside only when needed.

**Flag**: `.clone()` on heap types (`String`, `Vec`, `HashMap`) at function call boundaries.

---

**`Rc<RefCell<T>>` abuse**

`RefCell` defers borrow checking to runtime and PANICS on violation. `Rc<RefCell<T>>` outside tree/graph structures usually signals unclear ownership. Runtime borrow check overhead is measurable > 1M accesses/sec.

Failure scenario: two code paths both hold `RefCell` borrows, one mutable. Second access panics at runtime — no compile-time warning.

Prefer: restructure to `&mut T` (single owner), or actor pattern (owned state in task, communicate via channels).

---

**`std::sync::Mutex` held across `.await`**

```rust
let guard = mutex.lock().unwrap();
some_async_op().await;         // BAD — guard still held
// If this task is scheduled on same thread that re-enters, deadlock
```

Rule: if the critical section contains no `.await`, use `std::sync::Mutex` and drop the guard before `.await`. Otherwise use `tokio::sync::Mutex` (heavier) or restructure to actor pattern.

---

**`.collect::<Vec<_>>()` mid-iterator-chain**

Breaks lazy fusion, forces allocation, prevents LLVM auto-vectorization. Only collect when you need random access, multiple passes, or an owned value at the boundary.

---

**`async fn` calling `std::fs` / `std::thread::sleep`**

Blocks the executor thread. All other tasks on that thread starve silently — the executor isn't "stuck" visibly.

Fix: `tokio::fs`, `tokio::time::sleep`, `tokio::task::spawn_blocking` for unavoidable blocking.

---

**`unsafe` block without `SAFETY:` comment**

Documents the invariants `unsafe` code relies on. Without it, future refactors cannot verify they haven't violated those invariants.

**Flag**: `clippy::undocumented_unsafe_blocks`.

---

**Edition 2024 silent breaking changes**

- RPIT lifetime capture inversion (RFC 3498): `impl Trait` now captures ALL in-scope lifetimes. Fix with `use<'a, T>` precise-capture bounds. Lint: `impl_trait_overcaptures`.
- `static mut` references are hard error (was warning).
- `std::env::{set_var, remove_var}` are now `unsafe`.
- `if let` temporary lifetime narrowing — RefCell guard patterns silently panic at runtime.

---

### Rust Tooling Commands

```bash
# Lint with expert rule set
cargo clippy -- \
  -W clippy::pedantic \
  -W clippy::undocumented_unsafe_blocks \
  -W clippy::unwrap_used \
  -W clippy::expect_used \
  -A clippy::module_name_repetitions \
  --message-format json > .audit/clippy.json

# Dependency hygiene
cargo machete                     # unused deps (watch for proc-macro FPs)
cargo deny check                  # licenses, advisories, bans
cargo audit                       # CVE check

# UB detection (slow, nightly)
cargo +nightly miri test

# Edition migration
cargo fix --edition               # automatic 2024 migration
```

---

## Go

### Go Anti-Patterns (Non-Obvious)

**`%v` vs `%w` in `fmt.Errorf` (silent `errors.Is` failure)**

```go
// BAD — flattens chain to string
err := fmt.Errorf("load failed: %v", inner)
errors.Is(err, ErrNotFound)  // returns FALSE even if inner wraps ErrNotFound

// GOOD — preserves chain
err := fmt.Errorf("load failed: %w", inner)
errors.Is(err, ErrNotFound)  // works
```

Failure scenario: Tests pass (string still contains "not found"), production behavior breaks silently because `errors.Is` returns false and the retry logic doesn't fire.

**Flag**: `fmt.Errorf.*%v.*err` patterns — strong signal of error chain destruction.

---

**Context stored in struct**

Go docs explicit: "Do not store Contexts inside a struct type." Goroutines hold reference to cancelled context that never signals; request-scoped values leak into longer-lived objects.

**Flag**: `staticcheck SA1012`. Grep for `ctx context.Context` as a struct field.

---

**`context.Background()` severing cancellation chain**

Most common goroutine leak pattern: function accepts `context.Context` but passes `context.Background()` to a sub-call. Sub-goroutine runs indefinitely after parent request completes.

```go
func Handler(ctx context.Context, req Request) {
    // BAD — severs chain
    go process(context.Background(), req)
    // GOOD
    go process(ctx, req)
}
```

---

**`go func()` without lifecycle**

Spawning `go func()` without `WaitGroup`, `errgroup`, or context for cancellation is unstructured concurrency. Panics crash the process (unrecoverable in the goroutine).

Use `golang.org/x/sync/errgroup` with `SetLimit` for bounded worker pools.

---

**`for range items { go process(item) }` without worker pool**

O(n) goroutines per request. Under bursty load this exhausts memory.

---

**`sync.Map` vs `sync.RWMutex` map**

`sync.Map` is optimized for read-heavy, APPEND-ONLY patterns (keys written once). For general concurrent maps with frequent updates, `sync.RWMutex`-protected map is FASTER. Using `sync.Map` as a general concurrent map is a performance anti-pattern.

---

**`time.After` in loops (not GC'd until fired)**

```go
// BAD — leaks timer channels
for {
    select {
    case <-time.After(5 * time.Second):
        // ...
    case <-done:
        return
    }
}

// GOOD
t := time.NewTimer(5 * time.Second)
defer t.Stop()
for {
    t.Reset(5 * time.Second)
    select {
    case <-t.C:
    case <-done: return
    }
}
```

---

**`omitempty` on `time.Time`**

Zero `time.Time` serializes as `"0001-01-01T00:00:00Z"`, NOT absent. `omitempty` only omits basic types, pointers, maps, slices.

Fix: `*time.Time` pointer (omitempty omits nil) or custom `MarshalJSON`.

---

**Slice append aliasing**

```go
s1 := []int{1,2,3,4,5}
s2 := s1[:3]
s2 = append(s2, 99)
// May or may not modify s1[3] depending on cap(s1)
// Use s1[:3:3] to force allocation on append
```

---

**Sub-slice holds entire backing array**

```go
result := large[:5]  // keeps entire `large` alive for GC
// Fix:
result := make([]byte, 5)
copy(result, large[:5])
```

---

**Mixed pointer/value receivers on a type**

If a type has any pointer receiver method, it should have ALL pointer receiver methods. Value type may satisfy some interfaces but not others with NO compile-time diagnostic.

---

### Go Tooling Commands

```bash
# Meta-linter (run first)
golangci-lint run --out-format json ./... > .audit/golangci.json

# .golangci.yml must enable: staticcheck, govet, errcheck, gosec, revive,
# gocyclo (threshold 10), goimports, gofumpt, unconvert, unparam, gosimple,
# bodyclose, noctx, exportloopref (pre-1.22)

# Security
govulncheck ./... > .audit/govulncheck.txt   # call-graph aware
gosec ./...                                   # SAST

# Dead code
deadcode ./... > .audit/deadcode.txt

# Race detection
go test -race ./...

# Dependency audit
go mod verify
go list -u -m all | grep '\['   # outdated modules
```

---

## Cross-Language Performance Sub-Playbook

The performance agent runs these checks regardless of stack:

1. **Algorithmic complexity on hot paths** — grep for nested loops in recon hot-spot files; flag O(n²) over likely-large collections.
2. **Database N+1 queries** — grep for query calls inside loops or inside map/iter closures.
3. **Async / await blocking** — language-specific (see above).
4. **Allocation in hot loops** — string concat in loops, intermediate collection building, repeated regex compilation.
5. **Missing pagination on list endpoints** — grep route handlers for `.all()`, `SELECT * FROM`, `.find({})` without LIMIT.
6. **Missing indexes** (if SQL migrations are readable) — WHERE clauses in hot queries not covered by index in migrations.
7. **Bundle signals** (frontend) — barrel file re-exports, wildcard imports from large libraries, missing code splitting.

## Cross-Language Design Sub-Playbook

The design agent focuses on hot-spots (from recon):

1. **Divergent change** — files that change for unrelated reasons (use `git log --follow --name-only` + cluster by commit subject)
2. **Shotgun surgery** — features that require touching many files (use temporal coupling pairs from recon)
3. **Feature envy** — method uses other class's data more than its own
4. **Data clumps** — same 3-4 fields repeat across classes
5. **Primitive obsession** — domain concepts (Money, Email, DateRange) as raw primitives
6. **Inappropriate intimacy** — class reaches into another's private state
7. **Temporal coupling** — files that always change together without import relationship

Do NOT flag: long functions that are single-concept and deep (Ousterhout), single-implementation interfaces used only in tests, duplication before Rule of Three, over-applied SRP producing shallow modules.
