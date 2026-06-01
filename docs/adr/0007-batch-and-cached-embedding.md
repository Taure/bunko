# 7. Batch and cached embedding

Date: 2026-06-01

## Status

Accepted.

## Context

`remember` embeds one content at a time. Two costs follow. First, embedding APIs
are dramatically cheaper per item in bulk (one request for N texts vs. N
requests), so storing many memories at once should batch. Second, identical
content is re-embedded every time it is seen - wasteful when the same fact, doc
chunk, or message recurs, and embedding is the dominant latency and dollar cost
in the pipeline.

`bunko_embedder` had only `embed/2`. There was no batch entry point and no
memoization.

## Decision

**Batch.** Add an optional `embed_many/2` callback to `bunko_embedder`:

```erlang
-callback embed_many([binary()], Opts :: map()) -> {ok, [vector()]} | {error, term()}.
-optional_callbacks([embed_many/2]).
```

`bunko_embedder:embed_many/2` uses it when the module exports it, and otherwise
falls back to mapping `embed/2` - so every existing embedder keeps working. A new
`bunko:remember_many/2` takes `[{Content, Metadata}]`, embeds the whole batch in
one call, and stores each (best-effort, per-item store, ids returned in order).

**Cache.** Add `bunko_embed_cache`, a content-hash cache backed by a lazily
created public ETS table. The key is `{Module, Opts (minus the cache flag),
sha256(content)}`, so embedders and their configurations never collide. It is
enabled per embedder ref with `cache => true`; `embed/2` and `embed_many/2` then
serve hits from the cache and only send misses to the embedder (the batch path
dedups misses first).

No eviction policy ships: the cache is best-effort and lives for the node's
lifetime, with `clear/0` for callers that churn distinct content. Caching is off
by default.

## Consequences

**Positive.**

- Bulk ingestion is one embedding request, not N; recurring content is embedded
  once. Both cut the pipeline's dominant cost.
- `embed_many/2` is optional, so no existing embedder breaks; the fallback is
  transparent.
- The cache is process-independent and needs no supervision, fitting the
  library-not-application ethos.

**Negative.**

- The cache has no eviction; unbounded distinct content grows ETS until
  `clear/0` or node restart. Off by default, and documented, so it is the
  caller's deliberate choice.
- `remember_many/2` stores per-item and is not atomic; a mid-batch store error
  leaves earlier items written (same best-effort contract as `consolidate`).
- The cache key trusts `Opts` to capture everything that changes an embedding;
  an embedder whose output depends on hidden state would cache incorrectly.
