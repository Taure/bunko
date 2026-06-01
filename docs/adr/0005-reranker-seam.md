# 5. Reranker seam

Date: 2026-06-01

## Status

Accepted.

## Context

ADR 0003 added an in-tree recency/importance scorer. The strongest retrieval
quality gains, though, come from a *reranker*: a second stage that re-scores the
first-stage candidates with a more expensive model (a cross-encoder, or an LLM
judging query/passage relevance). Like embedders and summarizers, that model is
the caller's, not bunko's.

bunko already has the BYO-behaviour-plus-deterministic-stub pattern for
`bunko_embedder` and `bunko_summarizer`. Reranking should follow it rather than
being a special-cased option.

## Decision

Add a `bunko_reranker` behaviour applied as an optional second stage after
recall:

```erlang
-callback rerank(Query :: binary(), [hit()], Opts :: map()) ->
    {ok, [hit()]} | {error, term()}.
```

A reranker receives the query and the first-stage hits and returns them
reordered (and possibly trimmed). bunko ships:

- `bunko_reranker_stub` - deterministic offline reference; reorders by how many
  query tokens appear in each hit's content, stable on ties.
- `bunko_reranker_score` - wraps the ADR 0003 scorer (`bunko_score`) behind the
  behaviour, so the built-in recency/importance blend is just one reranker.

`bunko:recall/3` applies a reranker via `#{rerank => Ref}`: `recency` is a
shortcut for `bunko_reranker_score`, and any reranker reference (`Module` or
`{Module, Opts}`) plugs in a custom one. Per-call options go under `rerank_opts`
(the `rerank_weights` key from ADR 0003 is still honoured for the recency
scorer). A reranker error is non-fatal: recall falls back to the first-stage
order rather than failing the whole call.

## Consequences

**Positive.**

- The highest-leverage retrieval-quality stage is now a first-class, swappable
  seam consistent with the rest of the library.
- The recency scorer is no longer a special case; it is one reranker among many.
- Offline CI stays deterministic via the stub; cross-encoder/LLM rerankers plug
  in without bunko taking a dependency.

**Negative.**

- A reranker only reorders the top-k the store returned; recall@k is still
  bounded by the first stage. Widen `limit` (or the hybrid pool) to give the
  reranker more to work with.
- Treating reranker errors as non-fatal trades a hard failure for silently
  degraded ordering; callers who need strict behaviour should call the reranker
  themselves.
