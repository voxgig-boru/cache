# DX report — boru runtime gotchas

Project-specific boru gotchas hit while building **this** library.

**Nothing is implemented yet**, so the library itself has hit nothing.
What this file records is the measurement that shaped the design, and
the migration of the scaffolding to boru main.

One measurement taken while designing is worth repeating here because it
shaped the whole library: **map reads cost ~63µs and writes ~3µs on the
interpreter, both O(1)** — a ~20× asymmetry, identical for plain maps,
flex maps and `has`. See [DESIGN.md](DESIGN.md) §2 and its appendix. The
likely suspect was the polymorphic accessor dispatch path rather than the
map itself. **Superseded on boru main — see M2 below: reads are now
~1–3µs and no dearer than writes.**

The other constraints already known to apply (quadratic immutable-Map
accumulation, the two-value `pop`/`shift` trap, the `for`/`each` body
arity rules, non short-circuiting `and`/`or`, reserved names) are
recorded in DESIGN.md §9, with a dated note re-checking each on main.

---

## Migration to boru main @ 64c5ab2 (2026-10-01)

The scaffolding was last run against boru `6185620` (2026-07-21), 1,587
upstream commits earlier. Since 2026-09-19 (`ba64e111c`) boru has **one
execution path**: `boru X` runs a static pre-flight check, then compiles
the program to bytecode and runs it on the VM, or fails with
`[boru/compile_failed] … this is a compiler defect`. There is no
interpreter fallback; `--compile` / `--force-compile` / `--no-compile`
are usage errors (`flag provided but not defined`, exit 1) and the
`BORU_COMPILE` / `BORU_FORCE_COMPILE` / `BORU_NO_COMPILE` env vars are
ignored. "A suite runs" now means "a suite fully compiles".

**Result:** all five suites compile, run green and `boru check` with
0 errors (one advisory `module_body_executed_in_check` info each);
`cache.aql` checks clean. `test/divergence/run.sh` passes.

### Breaking changes hit

**M1 — relative imports anchor on the importing file.** `import
"./cache.aql"` now resolves against the directory of the file that
contains the `import`, for `boru X` as well as `boru check X`. The suites
in `test/` imported `"./cache.aql"`, i.e. a non-existent
`test/cache.aql`, and every suite failed. Fix: `import "../cache.aql"`.
(CLI.md still says `boru run` resolves against the working directory;
that sentence is stale — a script run from another directory finds a
sibling-relative import.)

The failure was hard to read, which is its own upstream defect (**D1**
below): a missing import is not reported as a missing file. The check
degrades it to an opaque module and reports 0 errors, then the compile
pass fails with `residual value of unknown provenance` and no source
position. Worse, with the missing import *first*, the leftover `Module`
value is swallowed by the following `import "boru:test"`, so the check
then reports six errors (`undefined_word: Test` / `Assert` and the
matching `no_signature` on `dot`) that point nowhere near the real
cause.

**M2 — the measurement behind DESIGN §2 changed.** Re-measured compiled
on main (`bench/map_cost.aql` plus an n-sweep, DESIGN Appendix): a map
read is ~1–2.5µs net of the loop (was ~63µs), a write ~2–4µs (was
~3.2µs), `has` ≈ a read, and a cache-shaped lookup fn (call + hit-counter
`get`/`set` + entry `get`) ~8–13µs. The read/write asymmetry is gone, so
the request for an upstream profile is resolved. DESIGN.md now carries
dated notes and an open question on whether the "effect memoizer"
framing still follows.

**M3 — postfix `print` chains reorder.** The suites' summary was
`"---" print` / `"fail count: " print Test.fail-count end print` /
`0 Test.fail-count end Assert.equal end` / `"all green" print`; on main
`print` collects forward, so it printed `fail count:`, `0`, `0`,
`all green` (the `---` lost, a value printed twice). Fix: one value per
statement — `print ("---")`, ``print (`fail count: ${(Test.fail-count)}`)``,
`Assert.equal 0 (Test.fail-count)` (expected first: the failure reads
`Assert.equal: expected 0, got N`), `print ("all green")`. Checked that a
failing `Test.test` still makes the suite exit 1 without `all green`.

**M4 — tooling names.** The CLI is `boru` (build `cmd/go` → `./boru`);
native modules are `boru:*` (the `aql:` prefix is gone); `prep`/`pack`
write `.boru/` (was `.aql/`, now in `.gitignore`); `/r` is `/v` and
`ref` is `valof` (ADR-011, 2026-08-19). The harness, hook, `.gitignore`
and docs were updated; the CI workflow needed no edit (it runs
`test/divergence/run.sh` and the suites directly).

### Workarounds applied

- **Library before `boru:test`.** Each assertion-bearing suite imports
  `../cache.aql` before `boru:test`, the order the sibling bloom-filter
  and stats suites need for the type-ID collision (**D2**). There is no
  class here yet, so nothing actually collides today. Probing it for
  this migration showed the order is **not a general fix**: on a
  minimal library, whether a class collides depends on the type ID it
  lands on (a class that is the 1st–3rd type the library mints collides
  in either import order; from the 4th it does not).

### Open upstream defects (minimal repros)

None of these blocks a suite here; they matter to whoever implements
the design.

- **D1 — a missing import is misreported as a compiler defect**
  (unrecorded in NUR.md).
  ```boru
  import "./no-such-file.boru"
  ```
  `boru X` → `[boru/compile_failed]: … residual value of unknown
  provenance — this is a compiler defect` with `source position
  unknown`; `boru check` → `0 error(s)` (the import is degraded to an
  opaque `Module`). The same happens for `import "boru:no-such-module"`
  and a missing bare module. Expected: an `import_error` naming the path.

- **D2 — `boru:test` type-ID collision.** `boru:test`'s
  `BuildTestModule` builds its sub-registry without
  `modReg.Types.AdoptSeqFrom(parent.Types)` (which every other
  type-minting module has), so its record types reuse IDs a program's
  own classes get, and the VM's return-contract check fails:
  ```boru
  # lib.boru
  def Box class { v: 0 }
  def mk fn [ [n:Integer] [Box] [ make Box {v: n} ] ]
  export "L" { mk: mk/v }
  # main.boru
  import "./lib.boru"
  import "boru:test"
  print (L.mk 1)
  ```
  → `type_error: mk: return value 1: expected Box, got Box`, in either
  import order (without `boru:test`: `Class/Box{v:1}`).

- **D3 — keeping the element of a `flex` list's `pop`/`shift` fails to
  compile** (all three pass `boru check`; DESIGN §9 avoids the shape):
  ```boru
  def take-last fn [[q:FlexList] [Any] [ pop q swap drop ]]
  print (take-last (flex [5 6 7]))
  ```
  → `fn take-last: body result is a fn-value lead a later dispatch
  collected past (NUR121)` (NUR121 is marked resolved). With
  `pop q var [[a b] a]` in the body instead: `body leaves extra values
  (Stage 3 lowers in-order results)`. At top level,
  `def x (pop q swap drop)` → `stack discipline: result operand of drop
  is not on top`, and `print (pop [5 6 7] var [[a b] a])` (a plain List)
  → `dynamic-scope def `a` of unknown provenance`. What compiles:
  `pop q drop` (shrink), index reads/writes, and `pop xs var [[a b] a]`
  over a List inside a fn.

- **D4 — a cyclic `flex` structure crashes the process.**
  ```boru
  def a (flex {v: 1})
  def _1 (a set self a)
  print (do [ a deq a ] error [ "caught" ])
  ```
  → Go `fatal error: stack overflow`, exit 2 — not catchable, and the
  same for `print (a)` over a two-node cycle and `StructUtil.jsonify`.
  This is why DESIGN §5 forbids node links (now more firmly).

- **D5 — the `clock` policy scope does not gate `TimeUtil.now`.**
  ```boru
  import "boru:time-util"
  print (TimeUtil.now)
  ```
  run with `boru -deny-global clock …` or
  `-perms-inline '{version:1,scopes:{clock:{install:false}}}'` still
  prints the wall clock (the time module falls back to the wall clock
  when no clock capability is installed), although PERMISSIONS.10.md
  binds the global `clock` cap to `clock.now`. The import gate does
  refuse it (the `gen` profile denies `import "boru:time-util"`).

### Other notes from re-verifying DESIGN.md

- `set` quotes a bare word key — `ent set key v` stores under `"key"` —
  while `get`/`has` evaluate theirs (boru NUR040, Allowed). A cache's
  keys are always computed: write `ent set (key) v`.
- `while [cond] [body]` exists (since 2026-08-21); `min`/`max` are no
  longer reserved names; `base` and `take` are.
- A run is capped at 10,000,000 evaluation steps by default
  (`[boru/evaluation_limit]`, raise with `-options steps:N`); a `for`
  body that updates a flex cell costs over ten steps per iteration.
- `boru:rand` gives time-seeded randomness (`Rand.with-seed` for a fixed
  seed), so "boru has no ambient randomness" (DESIGN §6) was inaccurate.
