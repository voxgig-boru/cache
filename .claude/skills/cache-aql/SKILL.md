# Cache (boru) — status

**This library is DESIGNED, NOT IMPLEMENTED.** `cache.aql` exports an
empty `Cache` namespace. There is no word to call.

If you are trying to use a caching or memoization API from boru: it does
not exist yet. Do not invent one.

Re-verified against boru main @ `64c5ab2` (2026-10-01).

## The design

`DESIGN.md` at the repository root is the substance. Three rulings you
would otherwise get wrong:

**A cache only pays over work dearer than a lookup.** On boru main a map
read costs ~1–3us and a cache-shaped lookup ~10us (DESIGN.md §2,
re-measured; it was ~63us on the old interpreter). Caching work cheaper
than that makes the program *slower*. Wrap network calls, file reads and
expensive parses — never arithmetic.

**Default eviction will be SIEVE, not LRU.** A textbook LRU needs a
doubly-linked list, which boru cannot express well (a cyclic `flex`
structure crashes `print`/`jsonify`/`deq`); CLOCK/SIEVE need only an
array and a hand, and beat LRU on hit rate.

**No `memoize` word yet — by scope, not by defect.** The free-word scope
defect that once blocked it is fixed upstream (boru `7e98aeb`). Pass any
function as data with `f/v`: a bare name holding a function calls.

## Calling convention (fixed)

Forward args, receiver (the cache) LAST: `Cache.verb …args c`. Piping
(`c Cache.verb …args`) binds identically; only receiver-first-all-forward
misbinds. Import with `import "./cache.aql"`, resolved against the
importing file's own directory (`"../cache.aql"` from `test/`).
