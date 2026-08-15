# Performance baseline — `Bloom` on compiled boru

Baseline captured against `boru-lang/boru` `main` (branch
`claude/voxgig-boru-baseline-m2nct6`), the build on which the library and **all
five** of its test suites run **fully bytecode-compiled** (`boru
--force-compile`) with no refusals — verified byte-identical to the
interpreter. See `aql-full-compilation-prompt.md` for the compilation work that
made this possible.

The headline number is the compiled-vs-interpreted speedup on the library's hot
path (hashing + bit operations under `Bloom.add` / `Bloom.contains`). Method:
best-of-N wall-clock, process+startup overhead (~24 ms) subtracted where noted.

## Core workload — 3 000 `Bloom.add` + 3 000 `Bloom.contains`

`{n: 5000, p: 0.01}` filter; insert 3 000 keys, then query the same 3 000
(all present — no false negatives), best-of-3:

| surface | work time | speedup |
|---|---:|---:|
| interpreter (`--no-compile`) | ~16 788 ms | 1.00× |
| **compiled (`--force-compile`)** | **~825 ms** | **20.4×** |

The ~20× gap is the per-token interpreter dispatch overhead removed by lowering
the double-hashing index loop and the bit-set/bit-test inner loops to bytecode.

## Per-suite wall-clock (best-of-3)

| suite | interp (ms) | compiled (ms) | speedup |
|---|---:|---:|---:|
| `bloom_unit_test.aql`  | 3 502 | 503 | 6.96× |
| `bloom_smoke_test.aql` | 1 167 | 258 | 4.52× |
| `bloom_unit_spec.aql`  | 1 105 | 304 | 3.63× |
| `bloom_prop_test.aql`  | 2 885 | 2 849 | 1.01× |
| `bloom_prop_spec.aql`  | 8 642 | 8 195 | 1.05× |

The example-based suites (`unit_test`, `smoke`, `unit_spec`) speed up 3.6–7×
because most of their time is spent in library operations. The property suites
(`prop_test`, `prop_spec`) barely move: their wall-clock is dominated by the
`boru:test` property framework (generation, shrinking, fixed run counts), not by
the library code the compiler accelerates.

## Reproducing

```bash
# fully-compiled core workload
boru --force-compile <(cat <<'EOF'
import "./bloom.aql"
def bf ({n: 5000, p: 0.01} Bloom.make)
def _add  (iota 3000 each [ var [[i] (bf Bloom.add (convert String i)) 0 ] ])
def hits  (iota 3000 each [ var [[i] if (bf Bloom.contains (convert String i)) [1] [0] ] ])
print (0 hits [add end] fold)          # => 3000 (no false negatives)
EOF
)

# per-suite: compare the two surfaces
for s in test/*.aql; do
  time boru --no-compile   "$s" >/dev/null
  time boru --force-compile "$s" >/dev/null
done
```

Numbers are indicative (single machine, wall-clock); treat the *ratios* as the
baseline, not the absolute milliseconds.
