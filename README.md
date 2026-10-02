# cache

Bounded caching with pluggable eviction for
[boru](https://github.com/boru-lang/boru).

> **Status: designed, not implemented.** `cache.aql` exports an empty
> `Cache` namespace and the test suites are green placeholders. The
> argued design is in **[DESIGN.md](DESIGN.md)** — read that first.

## Read this before reaching for it

On boru main @ `64c5ab2` (re-measured 2026-10-01, compiled) a map read
costs **~1–3µs** and a write ~2–4µs, both O(1); a whole cache-shaped
lookup — a call, a hit-counter bump and the entry read — is **~10µs**.
(The design was written against ~63µs reads on the old interpreter; see
[DESIGN.md](DESIGN.md) §2.) A cache only pays for itself over work that
costs substantially more than a lookup:

| Cached work | Verdict |
|---|---|
| Network fetch (1–100 ms) | **a large win** |
| File read / parse (0.1–1 ms) | **a clear win** |
| Non-trivial boru computation (tens of µs and up) | worthwhile |
| Cheap pure computation (under ~10 µs) | **a net loss — slower than recomputing** |

So the design centres on wrapping **effects** and expensive derivations,
not arithmetic. `Cache.stats` ships from day one so you can check you
were right; `boru bench/map_cost.aql` re-measures the lookup cost on your
build.

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
test/divergence/run.sh    the gate: every suite runs + checks clean on boru main
bench/map_cost.aql        re-measures the map read/write cost behind DESIGN §2
docs/                     Diátaxis documentation
dx-report.md              boru gotchas, and the migration to boru main
```

## Running it

```bash
boru test/cache_smoke_test.aql          # compile + run (the only execution path)
BORU=$(command -v boru) test/divergence/run.sh   # the full gate
```

Verified against boru main @ `64c5ab2` (2026-10-01). See
[How-to → Install and run boru](docs/how-to.md#install-and-run-boru).

## License

See [LICENSE](LICENSE).
