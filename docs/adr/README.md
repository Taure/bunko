# Architecture Decision Records

The decision log for bunko. Each ADR captures the *why* behind a behaviour, the
schema, or the retrieval/consolidation contract.

## When to write one

Write a new ADR for any new behaviour, a schema/migration change, or a change to
the retrieval or consolidation contract. Small fixes that preserve contracts do
not need one.

Use the [Nygard format](https://github.com/joelparkerhenderson/architecture-decision-record):
**Context**, **Decision**, **Consequences**. Number sequentially; never rewrite
a merged ADR - supersede it.

## Index

| ADR | Title |
| --- | --- |
| [0001](0001-memory-model.md) | Memory model |
| [0002](0002-query-time-retrieval-options.md) | Query-time retrieval options |
| [0003](0003-recency-importance-scoring.md) | Recency and importance scoring |
