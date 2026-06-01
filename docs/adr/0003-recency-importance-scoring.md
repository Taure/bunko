# 3. Recency and importance scoring

Date: 2026-06-01

## Status

Accepted.

## Context

Pure cosine search returns the semantically nearest memories, but agent memory
is not just a vector index. A fact learned a minute ago usually matters more
than an equally-similar one from a month ago, and some memories are explicitly
more important than others (a user's stated preference vs. an offhand remark).
ADR 0002 made hits carry `age_seconds`; the metadata jsonb can carry an
`importance`. Neither influenced ordering.

This is the difference between a RAG index and *memory*: relevance is a blend of
similarity, recency, and salience. It must not require an LLM - it has to be
cheap enough to run on every recall.

## Decision

Add `bunko_score`, a deterministic reranker over recall hits:

```
score = alpha * recency + beta * importance + gamma * similarity
```

- `recency = exp(-age_seconds / half_life * ln 2)` - exponential decay; a memory
  one half-life old scores `0.5`. `age_seconds` comes from the hit (computed in
  SQL). Missing age means recency `1.0`.
- `importance` = the `importance` metadata value (binary key), clamped to
  `[0, 1]`; absent/non-numeric -> `0.0`.
- `similarity = 1 - distance` (cosine distance to similarity).

Weights and `half_life_seconds` are options; defaults are `0.2 / 0.2 / 0.6` with
a one-week half-life. `bunko_score:rerank/2` returns the hits sorted by score
(descending), each carrying its `score`.

This is opt-in from `recall` via `#{rerank => recency, rerank_weights => W}`.
Without it, recall returns pure cosine order as before. Reranking happens in the
BEAM over the already-fetched top-k - no extra query.

## Consequences

**Positive.**

- Recall behaves like memory, not just an index, with no model and no extra
  round-trip.
- Weights are tunable per call; the default still favours similarity, so the
  blend never drowns relevance.
- `importance` gives the caller a salience lever (mark a memory important and it
  surfaces sooner for longer).

**Negative.**

- Reranking only reorders the top-k the vector search already returned: a highly
  recent/important but semantically distant memory outside the top-k is never
  seen. Callers who want recency to override similarity must widen `limit`.
- `importance` is the caller's convention (a metadata key); bunko does not set
  or validate it beyond clamping.
