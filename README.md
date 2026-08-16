# cache

Bounded caching with pluggable eviction for
[boru](https://github.com/boru-lang/boru).

> **Status: designed, not implemented.** `cache.aql` exports an empty
> `Cache` namespace and the test suites are green placeholders. The
> argued design is in **[DESIGN.md](DESIGN.md)** — read that first.

## Read this before reaching for it

A map read costs **~63µs** on this runtime (a write ~3µs; both O(1)).
A cache only pays for itself over work that costs substantially more than
a lookup:

| Cached work | Verdict |
|---|---|
| Network fetch (1–100 ms) | **15–1500× win** |
| File read / parse (0.1–1 ms) | **2–15× win** |
| Cheap pure computation (< 63 µs) | **a net loss — slower than recomputing** |

So this is an **effect memoizer**, not a general-purpose cache. Wrap I/O
and expensive derivations with it; do not wrap arithmetic. `Cache.stats`
ships from day one so you can check you were right.

## What it will be

`Cache.make` / `get` / `put` / `has` / `delete` / `clear` / `stats` /
`keys`, over a bounded store with a pluggable eviction policy —
defaulting to **SIEVE** rather than LRU (simpler, no linked list, and
better hit rates on real workloads; see DESIGN.md §5).

## Project layout

```
cache.aql                 the library (the Cache namespace) — currently a stub
DESIGN.md                 the argued plan for what goes in it
AGENTS.md                 agent guide: how to call this library correctly
test/cache_*.aql          the five suites (naming convention held, bodies empty)
docs/                     Diátaxis documentation
```

## Running it

```bash
boru test/cache_smoke_test.aql
```

See [How-to → Install and run](docs/how-to.md#install-and-run-aql).

## License

See [LICENSE](LICENSE).
