#!/usr/bin/env bash
# Single-path gate: every suite must RUN clean and CHECK clean on boru main.
#
#   run    boru X         compile X to bytecode and run it on the VM. Since
#                         boru 2026-09-19 this is the ONLY execution path: a
#                         program compiles and runs, or it fails with
#                         `[boru/compile_failed] … this is a compiler defect`.
#                         `boru X` also runs the static pre-flight check, and a
#                         check error blocks the run (this harness never passes
#                         -no-check). A suite passes when it exits 0;
#                         assertion-bearing suites must also print `all green`.
#   check  boru check X   static check of the suite — must report 0 errors.
#
# The library module itself (cache.aql) is also checked standalone and must
# report 0 errors.
#
# Why there is no interpreter / `--compile` / `--force-compile` column any
# more: this harness used to assert that the interpreter, `boru check` and the
# byte compiler agreed. Upstream retired the interpreter fallback and the
# flags `--compile`, `--force-compile` and `--no-compile` — passing one is now
# a usage error ("flag provided but not defined", exit 1) — and the
# BORU_COMPILE / BORU_FORCE_COMPILE / BORU_NO_COMPILE env vars, which are now
# silently ignored. With one execution path there is nothing left to diverge
# from: "the suite runs" now MEANS "the suite fully compiles", so the gate is
# run + check. (The directory keeps its old name so the CI job and the docs
# that call test/divergence/run.sh keep working.)
#
# Binary selection:
#   BORU=/path/to/boru   use that binary as-is (no build, no network) — e.g.
#                        BORU=$HOME/.local/bin/boru test/divergence/run.sh
#   BORU_REF=<sha|ref>   build that boru-lang/boru ref (default: main HEAD,
#                        resolved at run time). AQL_BYTECODE_REF is honoured
#                        as a legacy alias.
# Otherwise the harness builds its OWN boru, so it never depends on whatever
# boru is on PATH: fetched as a source tarball from codeload.github.com (works
# where a raw `git clone` of boru-lang/boru is blocked), built from cmd/go as
# ./boru, cached under ~/.cache/boru-divergence by the resolved SHA (it
# rebuilds only when main advances). Needs `go` + network for that build.
# BORU_TIMEOUT (default 600) caps each boru invocation, in seconds.
set -uo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO="$(cd "$HERE/../.." && pwd)"

SUITES="
test/cache_unit_test.aql
test/cache_unit_spec.aql
test/cache_prop_test.aql
test/cache_prop_spec.aql
test/cache_smoke_test.aql
"
MODULES="
cache.aql
"
TIMEOUT="${BORU_TIMEOUT:-600}"

log() { echo "[divergence] $*"; }

# --- locate or build boru --------------------------------------------------
if [ -n "${BORU:-}" ]; then
  [ -x "$BORU" ] || { echo "error: BORU=$BORU is not an executable." >&2; exit 1; }
else
  BORU_REF="${BORU_REF:-${AQL_BYTECODE_REF:-}}"
  if [ -z "$BORU_REF" ]; then
    BORU_REF="$(git ls-remote https://github.com/boru-lang/boru.git main | cut -f1)"
  fi
  [ -n "$BORU_REF" ] || { echo "error: could not resolve boru main HEAD (network?); set BORU=/path/to/boru." >&2; exit 1; }
  CACHE="$HOME/.cache/boru-divergence"
  BORU="$CACHE/boru-$BORU_REF"
  if [ ! -x "$BORU" ]; then
    command -v go >/dev/null 2>&1 || { echo "error: Go toolchain not found (or set BORU=/path/to/boru)." >&2; exit 1; }
    log "building boru @ $BORU_REF (one-time; cached) …"
    src="$(mktemp -d)"
    curl -fsSL "https://codeload.github.com/boru-lang/boru/tar.gz/$BORU_REF" \
      | tar -xz -C "$src" --strip-components=1 || { echo "error: fetch/extract failed." >&2; exit 1; }
    mkdir -p "$CACHE"
    # cmd/go is the CLI library; its thin `main` package is cmd/go/boru, so
    # the build target is ./boru (that is what names the binary `boru`).
    ( cd "$src/cmd/go" && GOWORK=off GOFLAGS=-mod=mod go build \
        -ldflags "-X github.com/boru-lang/boru/cmd/go.Version=$BORU_REF" \
        -o "$BORU" ./boru ) || { echo "error: build failed." >&2; exit 1; }
    rm -rf "$src"
  fi
fi
log "boru: $BORU ($("$BORU" -version 2>&1))"
echo

# A host with no `timeout` binary (macOS without coreutils) runs uncapped.
tmo() { if command -v timeout >/dev/null 2>&1; then timeout "$TIMEOUT" "$@"; else "$@"; fi; }

# Error count from `boru check` output ("check: N error(s), …" on a clean or
# advisory-only run, "check failed: N error(s)" when it gates).
check_errors() {
  local out n
  out="$(tmo "$BORU" check "$1" 2>&1)"
  n="$(printf '%s\n' "$out" | grep -oE '^check: [0-9]+ error' | grep -oE '[0-9]+' | tail -1)"
  if [ -z "$n" ]; then
    n="$(printf '%s\n' "$out" | grep -oE 'check failed: [0-9]+ error' | grep -oE '[0-9]+' | tail -1)"
  fi
  echo "${n:-?}"
}

cd "$REPO"
fail=0

# --- suites: run (compiled, the only path) + check ------------------------
log "suites — run (boru X) must exit 0 [+ print 'all green'], check must report 0 errors:"
printf '  %-26s  %-22s  %-12s  %s\n' SUITE RUN CHECK SECONDS
for s in $SUITES; do
  name="$(basename "$s")"
  t0=$(date +%s)
  out="$(tmo "$BORU" "$s" 2>&1)"; rc=$?
  secs=$(( $(date +%s) - t0 ))
  needs_green=0
  grep -q 'Test.fail-count' "$s" && needs_green=1
  if [ $rc -eq 0 ] && { [ $needs_green = 0 ] || printf '%s\n' "$out" | grep -qx 'all green'; }; then
    r_col="ok"
  elif printf '%s\n' "$out" | grep -q 'boru/compile_failed'; then
    r_col="COMPILE_FAILED"; fail=1
  elif [ $rc -eq 124 ]; then
    r_col="TIMEOUT"; fail=1
  elif [ $rc -eq 0 ]; then
    r_col="FAIL(no all-green)"; fail=1
  else
    r_col="FAIL(rc=$rc)"; fail=1
  fi

  errs="$(check_errors "$s")"
  if [ "$errs" = 0 ]; then c_col="ok"; else c_col="FAIL($errs err)"; fail=1; fi

  printf '  %-26s  %-22s  %-12s  %s\n' "$name" "$r_col" "$c_col" "$secs"
  if [ "$r_col" != ok ]; then
    printf '%s\n' "$out" | grep -m1 -E 'error:|\[boru/|\[error\]' | cut -c1-240 | sed 's/^/      /'
  fi
done

# --- library modules: check standalone -------------------------------------
echo
log "modules — boru check must report 0 errors:"
for m in $MODULES; do
  errs="$(check_errors "$m")"
  if [ "$errs" = 0 ]; then c_col="ok"; else c_col="FAIL($errs err)"; fail=1; fi
  printf '  %-26s  %s\n' "$m" "$c_col"
done

echo
if [ "$fail" = 0 ]; then
  log "PASS — every suite compiles, runs green, and checks clean; every module checks clean."
else
  log "FAIL — a suite failed to compile/run/check, or a module failed check (see above)."
fi
exit $fail
