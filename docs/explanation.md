# Explanation

> **Status: the library is designed, not implemented.** `cache.aql`
> exports an empty `Cache` namespace, so there is no API to document
> yet. See **[DESIGN.md](../DESIGN.md)** for the argued plan.

The design rationale currently lives in full in [DESIGN.md](../DESIGN.md) — why this is an effect memoizer rather than a general-purpose cache, why the default eviction policy is SIEVE rather than LRU, and why the library never reads the clock.
