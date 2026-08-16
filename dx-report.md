# DX report — boru runtime gotchas

Project-specific boru gotchas hit while building **this** library.

**Empty so far** — nothing is implemented yet.

One measurement taken while designing is worth repeating here because it
shaped the whole library: **map reads cost ~63µs and writes ~3µs on the
interpreter, both O(1)** — a ~20× asymmetry, identical for plain maps,
flex maps and `has`. See [DESIGN.md](DESIGN.md) §2 and its appendix. The
likely suspect is the polymorphic accessor dispatch path rather than the
map itself; it is worth a profile upstream, and improving it would widen
what this library is good for.

The other constraints already known to apply (quadratic immutable-Map
accumulation, the two-value `pop`/`shift` trap, the `for`/`each` body
arity rules, non short-circuiting `and`/`or`, reserved names) are
recorded in DESIGN.md §9.
