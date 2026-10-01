# Single-path gate: run · check

This library's suites are written once and must run clean on boru **main**.
`run.sh` holds every suite to two conditions:

```bash
boru X         # compile to bytecode + run on the VM — must exit 0, and an
               #   assertion-bearing suite must print `all green`
boru check X   # static check — must report 0 errors
```

and also checks the library module (`cache.aql`) standalone for 0 errors.

## Why it is no longer a three-way comparison

Until 2026-09 this harness compared three execution surfaces — the
interpreter (`boru X`), `boru check X` and the byte compiler
(`boru --compile X`, plus an informational `--force-compile` coverage line) —
and failed on any disagreement. That model is gone upstream:

- **There is one execution path.** Since boru 2026-09-19 a program is
  compiled to bytecode and run on the VM, or it fails with
  `[boru/compile_failed] … this is a compiler defect`. There is no
  interpreter fallback.
- **The flags are retired.** `--compile`, `--force-compile` and
  `--no-compile` are usage errors now (`flag provided but not defined`,
  exit 1); the `BORU_COMPILE` / `BORU_FORCE_COMPILE` / `BORU_NO_COMPILE` env
  vars are retired too and are silently ignored.
- **`boru X` runs the check first.** A pre-flight `boru check` error blocks
  the run (`-no-check` skips it; this harness never uses it).

So "the suite runs" now means "the suite fully compiles", and the only two
surfaces left to gate are the run and the check. The directory keeps its old
name so the CI job and the docs that call `test/divergence/run.sh` keep
working.

## Running it

```bash
test/divergence/run.sh                              # build boru @ main HEAD (cached), then gate
BORU=$HOME/.local/bin/boru test/divergence/run.sh   # use an existing binary, no build
BORU_REF=64c5ab2 test/divergence/run.sh             # build a specific ref
```

Without `BORU`, the script builds its own boru so it never depends on what is
on `PATH`: it resolves `boru-lang/boru` main HEAD, fetches the source as a
codeload tarball (works where a raw `git clone` is blocked), builds
`cmd/go` → `./boru`, and caches the binary under `~/.cache/boru-divergence`
keyed by the SHA (it rebuilds only when main advances). Needs `go` + network
for that one-time build. `BORU_TIMEOUT` (default 600) caps each invocation.

Sample output (boru main @ 64c5ab2, 2026-10-01):

```
[divergence] suites — run (boru X) must exit 0 [+ print 'all green'], check must report 0 errors:
  SUITE                       RUN                     CHECK         SECONDS
  cache_unit_test.aql         ok                      ok            0
  cache_unit_spec.aql         ok                      ok            0
  cache_prop_test.aql         ok                      ok            0
  cache_prop_spec.aql         ok                      ok            0
  cache_smoke_test.aql        ok                      ok            0

[divergence] modules — boru check must report 0 errors:
  cache.aql                   ok

[divergence] PASS — every suite compiles, runs green, and checks clean; every module checks clean.
```

The library is **designed, not implemented** (`cache.aql` exports an empty
`Cache` namespace), so the suites are placeholders: they import the module,
and the four assertion-bearing ones assert `Test.fail-count` is `0` and print
`all green`. Each suite `boru check`s with 0 errors and one advisory info
(`module_body_executed_in_check` — the checker runs an imported module's body
to type its exports; expected, not a defect).

## What changed for the suites on boru main

- **Relative imports anchor on the importing file.** The suites in `test/`
  import `"../cache.aql"`. The old `"./cache.aql"` points at a missing
  `test/cache.aql`, which boru main does *not* report as a missing file: the
  check degrades the import to an opaque module and the compile pass then
  fails with `[boru/compile_failed] … residual value of unknown provenance`
  and no source position (see `dx-report.md`).
- **The library is imported before `boru:test`.** `boru:test` mints its record
  types from a fresh type-ID counter, so a library class imported after it can
  collide with one of them (`expected X, got X`). There is no class yet, but
  the order is fixed now so the first implemented word does not trip it.
- **The summary prints one value per statement** (`print ("…")`) and asserts
  with the forward `Assert.equal 0 (Test.fail-count)` (expected first): a
  postfix `"x" print` chain collects forward and prints out of order.

### Wiring it into CI

`.github/workflows/test.yml` already runs this script in its `divergence` job
(`run: test/divergence/run.sh`), so the job picked up the single-path gate
without a workflow edit; only the job's step name still says
"interpreter / check / byte-compiler agreement".
