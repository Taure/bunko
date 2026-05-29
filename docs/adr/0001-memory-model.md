# 1. Memory model

Date: 2026-05-29

## Status

Accepted (v0.1).

## Context

Agents need memory the orchestration runtime does not give them: long-term facts
that persist across runs, and semantic retrieval (RAG) of the most relevant
context for a query. No BEAM library provides this. pgvector is the natural
store, and embeddings need a model - which, like every other client in this
stack, should be the caller's, not bundled.

## Decision

Three behaviours, a pgvector store, and a small API. Nothing bundles an
embedding or LLM client; deterministic stubs keep CI offline.

### Behaviours

```erlang
%% bunko_embedder - text to a fixed-dimension vector.
-callback embed(binary(), Opts :: map()) -> {ok, [float()]} | {error, term()}.

%% bunko_summarizer - merge several memory contents into one (consolidation).
-callback summarize([binary()], Opts :: map()) -> {ok, binary()} | {error, term()}.

%% bunko_store - persistence + namespaced similarity search.
-callback put(memory(), Opts :: map()) -> {ok, id()} | {error, term()}.
-callback search(namespace(), [float()], K :: pos_integer(), Opts :: map()) ->
    {ok, [hit()]} | {error, term()}.
-callback delete([id()], Opts :: map()) -> ok | {error, term()}.
-callback all(namespace(), Opts :: map()) -> {ok, [memory()]} | {error, term()}.
```

`bunko_embedder_stub` hashes text into a deterministic `embedding_dim`-length
vector; `bunko_summarizer_stub` concatenates. Real implementations wrap
gakudan_llm, sekisho, or a vendor SDK.

### Store: pgvector via kura

The shipped `bunko_store_pgvector` uses a kura repo (the caller's) and raw SQL
(kura has no `vector` type). The base table (`bunko_memories`: id, namespace,
content, metadata, timestamps) is a kura schema and its migration is generated.
A second migration carries the pgvector-specific DDL via the `{execute, SQL}`
op: `CREATE EXTENSION vector`, `ALTER TABLE ... ADD embedding vector(N)`, and an
HNSW cosine index. `N` is read from `{bunko, embedding_dim}` in the migration's
`up/0`, so the column matches whatever embedder (and stub) the deployment uses.

`put` and `search` are raw `Repo:query/2` calls: insert with a vector literal,
select `ORDER BY embedding <=> $1 LIMIT k` (cosine distance). A hit carries the
memory plus its distance.

### API

```erlang
bunko:remember(Ctx, Content, Metadata) -> {ok, id()} | {error, term()}.
bunko:recall(Ctx, Query, Opts) -> {ok, [hit()]} | {error, term()}.
bunko:consolidate(Ctx, Opts) -> {ok, stats()} | {error, term()}.
```

`Ctx` bundles the store ref, embedder ref, namespace, and (for consolidate) a
summarizer ref. `remember` embeds then stores; `recall` embeds the query then
searches; `consolidate` groups memories whose pairwise similarity exceeds a
threshold, summarizes each group into one memory (re-embedded), and replaces the
originals - so accumulated memories stay bounded and deduplicated.

## Consequences

**Positive.**

- Agents get long-term + semantic memory on the BEAM; runtime-agnostic, so any
  app benefits.
- Client-free core: CI is deterministic and offline via the stubs; real
  embedders/summarizers plug in without bunko taking a dependency.
- pgvector through kura's `{execute}` op needs no kura changes.

**Negative.**

- The embedding dimension is fixed per deployment (a pgvector + HNSW
  requirement); changing models means a re-embed + migration.
- Consolidation quality depends on the summarizer (the caller's) and the
  similarity threshold; a poor threshold over- or under-merges.
- Only a pgvector store ships in v0.1; the behaviour is the seam for others
  (sqlite-vec, etc.) later. Hybrid search and reranking are deferred.
