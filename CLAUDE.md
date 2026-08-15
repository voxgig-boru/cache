# CLAUDE.md

This repository is the `Bloom` bloom-filter library, written in boru.

## Using the library

See @AGENTS.md for how to call the `Bloom` API correctly from boru — the
calling convention, the full API, copy-paste idioms, and the common
mistakes to avoid. Every example there is verified against the pinned
`boru` build.

## Working on this repository

- A SessionStart hook (`.claude/settings.json` →
  `.claude/hooks/session-start.sh`) builds `boru` from the pinned commit in
  remote sessions, so a fresh session can run the suites. Locally, build it
  once from source (there is no tagged release and `go install …/aql@latest`
  is blocked by replace directives) — see
  [docs/how-to.md](docs/how-to.md#install-and-run-aql).
- Tests live in `test/`, named `<subject>_<unit|prop>_<test|spec>.aql` plus a
  `bloom_smoke_test.aql`: `_test` = imperative (`Test.test`/`Test.check-prop`),
  `_spec` = declarative spec; `unit` = example-based, `prop` = property-based.
  Each assertion-bearing suite ends by asserting `Test.fail-count` is `0` and
  prints `all green`.
- `test/divergence/run.sh` runs every suite through all three boru surfaces —
  interpreter, `boru check`, and the byte compiler (`boru --compile`) — and
  asserts none errors or disagrees. It builds a newer boru than this module's
  pin, since the `--compile` CLI postdates it. See its `README.md`; the
  byte-compiler bug it guards against is `dx-report.md` §3.
- Known boru-runtime gotchas observed with the pinned build are in
  `dx-report.md`. The pinned boru commit is single-sourced in the CI workflow's
  `BORU_REF` (`.github/workflows/test.yml`); a CI `consistency` job fails if the
  hook, `test/divergence/run.sh`, or `api.json` drift from it.
- Forking this repo to start a new boru library? See `TEMPLATE.md`.
