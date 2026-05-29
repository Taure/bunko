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
ships no embedding or LLM client: you plug in an `bunko_embedder` and (for
consolidation) a `bunko_summarizer`, with deterministic stubs for offline tests.

## How it works

```erlang
%% Configure a store (a kura repo + namespace) and an embedder.
Store = {bunko_store_pgvector, #{repo => myapp_repo}},
Embedder = {my_embedder, #{model => ~"text-embedding-3-small"}},
Ctx = #{store => Store, embedder => Embedder, namespace => ~"agent:42"},

%% Remember a fact.
{ok, _Id} = bunko:remember(Ctx, ~"the user prefers metric units", #{source => chat}),

%% Recall the most relevant memories for a query (top-k cosine).
{ok, Hits} = bunko:recall(Ctx, ~"what units should I use?", #{limit => 5}),

%% Periodically compact: merge near-duplicate memories via a summarizer.
{ok, _Stats} = bunko:consolidate(Ctx#{summarizer => {my_summarizer, #{}}}, #{threshold => 0.9}).
```

## Behaviours

| Behaviour | Role |
| --- | --- |
| `bunko_store` | persist a memory + namespaced top-k similarity search |
| `bunko_embedder` | text -> embedding vector |
| `bunko_summarizer` | merge several memories into one (consolidation) |

The shipped store is `bunko_store_pgvector` (kura + pgvector). Embedder and
summarizer have deterministic stubs (`bunko_embedder_stub`,
`bunko_summarizer_stub`); real ones are the caller's (wrap gakudan_llm, sekisho,
or a vendor SDK).

## Status

v0.1 in development. The embedding dimension is configured via
`{bunko, [{embedding_dim, N}]}` (read by the migration and matched by the stub).

Deferred: hybrid keyword+vector search, reranking, automatic extraction from
transcripts, alternative stores.

## License

MIT.
