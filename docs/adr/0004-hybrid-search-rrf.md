# 4. Hybrid keyword + vector search

Date: 2026-06-01

## Status

Accepted. Supersedes the "hybrid search deferred" stance of ADR 0001.

## Context

ADR 0001 deferred hybrid search. In practice pure vector recall misses exact
terms - identifiers, rare proper nouns, error codes, acronyms - that a keyword
search nails and an embedding blurs. The reverse is also true: keyword search
misses paraphrase. Agent memory wants both.

The deferral assumed hybrid search meant a second engine. It does not: Postgres
ships full-text search (`tsvector` / `ts_rank_cd`) in the same database as
pgvector. Both lanes run in one query against one table - no new dependency, no
second store. That removes the reason for deferring, so we reconsider.

## Decision

Add an opt-in hybrid path to `bunko_store_pgvector:search/5`, selected by
`#{hybrid => true, text => Query}` in the query map (`bunko:recall/3` sets these
when given `hybrid => true`).

One SQL statement, two CTEs:

- **vec** - the cosine lane: the namespace's rows ordered by `embedding <=> q`,
  `row_number()` as rank, limited to a candidate pool.
- **kw** - the keyword lane: rows matching
  `to_tsvector('english', content) @@ plainto_tsquery('english', $3)`, ranked by
  `ts_rank_cd`, same pool.

The lanes are fused by **Reciprocal Rank Fusion**: each contributes
`1 / (rrf_k + rank)`, summed, and the result is ordered by that sum. RRF needs
no score calibration between the (incomparable) cosine and `ts_rank_cd` scales -
it uses only ranks. `rrf_k` (default 60) and `rrf_pool` (default `4 * limit`)
are tunable via the query map.

`install/1` now also creates a GIN index on `to_tsvector('english', content)`.
The query works without it (sequential `to_tsvector`); the index just makes the
keyword lane fast.

The text query is bound (`$3`) and goes through `plainto_tsquery` - never
concatenated into SQL. The vector literal stays inlined as before.

## Consequences

**Positive.**

- Exact-term recall (identifiers, codes) alongside semantic recall, in one
  round-trip, no new store.
- RRF needs no per-lane score normalisation and is robust to outliers.
- Opt-in: plain recall is unchanged and pays nothing for FTS.

**Negative.**

- The text analyzer is fixed to `'english'`. Other languages need a different
  configuration; a per-call analyzer is a future option.
- RRF weights both lanes equally; a lane-weighted fusion is possible later but
  adds tuning surface.
- The GIN index adds write cost and storage; acceptable for a memory store whose
  reads dominate.
