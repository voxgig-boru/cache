# CLAUDE.md

This repository is the `Cache` bounded-caching library, written in boru.

## Status — designed, not implemented

`cache.aql` exports an **empty** `Cache` namespace; the five suites are
green placeholders. There is no API to call yet.

**@DESIGN.md is the substance of this repository right now.** Read it
before adding anything. Three of its rulings are easy to undo by
accident:

- **This is an effect memoizer, not a general-purpose cache.** The
  break-even governs the whole API. It was argued from a ~63µs map read
  on the old interpreter; on boru main @ `64c5ab2` a read is ~1–3µs and a
  cache-shaped lookup ~10µs (DESIGN.md §2 note, `bench/map_cost.aql`), so
  the framing is now open question 5 rather than a runtime necessity.
- **Default eviction is SIEVE, not LRU.** A textbook LRU needs a
  doubly-linked list, which boru cannot express well (cyclic flex
  references break `jsonify` and risk `deq` recursion). CLOCK/SIEVE need
  only an array and a hand — and beat LRU on hit rate anyway.
- **The library never reads the clock.** `clock` is a gated policy scope;
  TTL takes `now` as a parameter so the core stays zero-capability and
  deterministic under property tests.

`Cache.memoize` is absent from v1 by scope, not by defect: the boru
function-value scope defect that once blocked it
(`design/FUNCTION-VALUE-SCOPE.0.md`) is fixed upstream (boru `7e98aeb`,
re-verified on main) — a function value resolves its free words in the
module that defined it. See DESIGN.md §7.

## Working on this repository

- A SessionStart hook builds `boru` from boru-lang/boru **main** HEAD in
  remote sessions so a fresh session can run the suites. Locally, build it
  from source (`cd <boru>/cmd/go && go build -o ~/.local/bin/boru ./boru`).
- **One execution path.** `boru X` runs a static pre-flight check, then
  compiles to bytecode and runs on the VM, or fails with
  `[boru/compile_failed] … compiler defect`; there is no interpreter
  fallback, and `--compile` / `--force-compile` / `--no-compile` are
  retired (usage errors). Never use `-no-check` to get green.
- The whole library is one file, `cache.aql`, exporting the single
  `Cache` namespace. Relative imports resolve against the **importing
  file's own directory**: the suites in `test/` import `"../cache.aql"`
  (and import it before `boru:test` — see `dx-report.md`).
- Tests live in `test/`, named `cache_<unit|prop>_<test|spec>.aql` plus a
  `cache_smoke_test.aql`. Each assertion-bearing suite ends with
  `Assert.equal 0 (Test.fail-count)` and prints `all green`, one
  `print (…)` per value (postfix print chains reorder).
- `test/divergence/run.sh` is the gate (CI calls it): every suite exits 0
  under `boru X` and prints `all green` where it asserts, and `boru check`
  reports 0 errors on every suite and on `cache.aql`. `BORU=/path/to/boru`
  reuses a binary. Verified against boru main @ `64c5ab2` (2026-10-01).
- boru gotchas, the migration to boru main and the open upstream defects
  (with repros) are in `dx-report.md`.
- The planned keystone property is the **eviction contract**: `size`
  never exceeds `capacity`, and every policy agrees with a naive
  list-based reference implementation on which keys survived.
- Instantiated from the `bloom-filter` template; scaffolding renamed, no
  bloom logic or documentation carried across.
