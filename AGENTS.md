# AGENTS.md — using the `Cache` library

> **There is no API yet.** This library is **designed, not implemented**:
> `cache.aql` exports an empty `Cache` namespace. If you are an agent
> trying to call it, stop — there is nothing to call.
>
> The design lives in **[DESIGN.md](DESIGN.md)**. Everything below was
> re-verified against boru main @ `64c5ab2` (2026-10-01).

## What it will be

Bounded caching with pluggable eviction: `Cache.make`, `get`, `put`,
`has`, `delete`, `clear`, `stats`, `keys`.

## Already fixed

**Calling convention — forward args, receiver (the cache) LAST:**
`Cache.verb …args c`. Piping (`c Cache.verb …args`) binds identically.
Receiver-first all-forward (`Cache.verb c …args`) misbinds: when the
receiver is a typed class instance `boru check` rejects it
(`uncalled_function: … matched no signature`, which also blocks
`boru X`), but two arguments of the same type still bind silently in
signature order.

**Import it relative to the importing file.** `import "./cache.aql"`
resolves against the directory of the file that contains the `import`
(for `boru X` and `boru check X` alike), not the working directory — a
suite in `test/` writes `import "../cache.aql"`.

**A cache only pays over work dearer than a lookup.** On boru main a map
read costs ~1–3µs and a cache-shaped lookup (a call, a hit-counter bump,
the entry read) ~10µs (DESIGN.md §2, re-measured 2026-10-01; it was
~63µs on the old interpreter). Caching work cheaper than that makes the
program *slower*: wrap network calls, file reads, parses and other
expensive work — not arithmetic — and check `Cache.stats`.

**`memoize` is not blocked any more, just not built.** The free-word
scope defect that once barred it is fixed upstream (boru `7e98aeb`): a
function value resolves its free words in the module that defined it,
re-verified on main. Until the library ships one, cache a *result*
yourself with `get`/`put`. When you hand a function to any word, write
`f/v` — a bare name holding a function calls wherever it appears (`/r`
was renamed `/v`).

## Where to look next

- `DESIGN.md` — the roster, the measurement, the constraints, the open
  questions.
- `bench/map_cost.aql` — re-measures the lookup cost on your boru.
- `dx-report.md` — boru gotchas and the migration to boru main.
- `docs/` — Diátaxis documentation, to be written against the real API.
