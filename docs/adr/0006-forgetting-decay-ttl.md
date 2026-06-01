# 6. Forgetting: TTL and idle expiry

Date: 2026-06-01

## Status

Accepted.

## Context

Memory that only grows is a liability. Stale facts crowd recall, consolidation
cost rises with table size, and - critically - a poisoned or incorrect memory
survives indefinitely. ADR 0003's recency scoring already *soft*-decays old
memories in ranking, but they remain in the store and can still surface. Agent
memory needs an actual forgetting mechanism, and a bound on how long any single
entry can live is a security control, not just housekeeping.

There was no notion of last access, so idle-based expiry was impossible: a memory
recalled every day looked identical in age to one never touched since insertion.

## Decision

Two complementary mechanisms.

**Soft decay** stays as-is: recency weighting in `bunko_score` (ADR 0003)
down-ranks old memories without deleting them.

**Hard forgetting** is new. Add a `last_accessed_at timestamptz` column
(`install/1` adds it idempotently with `ADD COLUMN IF NOT EXISTS`) and two store
operations, both optional callbacks on `bunko_store`:

```erlang
-callback expire(namespace(), Expiry :: map(), Opts :: map()) ->
    {ok, non_neg_integer()} | {error, term()}.
-callback touch([id()], Opts :: map()) -> ok | {error, term()}.
```

- `bunko:forget(Ctx, Expiry)` deletes memories in the namespace matching
  `max_age_seconds` (age since `inserted_at`) and/or `max_idle_seconds` (since
  `coalesce(last_accessed_at, inserted_at)`). Returns the count removed. A
  scheduled caller (any timer/cron in the host app) runs it as a sweep; bunko
  stays a library and ships no scheduler.
- `recall/3` gains `touch => true`, which stamps the returned hits'
  `last_accessed_at`, so frequently-recalled memories resist idle expiry.
  Touching is opt-in to avoid a write on every read.

The expiry intervals are code-generated from numbers and inlined as
`interval '<n> seconds'`; the namespace is bound.

## Consequences

**Positive.**

- Memory stays bounded; a TTL caps the lifetime of any entry, including a
  poisoned one (a deliberate security control).
- Idle expiry plus `touch` keeps useful memories and drops forgotten ones,
  approximating an LRU without a separate structure.
- `expire`/`touch` are optional callbacks: stores that cannot support them are
  still valid `bunko_store` implementations.

**Negative.**

- bunko ships no scheduler; the host app must drive the sweep. This keeps the
  library boundary clean but means forgetting does not happen by itself.
- `touch` on recall is an extra write; left off by default, so callers opt into
  the cost.
- Deletion is irreversible. Aggressive `max_age_seconds` can drop still-relevant
  memories; the caller owns the policy.
