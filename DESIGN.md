# DESIGN — caching and eviction

> **Status: design only. Nothing is implemented.** `cache.aql` exports an
> empty `Cache` namespace; the test suites are green placeholders. This
> document is the argued plan — and, unusually, it argues first about
> *whether* and *what*, because a measurement taken before writing it
> changes what this library should be.
>
> **Re-verified against boru main @ `64c5ab2` (2026-10-01).** Every claim
> below that cites boru behaviour was re-run on main, where a program is
> compiled to bytecode and run on the VM — the only execution path since
> 2026-09-19. The original text stands; dated **Note (2026-10-01)** blocks
> mark where main differs. The one that matters most: **a map read is no
> longer ~63µs but ~1–3µs, and a whole cache-shaped lookup ~10µs** (§2,
> Appendix), which moves the break-even rows 1–2 rest on. Also changed:
> `memoize` is unblocked (§7), `while` exists and `min`/`max` are not
> reserved (§9), cyclic `flex` references now crash the process outright
> (§5), and the `clock` scope's own gate does not stop `TimeUtil.now` —
> the import gate does (§6). Still true: quadratic immutable-Map
> accumulation, the `make Store` refusal, String/Atom-only keys,
> two-value `pop`/`shift` with an O(n) `shift`, eager `and`/`or`.

This repository was instantiated from the `bloom-filter` template. The
scaffolding has been renamed for `cache`; none of the bloom filter's
logic, tests or documentation was carried across.

---

## 0. The decisions, at a glance

| # | Decision | Ruling | Why (one line) |
|---|----------|--------|----------------|
| 1 | What this library *is* | An **effect memoizer**, not a general-purpose cache | A lookup costs ~63µs, so it pays only for work costing far more |
| 2 | What it is **not** | Not a hot-path cache for cheap computation | Below ~63µs of work, the cache is slower than recomputing |
| 3 | Eviction algorithm | **CLOCK / SIEVE**, not textbook LRU | LRU needs a doubly-linked list; boru has no good one, and the modern FIFO-based algorithms match or beat LRU anyway |
| 4 | Time | **Take `now` as a parameter**; never read the clock | `clock` is a gated policy scope — reading it costs the library its zero-capability posture |
| 5 | Memoization | **Blocked** on the boru free-word scope defect | `Cache.memoize f` is exactly the broken case; ship the data-only core first |
| 6 | Storage | `flex` map + a `flex` list ring | Measured O(1); immutable Map accumulation is quadratic |
| 7 | Keys | **Strings** | boru map keys are String/Atom only |
| 8 | Statistics | Ship hit/miss/eviction counters from day one | Without a hit rate the user cannot tell whether the cache is helping or hurting — which, per #1, it may well be |

> **Note (2026-10-01, boru main @ `64c5ab2`).** Rows 1–2 rest on the
> ~63µs read, measured on the interpreter. Compiled on main a map read is
> ~1–3µs and a cache-shaped lookup (a fn call, a hit-counter bump and the
> entry read) ~8–13µs net (§2 note), so the break-even is roughly **ten
> microseconds of work, not 63**. Cheap arithmetic is still a loss, but
> moderately priced pure computation now pays — the "effect memoizer"
> framing has become a scope choice rather than something the runtime
> forces (§11 Q5). Row 4's reason is refined in §6, row 5 is lifted (§7),
> and row 6's quadratic-Map premise was re-measured and still holds (§9).

---

## 1. The family

| Group | Members |
|---|---|
| **Recency / frequency eviction** | LRU, LFU, FIFO, MRU, random, **CLOCK** (second-chance), SLRU, 2Q, ARC, LIRS |
| **Modern hybrids** | **W-TinyLFU** (Caffeine — admission filter over a frequency sketch), **S3-FIFO**, **SIEVE** |
| **Expiry** | expire-after-write, expire-after-access, refresh-ahead |
| **Memoization** | function-result caching, lazy / once |
| **Neighbours (not here)** | Count-Min Sketch, HyperLogLog, consistent hashing, rate limiters |

They all answer one question — *when the store is full, what goes?* — and
differ in what they track to decide: recency (LRU/CLOCK), frequency
(LFU/TinyLFU), both (ARC/2Q/LIRS), or nothing (FIFO/random).

## 2. The measurement that reframes this library

Measured on this build, interpreter path (which is what real code hits —
`each` bodies currently refuse compilation):

| Operation | Cost | Scaling |
|---|---|---|
| map **write** (`set`) | **~3.2 µs** | O(1) — flat from n=2,500 to 20,000 |
| map **read** (`get` / `has`) | **~63 µs** | O(1) — flat, and identical for plain maps, flex maps and `has` |

A cache exists to be cheaper than recomputing. At ~63µs per lookup, the
break-even is stark:

| Cached work | Cost | Verdict |
|---|---|---|
| Network fetch | 1–100 ms | **15–1500× win** |
| File read / parse | 0.1–1 ms | **2–15× win** |
| Non-trivial boru computation | 0.1–10 ms | worthwhile |
| Cheap pure computation | < 63 µs | **a net loss — the cache is slower** |

**So this is not a cache library; it is an effect memoizer.** That has to
be said in the README, not discovered by a user who wraps an arithmetic
helper and gets slower. It also sets the API's centre of gravity: the
headline word should be the one that wraps an expensive *effect*, and the
eviction machinery is what keeps that store bounded.

**If hot-path caching is what is wanted** — memoising dispatch, parses,
or interpreter-internal work — it cannot be a boru library at any quality
of implementation, and belongs Go-side as a `boru:cache` native module.
The engine already carries `dispatchCache`, `macroCache` and `enginePool`
internally for exactly this reason. That is a different project; this
document does not pursue it.

> **Note (2026-10-01, boru main @ `64c5ab2`) — the measurement, redone.**
> "Interpreter path" and "`each` bodies refuse compilation" are both gone:
> since 2026-09-19 every program compiles to bytecode or fails, and the
> loops below compiled with no runtime-constructed callbacks
> (`boru -compile-report`). Re-measured with
> [`bench/map_cost.aql`](bench/map_cost.aql) plus an n-sweep (Appendix),
> on a 4-CPU container shared with other jobs, so treat the figures as
> ±50%:
>
> | Operation | Cost on main, net of the bare loop | Was |
> |---|---|---|
> | `flex` map **write** (`set (k)`) | **~2–4 µs** | ~3.2 µs |
> | map **read** (`get (k)`), flex or plain | **~1–2.5 µs** | ~63 µs |
> | `has (k)` | **~1–3 µs** (≈ a read) | ~63 µs |
> | a cache-shaped lookup fn (call + counter read/write + entry read) | **~8–13 µs** | — |
>
> All flat from n=10,000 to 40,000 (O(1)). The read/write asymmetry the
> Appendix flagged is gone — reads are now no dearer than writes — so
> whatever made reads ~20× writes was fixed upstream. The break-even
> table above therefore shifts down by roughly an order of magnitude: the
> verdict line becomes *cheap pure computation, under ~10µs*, and
> "non-trivial boru computation" (tens of µs and up) is a clear win. The
> argument for `Cache.stats` (§8) is unchanged — a cache can still make a
> program slower — but the "this is not a cache library" conclusion no
> longer follows from the numbers alone (§11 Q5).

## 3. Why a separate library

Same ecosystem test the sibling repos apply. A cache is a **stateful,
mutable object with a lifecycle** — make it, read through it, let it
evict — which is the `bloom-filter` shape (a sealed class instance over
flex storage), not the pure-function shape of `sort` and `graph`. It is
pure computation with no capability needs *provided* §6 holds, so it
keeps the sandbox-safe posture every sibling has.

## 4. The proposed surface

Arguments forward, receiver (the cache) **LAST**, as everywhere else.

| Call | Returns | Notes |
|------|---------|-------|
| `Cache.make {capacity policy}` | `Cache` | `policy` one of `"sieve"` / `"clock"` / `"fifo"` / `"lru"`. Bad args raise `bad_input`. |
| `Cache.get key c` | value or `none` | Records a hit or a miss. Absent ⇒ `none`; use `Cache.has` to distinguish "absent" from "present with value `none`". |
| `Cache.put key value c` | the same `c` (mutated) | Evicts under the policy when full. |
| `Cache.has key c` | `Boolean` | Does **not** count as an access for eviction purposes — or does, if `policy` is access-based. §11 Q2. |
| `Cache.delete key c` | the same `c` | |
| `Cache.clear c` | the same `c` | |
| `Cache.stats c` | `Map` | `{hits misses evictions size capacity hit-rate}` — see §8. |
| `Cache.keys c` | `List` | In eviction order, so the next victim is first. Useful, and free. |

Deliberately **not** in v1: `Cache.memoize` (§7), TTL words (§6),
`merge`, `encode`/`decode`.

```boru
def c ({capacity: 500, policy: "sieve"} Cache.make)
def _ (Cache.put "user:42" profile c)
Cache.get "user:42" c        # => profile
Cache.stats c                # => {hits: 1, misses: 0, evictions: 0, …}
```

## 5. Eviction: don't build textbook LRU

**LRU is the wrong first algorithm here**, for a boru-specific reason and
a general one.

The boru-specific reason: an O(1) LRU is a hash map plus a **doubly-linked
list**, and boru has no good way to express one. True node links mean
cyclic `flex` references — which break `jsonify` and risk unbounded
recursion in `deq` — and the alternative is hand-rolled integer index
links, which is a lot of error-prone machinery for a first release.

The general reason: the last few years of cache research went the other
way. **SIEVE** (a FIFO queue plus a moving hand that gives each entry one
second chance) and **S3-FIFO** are markedly simpler than LRU and report
*better* hit rates on real workloads; **CLOCK** has been the standard
cheap LRU approximation for decades. All three need only an array and an
index — no linked list at all.

**Ruling: ship `"sieve"` as the default**, with `"clock"` and `"fifo"`
alongside; implement `"lru"` later, if at all, and only via index links.
The constraint and the state of the art agree, which is the comfortable
case.

Frequency-aware policies (LFU, W-TinyLFU) are deferred: they need a
frequency sketch, which is the sibling `bloom-filter` repo's
neighbourhood (a Count-Min Sketch), and they are a second-order win once
a bounded store exists.

> **Note (2026-10-01, boru main @ `64c5ab2`).** Worse than "break
> `jsonify` and risk recursion in `deq`": a cyclic `flex` structure kills
> the process. `print`, `StructUtil.jsonify` and `deq` (even `a deq a`)
> over a self- or mutually-referencing flex node all die with the Go
> runtime's `fatal error: stack overflow` (exit 2), which `do […] error
> […]` cannot catch. Building the cycle is fine; touching it whole is not.
> The ruling stands, more firmly: no node links, index links only.

## 6. Time: take it, don't read it

TTL is the most-requested cache feature and the one that would quietly
cost the most. `clock` is a **gated policy scope** in boru, so a library
that calls `TimeUtil.now` internally stops working under a restrictive
profile and drags every consumer into needing the capability.

**Ruling: the library never reads the clock.** If TTL lands, the caller
supplies the timestamp: `Cache.put-at now key value c` /
`Cache.get-at now key c`. The core stays pure, testable without a clock,
and deterministic under property testing.

> **Note (2026-10-01, boru main @ `64c5ab2`).** The mechanism is not the
> one described above. The `clock` policy scope's own gate does not stop
> `TimeUtil.now`: under `-deny-global clock`, or a profile with
> `scopes: {clock: {install: false}}`, it still returns the wall clock
> (the time module falls back to the wall clock when no clock capability
> is installed — recorded in `dx-report.md` as an upstream defect). What
> does refuse it is the **module-import gate**: the built-in `gen`
> profile, for one, denies `import "boru:time-util"` itself
> (`permission_denied: modules.import`), so a library that imports the
> time module fails to load at all there. The ruling stands for the same
> end reason — reading the clock costs the library its zero-capability
> posture — and for determinism under property tests.

This is the same ruling the sibling `sort` library needs for `shuffle` —
boru has no ambient randomness, so a seed is passed in — and it should be
stated in the same terms.

> **Note (2026-10-01, boru main @ `64c5ab2`).** "No ambient randomness"
> is not accurate: `boru:rand` (`Rand.int lo hi`, `Rand.float`, …) draws
> from a time-seeded generator — three runs of `Rand.int 0 1000000` give
> three values, the `-s` flag does not fix them, and the `gen` profile
> allows the import. `Rand.with-seed` is the deterministic form. Passing a
> seed in is still the right ruling, for the determinism reason, not
> because boru forces it.

## 7. Memoization is blocked, and by what

The obvious headline word is `Cache.memoize f c` — wrap a function, cache
its results. **It cannot be built correctly today.**

> **UNBLOCKED 2026-08-15.** This section's blocker was boru's
> function-value scope defect, and it named its own release condition:
> *"`memoize` lands when that doc's phase 1 (the native-callback seam)
> does."* Phase 1 has landed (boru `7e98aeb`), so the technical obstacle
> is gone. What remains is a scope decision, not a constraint — see the
> revised ruling below.

Passing a function across a module boundary and invoking it there **was**
exactly the defect recorded in boru's `design/FUNCTION-VALUE-SCOPE.0.md`:
the interpreter resolved the function's free words in the **running**
module, so a memoized function lost access to its own module's helpers —
or, worse, silently bound a same-named word inside this library and
returned a plausible wrong value, with `boru check` reporting nothing.

Concretely: if this library had a private helper named `hash`, and a
caller memoized a function that called *their* `hash`, they got ours.

**That is fixed.** A function value now resolves its free words in the
module that *defined* it, on both engines, and specifically through the
native-callback seam a `memoize` implementation would use
(`core.InvokeCallbackFn` / `core.CallBoruFn`). A caller's `hash` and this
library's `hash` no longer collide.

> **Note (2026-10-01, boru main @ `64c5ab2`).** Re-verified: module A's
> function value calling A's private `secret`, handed as `A.h/v` to module
> B (which has its own `secret`) and applied there — directly and through
> a native `each` callback — runs **A's** `secret`; a caller-defined
> function calling the caller's own helper also resolves inside B. "Both
> engines" is now one: there is only the compiled path. `core.CallBoruFn`
> was retired (boru `b85cfc4e0`, 2026-08-28); `core.InvokeCallbackFn` is
> the seam. A function passed as data must be written `f/v` — a bare name
> holding a function **calls** wherever it appears (ADR-011; `/r` was
> renamed `/v` on 2026-08-19 and `/r` is now `undefined_word`).

**Revised ruling: `memoize` is no longer blocked; whether it belongs in
v1 is an ordinary scope call.** The eviction core still takes data, not
functions, and is still the thing to build first — that ordering was
never about the defect. Two notes for whoever picks `memoize` up:

- **Key derivation is the real design problem**, and always was. It was
  simply hidden behind the scope blocker. Arguments must be reduced to a
  map-legal key (String/Atom), which for structured arguments means a
  canonical rendering — see boru's ADR-015 (`canon` always round-trips).
- **Captures are snapshots, not cells** (`FUNCTION-VALUE-SCOPE.0.md` §11
  rule 2, still design-only). A memoized closure sees its captured values
  as they were at construction, which is usually what you want from a
  cache, but it should be documented rather than discovered.

## 8. Statistics are not optional here

Every cache library ships hit/miss counters; for this one they are
load-bearing. Because §2's break-even is real, a user can easily install
a cache that makes their program **slower**, and there is no way to
notice without a hit rate and an honest sense of what the cached work
costs. `Cache.stats` ships in v1, and the how-to guide should show
computing the break-even, not just reading the number.

## 9. boru implementation constraints

Carried from measurements taken across this ecosystem; all apply here.

- **Storage must be `flex`.** Immutable `Map` accumulation is quadratic;
  `flex` writes are ~3µs and flat. The entry map, the ring, and the
  counters are all `flex`; convert with `node` only at the `stats`
  boundary.
- **`Store` is not an option** — `make Store` is a coded refusal. There
  is no Set type; a Map to `true` is the idiom.
- **No `pop` / `shift`.** Both return two values (a residual the bytecode
  compiler refuses), and `shift` is O(n). The ring is an append-only
  `flex` list plus an integer hand — which is exactly what CLOCK and
  SIEVE want anyway.
- **Keys are Strings** — boru map keys must be String or Atom. A caller
  with structured keys stringifies them; document that the stringification
  is theirs to make collision-free.
- **No `while`** — `for N [body]` with `break`. Inside a `fn`, a `for`
  body nets **zero** values while an `each` body yields **exactly one**.
- **`and` / `or` do not short-circuit** — nest `if`.
- **Reserved names** — `keys`, `vals`, `has`, `node`, `stack`, `depth`,
  `find`, `list`, `min`, `max`, `range`. Free and idiomatic here: `ent`,
  `ring`, `hand`, `cap`, `hits`, `misses`, `victim`, `slot`, `ks`.

> **Note (2026-10-01, boru main @ `64c5ab2`) — each bullet re-run.**
>
> - **`flex`:** still required. Accumulating n keys into an immutable Map
>   with a copy-returning `set` in a `fold` is still quadratic — ~0.3 s at
>   n=1,000, ~1.0 s at 2,000, ~4.7 s at 4,000, ~11–17 s at 8,000 — against
>   ~5→25 ms for a `flex` map (several hundred × at n=8,000). `node`
>   converts a flex map to a plain one as described.
> - **`Store`:** confirmed — `make Store` raises
>   `[boru/unsupported]: make: unsupported target type Store`; `Set` is
>   an undefined word. A Map to `true` is still the idiom.
> - **`pop` / `shift`:** both still return two values (the list, then the
>   element on top), and `shift` is O(n): draining a 10,000-element flex
>   list takes ~5 s with `shift` vs ~25 ms with `pop` (20,000: ~20 s vs
>   ~40 ms). The old "residual shape beyond Stage 1" refusal no longer
>   exists; what compiles now is shape-dependent. Fully consumed shapes
>   compile (`pop q drop` to shrink a flex list; `pop xs var [[a b] a]`
>   over a **List** inside a fn), but keeping the element of a **flex**
>   list's `pop`/`shift` hits three compiler defects (`dx-report.md`).
>   The ring design — index reads/writes plus an integer hand — needs
>   neither, and `q get i` / `q set i v` / `pop q drop` all compile.
> - **Keys:** confirmed String/Atom only (`set` with an Integer key on a
>   map is a `no_signature` check error); a String and an Atom of the same
>   text share one slot. New trap for a cache, whose keys are always
>   computed: **`set` quotes a bare word** — `ent set key v` stores under
>   the literal key `"key"` — so write `ent set (key) v`; `get` and `has`
>   evaluate their key (boru NUR040, Allowed).
> - **Loops:** `while [cond] [body]` **exists** since boru 2026-08-21
>   (`99fc2c3ec`) and compiles inside a fn. A `for` body's per-iteration
>   values stay on the stack (collect them with `[for n [...]]`), so
>   inside a fn they count toward the declared return arity — net zero
>   unless collected. An `each` body must leave **at least** one value
>   (zero is a runtime `each_error`); with more than one, the top value
>   is kept. `for-each` is the no-result side-effect loop.
> - **`and` / `or`:** they select an operand (`0 and 5` → `0`,
>   `none or 7` → `7`) and the upstream docs call that "short-circuit",
>   but **both operand expressions are always evaluated** — a right-hand
>   side with an effect runs even when the left decides
>   (`design/TRUTHINESS.0.md` §5). "Nest `if`" stands.
> - **Reserved names:** `keys`, `vals`, `has`, `node`, `stack`, `depth`,
>   `find`, `list`, `range` are still `[boru/reserved_word]`; **`min` and
>   `max` are not** (they are `MathUtil.min`/`max`, free as bindings even
>   with `boru:math-util` imported). Also reserved and tempting in this
>   library: `size`, `get`, `set`, `del`, `push`, `pop`, `shift`, `each`,
>   `fold`, `filter`, `sort`, `reverse`, `dup`, `drop`, `swap`, `over`,
>   `rot`, `pick`, `valof`, `base`; `take` cannot be a fn name either (a
>   core word, `extend_owner`). Every listed free name is still free, as
>   are `count`, `put`, `delete`, `clear`, `peek`, `stats`, `capacity`,
>   `policy`, `key`, `val`, `entry`, `hit`, `miss`, `evict`, `now`.
> - **New — the step budget.** A run's total evaluation steps are capped
>   at 10,000,000 by default (`[boru/evaluation_limit]`; raise with
>   `boru -options steps:N`). A `for` body that updates a flex cell costs
>   over ten steps per iteration, so one run gets well under a million
>   such iterations — relevant to a cache inside a long-running loop.

## 10. Testing

The keystone is **the eviction contract**: after `capacity + k` distinct
puts, `size == capacity`, and exactly the entries the policy says should
have survived did.

| Property | Catches |
|---|---|
| `size` never exceeds `capacity`, ever | the whole point of the library |
| Put-then-get returns the value, for any key below capacity | basic storage |
| A key put twice is not duplicated; `size` unchanged | the classic hash/ring desync |
| **Every policy agrees with a naive reference implementation** on the surviving key set | the analogue of `sort`'s cross-agreement — a list-based O(n) model cache is the oracle |
| Repeatedly getting one key keeps it alive under `"sieve"`/`"clock"`/`"lru"`, but **not** under `"fifo"` | that the policy is actually implemented, not just named |
| `stats` counts reconcile: `hits + misses == total gets`, `evictions == puts - size` | accounting drift |
| Capacity 1, capacity 0, empty cache, key absent | the usual edges |

The naive oracle is the important one: it is cheap to write, obviously
correct, and it is what makes a subtle eviction bug visible.

## 11. Open questions

1. **Should `get` on a miss return `none` or raise?** Returning `none`
   matches `TrieMap.get` in the sibling library and makes the common
   path branch-free. (Leaning: `none`, with `has` to disambiguate.)
2. **Does `has` count as an access** for recency policies? Peeking
   without promoting is genuinely useful; so is not surprising people.
   (Leaning: `has` does *not* promote; add `Cache.peek` only if someone
   wants the other.)
3. **Is `Cache.keys` in eviction order worth the exposure?** It is free
   and excellent for tests and debugging, but it leaks policy internals
   into the API. (Leaning: ship it, documented as advisory.)
4. **Does a `"lru"` policy ever get built**, given §5? (Leaning: only if
   a real workload shows SIEVE losing to it — and then via index links.)
5. **Added 2026-10-01: does the "effect memoizer" framing survive the
   re-measurement?** §2's ruling followed from a ~63µs read; on boru main
   a cache-shaped lookup is ~10µs (§2 note). The effect-wrapping API
   centre and `Cache.stats` still make sense, but "never for
   computation" is now too strong — the honest rule is "work costing
   well over ~10µs". (Leaning: keep the effect-first framing, restate
   the break-even with the new number, and let `stats` arbitrate.)

## Appendix — measurements behind §2

Interpreter path, this build. Loop baseline (`iota n each` +
`convert String`) measured separately at ~1.9 µs/iteration and excluded.

| n | `flex` map writes | per op |
|---|---|---|
| 2,500 | 9 ms | 3.6 µs |
| 5,000 | 19 ms | 3.8 µs |
| 10,000 | 30 ms | 3.0 µs |
| 20,000 | 63 ms | 3.15 µs |

| n | map reads | per op |
|---|---|---|
| 2,500 | 159 ms | 63.6 µs |
| 5,000 | 314 ms | 62.8 µs |
| 10,000 | 620 ms | 62.0 µs |

Reads and writes are both **O(1)**, but reads are **~20× more expensive
than writes**, consistently, and identically for plain maps, `flex` maps
and `has`. That asymmetry is backwards for essentially every workload and
is worth a profile in the language repo — the likely suspect is the
polymorphic accessor dispatch path (`get`/`dot` over
List/Map/Bytes/Store/Flex) rather than the map itself. **It directly sets
the break-even in §2**, so improving it widens what this library is good
for: at 6 µs instead of 63 µs, caching moderately-priced computation
would start to pay.

### Re-measured on boru main @ `64c5ab2` (2026-10-01)

Compiled (the only execution path), on a shared 4-CPU container; medians
of five runs; "net" subtracts the bare `each` loop (~1.2–1.35 µs per
iteration, timed in the same run). Key building (`iota n each [convert
String]`, the old loop baseline) now costs ~2.3 µs per key, against
~1.9 µs before. Reproduce with `boru bench/map_cost.aql` (one n per run).

| n | `flex` map writes | per op, net | `flex` map reads | per op, net | plain map reads | per op, net | `has` | per op, net |
|---|---|---|---|---|---|---|---|---|
| 10,000 | 32 ms | 2.0 µs | 32 ms | 2.0 µs | 21 ms | 0.9 µs | 20 ms | 0.8 µs |
| 20,000 | 72 ms | 2.3 µs | 55 ms | 1.5 µs | 47 ms | 1.1 µs | 46 ms | 1.0 µs |
| 40,000 | 165 ms | 2.8 µs | 133 ms | 2.0 µs | 113 ms | 1.5 µs | 101 ms | 1.2 µs |

Reads went from ~63 µs to ~1–2 µs net (~30–60× cheaper); writes from
~3.2 µs to ~2–3 µs. Reads are now no dearer than writes, so the
asymmetry above — and the request for an upstream profile — is resolved.
A cache-shaped lookup fn (a call, a hit-counter `get` + `set`, an entry
`get`) measured ~8–9 µs net at n=10,000–40,000, ~9–13 µs in the
single-run bench; that is the figure the break-even should use.
