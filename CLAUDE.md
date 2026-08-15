# CLAUDE.md

This repository is the `Cache` bounded-caching library, written in boru.

## Status — designed, not implemented

`cache.aql` exports an **empty** `Cache` namespace; the five suites are
green placeholders. There is no API to call yet.

**@DESIGN.md is the substance of this repository right now.** Read it
before adding anything. Three of its rulings are easy to undo by
accident:

- **This is an effect memoizer, not a general-purpose cache.** A map read
  costs ~63µs, so caching anything cheaper than that is a net loss. The
  break-even governs the whole API.
- **Default eviction is SIEVE, not LRU.** A textbook LRU needs a
  doubly-linked list, which boru cannot express well (cyclic flex
  references break `jsonify` and risk `deq` recursion). CLOCK/SIEVE need
  only an array and a hand — and beat LRU on hit rate anyway.
- **The library never reads the clock.** `clock` is a gated policy scope;
  TTL takes `now` as a parameter so the core stays zero-capability and
  deterministic under property tests.

`Cache.memoize` is deliberately absent: it would pass a function across a
module boundary, which is the defect recorded in boru's
`design/FUNCTION-VALUE-SCOPE.0.md` (the callee's free words resolve in
the running module, so a memoized function can silently bind *this*
library's helpers). It lands when that doc's phase 1 does.

## Working on this repository

- A SessionStart hook builds `boru` in remote sessions so a fresh session
  can run the suites.
- The whole library is one file, `cache.aql`, exporting the single
  `Cache` namespace.
- Tests live in `test/`, named `cache_<unit|prop>_<test|spec>.aql` plus a
  `cache_smoke_test.aql`. Each assertion-bearing suite ends by asserting
  `Test.fail-count` is `0` and prints `all green`.
- The planned keystone property is the **eviction contract**: `size`
  never exceeds `capacity`, and every policy agrees with a naive
  list-based reference implementation on which keys survived.
- Instantiated from the `bloom-filter` template; scaffolding renamed, no
  bloom logic or documentation carried across.
