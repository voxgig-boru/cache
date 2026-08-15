# AGENTS.md — using the `Cache` library

> **There is no API yet.** This library is **designed, not implemented**:
> `cache.aql` exports an empty `Cache` namespace. If you are an agent
> trying to call it, stop — there is nothing to call.
>
> The design lives in **[DESIGN.md](DESIGN.md)**.

## What it will be

Bounded caching with pluggable eviction: `Cache.make`, `get`, `put`,
`has`, `delete`, `clear`, `stats`, `keys`.

## Three things already fixed

**Calling convention — forward args, receiver (the cache) LAST:**
`Cache.verb …args c`. Piping (`c Cache.verb …args end`) binds
identically; only receiver-first-all-forward misbinds.

**It is an effect memoizer.** A map read costs ~63µs on this runtime.
Caching work cheaper than that makes the program *slower*. Wrap network
calls, file reads and expensive parses — not arithmetic.

**No `memoize` word.** Passing a function into this library and invoking
it there hits boru's free-word scope defect
(`design/FUNCTION-VALUE-SCOPE.0.md`): the function would lose its own
module's helpers, or silently bind ours. Cache the *result* yourself with
`get`/`put` until that is fixed.

## Where to look next

- `DESIGN.md` — the roster, the measurement, the constraints, the open
  questions.
- `docs/` — Diátaxis documentation, to be written against the real API.
