# bunko

[![CI](https://github.com/Taure/bunko/actions/workflows/ci.yml/badge.svg)](https://github.com/Taure/bunko/actions/workflows/ci.yml)
[![OTP](https://img.shields.io/badge/OTP-29%2B-blue)](https://www.erlang.org)
[![License: MIT](https://img.shields.io/badge/License-MIT-green.svg)](https://github.com/Taure/bunko/blob/main/LICENSE)

**文庫** ("archive") - agent memory and semantic retrieval for the BEAM.

bunko gives agents long-term memory and RAG: store text with an embedding,
recall the most relevant memories for a query, and consolidate accumulated
memories so they don't grow unbounded. It is runtime-agnostic - any BEAM app
uses it, not just [gakudan](https://github.com/Taure/gakudan).

The store is pgvector-backed (via [kura](https://github.com/Taure/kura)). It
ships no embedding or LLM client: you plug in a `bunko_embedder` and (for
consolidation) a `bunko_summarizer`, with deterministic stubs for offline tests.

## How it works

```erlang
%% Configure a store (a kura repo), an embedder, and a namespace.
Store = {bunko_store_pgvector, #{repo => myapp_repo}},
Embedder = {my_embedder, #{model => ~"text-embedding-3-small"}},
Ctx = #{store => Store, embedder => Embedder, namespace => ~"agent:42"},

%% Remember a fact.
{ok, _Id} = bunko:remember(Ctx, ~"the user prefers metric units", #{source => chat}),

%% Recall the most relevant memories for a query (top-k cosine).
{ok, Hits} = bunko:recall(Ctx, ~"what units should I use?", #{limit => 5}),

%% Scope recall by metadata and reject semantically distant hits.
{ok, Scoped} = bunko:recall(Ctx, ~"what units should I use?", #{
    limit => 5,
    filter => #{<<"source">> => <<"chat">>},
    max_distance => 0.35
}),

%% Rerank by recency + importance + similarity (no model needed).
{ok, Ranked} = bunko:recall(Ctx, ~"what units should I use?", #{
    rerank => recency,
    rerank_weights => #{alpha => 0.3, beta => 0.2, gamma => 0.5}
}),

%% Hybrid: fuse a keyword (tsvector) lane with the vector lane via RRF.
{ok, Fused} = bunko:recall(Ctx, ~"metric units error E42", #{hybrid => true}),

%% Plug in a custom reranker as an optional second stage.
{ok, Reranked} = bunko:recall(Ctx, ~"what units?", #{
    rerank => {my_reranker, #{}},
    rerank_opts => #{}
}),

%% Periodically compact: merge near-duplicate memories via a summarizer.
{ok, _Stats} = bunko:consolidate(Ctx#{summarizer => {my_summarizer, #{}}}, #{threshold => 0.9}).
```

## Behaviours

| Behaviour | Role |
| --- | --- |
| `bunko_store` | persist a memory + namespaced top-k similarity search |
| `bunko_embedder` | text -> embedding vector |
| `bunko_summarizer` | merge several memories into one (consolidation) |
| `bunko_reranker` | optional second-stage reordering of recall hits |

The shipped store is `bunko_store_pgvector` (kura + pgvector). Embedder,
summarizer, and reranker have deterministic stubs (`bunko_embedder_stub`,
`bunko_summarizer_stub`, `bunko_reranker_stub`); real ones are the caller's
(wrap gakudan_llm, sekisho, or a vendor SDK). `bunko_reranker_score` is a
built-in reranker over the recency/importance scorer.

## Schema setup

kura discovers migrations through the consuming app, so a consumer's repo cannot
auto-apply bunko's migrations. Provision the schema with `install/1` (idempotent;
safe to call on every boot) after setting the embedding dimension:

```erlang
application:set_env(bunko, embedding_dim, 1536),
ok = bunko_store_pgvector:install(#{repo => myapp_repo}).
```

This creates the `vector` extension, the `bunko_memories` table, and the cosine
(HNSW) index in your repo.

## Status

v0.1. The embedding dimension is configured via `{bunko, [{embedding_dim, N}]}`
(used by `install/1` and matched by the stub).

Recall supports metadata filtering, a distance threshold, recency/importance
reranking, and opt-in hybrid keyword+vector search (RRF). Deferred: automatic
extraction from transcripts, alternative stores.

## License

MIT.
