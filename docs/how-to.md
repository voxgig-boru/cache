# How-to guides

> **Status: the library is designed, not implemented.** `cache.aql`
> exports an empty `Cache` namespace, so there is no API to document
> yet. See **[DESIGN.md](../DESIGN.md)** for the argued plan.

Task recipes will appear here as words land. The first one to write is **"decide whether a cache helps"** — see [DESIGN.md](../DESIGN.md) §2 and §8; it is the recipe this library most needs.

## Install and run boru

```bash
git clone https://github.com/boru-lang/boru
cd boru/cmd/go && go build -o ~/.local/bin/boru ./boru
```

Then from this repository's root:

```bash
boru test/cache_smoke_test.aql
```

## Run the tests

```bash
for f in test/cache_*.aql; do boru "$f"; done
```
