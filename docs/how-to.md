# How-to guides

> **Status: the library is designed, not implemented.** `cache.aql`
> exports an empty `Cache` namespace, so there is no API to document
> yet. See **[DESIGN.md](../DESIGN.md)** for the argued plan.

Task recipes will appear here as words land. The first one to write is **"decide whether a cache helps"** — see [DESIGN.md](../DESIGN.md) §2 and §8; it is the recipe this library most needs.

## Install and run boru

boru has no tagged release, and `go install …/cmd/go/boru@latest` is
blocked by the replace directives in `cmd/go/go.mod`, so build it from a
source checkout of **main** (this repo tracks main; last verified against
boru main @ `64c5ab2`, 2026-10-01):

```bash
git clone https://github.com/boru-lang/boru
cd boru/cmd/go && go build -o ~/.local/bin/boru ./boru
```

The CLI module is `cmd/go`; its thin `main` package is `cmd/go/boru`,
which is why the build target is `./boru`. (The SessionStart hook and CI
build a standalone source tree with `GOWORK=off GOFLAGS=-mod=mod`.)

Then from this repository's root:

```bash
boru test/cache_smoke_test.aql
```

`boru X` runs a static pre-flight check, then compiles the program to
bytecode and runs it on the VM — the only execution path since boru
2026-09-19. A check error blocks the run, and a compiler defect fails it
with `[boru/compile_failed]`; there is no interpreter fallback, and the
old `--compile` / `--force-compile` / `--no-compile` flags are usage
errors.

## Run the tests

```bash
for f in test/cache_*.aql; do boru "$f"; done
```

Every assertion-bearing suite ends by printing `all green`; the smoke
suite prints `--- ok ---`. The gate CI runs — every suite exits 0 (and
prints `all green` where it asserts), and `boru check` reports 0 errors
on every suite and on `cache.aql` — is:

```bash
BORU=$(command -v boru) test/divergence/run.sh
```

Without `BORU` it builds its own boru at main HEAD (see
[test/divergence/README.md](../test/divergence/README.md)).
