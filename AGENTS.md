# AGENTS.md

Working agreement for agents and contributors on **bunko** (文庫, "archive") -
agent memory and semantic retrieval for the BEAM. A small OTP library:
behaviours + a pgvector adapter, bring-your-own embedder, no DSL.

## Ecosystem

A gakudan sister library in a BEAM-native multi-agent stack (all under
https://github.com/Taure):

- **[gakudan](https://github.com/Taure/gakudan)** - agent orchestration runtime.
- **[saiten](https://github.com/Taure/saiten)** - runtime-agnostic eval/scoring
  + CI gate.
- **[madoguchi](https://github.com/Taure/madoguchi)** - MCP *server* framework.
- **[sekisho](https://github.com/Taure/sekisho)** - LLM gateway / control plane:
  virtual keys, budgets, and audit in front of Anthropic + OpenAI (chat and
  embeddings) + Vertex.
- **bunko** - agent memory + RAG: a pgvector-backed store, an embedder seam, and
  memory consolidation.
- **[banto](https://github.com/Taure/banto)** - multi-agent repo concierge; the
  showcase consumer that wires the pillars together.

Other gakudan sisters: gakudan_metrics, gakudan_otel, gakudan_tickets
(+ gakudan_tickets_github), gakudan_liveboard (Nova + Datastar dashboard).

**This repo** is the memory layer. Runtime-agnostic on purpose (like saiten): any
BEAM app uses it. The gakudan integration (recall as a tool / auto-injected
context) is a documented follow-up, not a dependency.

## Design pillars

- **Behaviours, not a framework.** `bunko_store` (persist + similarity search),
  `bunko_embedder` (text -> vector), `bunko_summarizer` (merge memories).
- **Bring-your-own client.** No embedding or LLM client ships in bunko - plug
  one in (wrap gakudan_llm / sekisho / a vendor SDK). A deterministic stub backs
  each behaviour so CI is offline and reproducible. Same earned-demand principle
  as saiten's judge and gakudan's backends.
- **pgvector via kura.** The shipped store uses kura + pgvector; vector ops go
  through raw SQL (kura has no `vector` type). The embedding dimension is config
  (`bunko, embedding_dim`), read by the migration and matched by the stub.

## Scope - what belongs here

- **In:** the behaviours + stubs (`bunko_store`, `bunko_embedder`,
  `bunko_summarizer`); the pgvector store adapter; `remember` / `recall`
  (namespaced top-k cosine, metadata filter, distance threshold,
  recency/importance reranking, optional hybrid keyword+vector RRF);
  `consolidate` (dedup + summarize similar memories).
- **Out (deferred):** automatic memory extraction from transcripts, alternative
  stores (sqlite-vec), multi-tenancy beyond a namespace string.

## Commands

```bash
docker compose up -d        # pgvector Postgres for kura (port 5557)
rebar3 compile
rebar3 eunit
rebar3 ct                   # against Docker pgvector Postgres
rebar3 fmt                  # CI runs fmt --check
rebar3 xref
rebar3 dialyzer
rebar3 ex_doc
```

## Conventions

- OTP 29+. The `~"..."` sigil, never `<<"...">>`. No `lists:foldl/foldr`.
- JSON via the OTP `json` module. `?LOG_*` macros with `#{...}` map reports.
- Migrations generated with `rebar3 kura`; pgvector-specific DDL (extension,
  `vector` column, index) uses the `{execute, SQL}` migration op.
- `{vsn, "git"}` - version derives from git tags. Default to zero comments.

## Decisions live in ADRs

Read [docs/adr/](docs/adr/) before changing a behaviour, the schema, or the
retrieval/consolidation contract. Write a new ADR for any such change.

## Git and PRs

Conventional commits. Always open a PR - never push to `main`. Every merge to
`main` tags a release.
