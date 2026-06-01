# 2. Query-time retrieval options

Date: 2026-06-01

## Status

Accepted.

## Context

ADR 0001 defined `recall` as namespaced top-k cosine search and nothing more.
The `bunko_memories` table already carries a `metadata` jsonb column and
`inserted_at` / `updated_at` timestamps, but search ignored them: every call
returned the k nearest neighbours in the namespace regardless of metadata, and
there was no way to reject hits that were semantically distant.

Agent memory needs both. A query is usually scoped ("only memories tagged
`source=chat`", "only this session") and a similarity floor matters: returning
the k nearest is meaningless when the nearest is still unrelated, which is how
irrelevant or poisoned context leaks into a prompt.

The store behaviour's `search/4` only received the store's *static* config
(`Opts`, e.g. the repo). There was nowhere to pass per-call retrieval tuning.

## Decision

Widen the search callback to carry a query-options map, separate from store
config.

```erlang
%% was: search(namespace(), [float()], K, Opts) -> {ok, [hit()]} | {error, _}.
-callback search(namespace(), [float()], K :: pos_integer(),
                 Query :: query(), Opts :: map()) ->
    {ok, [hit()]} | {error, term()}.
```

`query()` is an open map; v0.2 reads:

- `filter => map()` - a metadata containment filter, compiled to
  `metadata @> $N::jsonb`. The filter map is JSON-encoded and **bound** as a
  parameter (never inlined). Keys are matched as stored (binary keys).
- `max_distance => number()` - drop hits whose cosine distance
  (`embedding <=> query`) exceeds the threshold, applied in SQL as an extra
  `AND`. The bound is code-generated from a float, so it is inlined like the
  vector literal.

`bunko:recall/3` builds the query map from its `Opts` (`filter`, `max_distance`)
and threads it through. Both are optional; omitting them reproduces the old
top-k behaviour exactly.

Hits now also carry `age_seconds` (computed in SQL as
`extract(epoch from now() - inserted_at)`) when the store provides it, so later
stages (recency scoring) need no extra round-trip or timestamp parsing.

The vector literal stays inlined (pgo cannot bind a `vector` parameter; the
floats are code-generated). Everything else - the filter JSON, namespace, limit
- is a bound parameter.

## Consequences

**Positive.**

- Scoped, thresholded recall: the core primitive agent memory needs.
- A distance floor is a cheap relevance and safety control (bounds how much
  unrelated/poisoned context can surface).
- The `query()` map is the extension point for hybrid search, reranking hints,
  and future options without widening the arity again.

**Negative.**

- The `bunko_store` behaviour changed arity (`search/4` -> `search/5`). Any
  out-of-tree store implementation must update its callback. This is a
  pre-1.0 break, taken deliberately and documented here.
- The metadata filter relies on the jsonb `@>` containment operator; it matches
  containment, not arbitrary predicates (ranges, `OR`). Richer filtering is a
  later ADR if demand appears.
