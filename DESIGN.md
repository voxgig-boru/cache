# DESIGN — caching and eviction

> **Status: design only. Nothing is implemented.** `cache.aql` exports an
> empty `Cache` namespace; the test suites are green placeholders. This
> document is the argued plan — and, unusually, it argues first about
> *whether* and *what*, because a measurement taken before writing it
> changes what this library should be.

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

## 6. Time: take it, don't read it

TTL is the most-requested cache feature and the one that would quietly
cost the most. `clock` is a **gated policy scope** in boru, so a library
that calls `TimeUtil.now` internally stops working under a restrictive
profile and drags every consumer into needing the capability.

**Ruling: the library never reads the clock.** If TTL lands, the caller
supplies the timestamp: `Cache.put-at now key value c` /
`Cache.get-at now key c`. The core stays pure, testable without a clock,
and deterministic under property testing.

This is the same ruling the sibling `sort` library needs for `shuffle` —
boru has no ambient randomness, so a seed is passed in — and it should be
stated in the same terms.

## 7. Memoization is blocked, and by what

The obvious headline word is `Cache.memoize f c` — wrap a function, cache
its results. **It cannot be built correctly today.**

Passing a function across a module boundary and invoking it there is
exactly the defect recorded in boru's `design/FUNCTION-VALUE-SCOPE.0.md`:
the interpreter resolves the function's free words in the **running**
module, so a memoized function loses access to its own module's helpers —
or, worse, silently binds a same-named word inside this library and
returns a plausible wrong value, with `boru check` reporting nothing.

Concretely: if this library had a private helper named `hash`, and a
caller memoized a function that called *their* `hash`, they would get
ours.

**Ruling: no `memoize` in v1.** The eviction core takes data, not
functions, and is unaffected — build that first. `memoize` lands when
that doc's phase 1 (the native-callback seam) does, and until then the
README should say why rather than leaving a conspicuous gap unexplained.

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
