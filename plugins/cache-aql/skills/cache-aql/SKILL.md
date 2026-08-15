# Cache (boru) — status

**This library is DESIGNED, NOT IMPLEMENTED.** `cache.aql` exports an
empty `Cache` namespace. There is no word to call.

If you are trying to use a caching or memoization API from boru: it does
not exist yet. Do not invent one.

## The design

`DESIGN.md` at the repository root is the substance. Three rulings you
would otherwise get wrong:

**It is an effect memoizer, not a general-purpose cache.** A map read
costs ~63us on this runtime; a write ~3us. Caching work cheaper than a
lookup makes the program *slower*. Wrap network calls, file reads and
expensive parses — never arithmetic.

**Default eviction will be SIEVE, not LRU.** A textbook LRU needs a
doubly-linked list, which boru cannot express well; CLOCK/SIEVE need only
an array and a hand, and beat LRU on hit rate.

**No `memoize` word.** Passing a function into this library and invoking
it there hits boru's free-word scope defect
(`design/FUNCTION-VALUE-SCOPE.0.md`) — the function would lose its own
module's helpers or silently bind this library's.

## Calling convention (fixed)

Forward args, receiver (the cache) LAST: `Cache.verb …args c`. Piping
(`c Cache.verb …args end`) binds identically; only
receiver-first-all-forward misbinds.
