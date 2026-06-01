-module(bunko_score).
-moduledoc """
Recency + importance reranking of recall hits, no model required.

Each hit is scored

```
alpha * recency + beta * importance + gamma * similarity
```

and the hits are returned sorted by that score (descending), each carrying a
`score` field.

- `recency` is `exp(-age_seconds / half_life_seconds * ln 2)`, an exponential
  decay over the memory's age (so a memory one half-life old scores `0.5`).
  Needs the `age_seconds` a pgvector hit carries; absent it, recency is `1.0`.
- `importance` is the `importance` metadata value (binary key), clamped to
  `[0.0, 1.0]`; absent or non-numeric it is `0.0`.
- `similarity` is `1.0 - distance` (cosine distance to cosine similarity).

Weights and the half-life come from the options map (`alpha`, `beta`, `gamma`,
`half_life_seconds`); the defaults weight recency, importance, and similarity
`0.2 / 0.2 / 0.6` with a one-week half-life.
""".

-export([rerank/2, score/2]).

-define(DEFAULT_HALF_LIFE, 604800.0).

-spec rerank([bunko_store:hit()], map()) -> [bunko_store:hit()].
rerank(Hits, Opts) ->
    Scored = [H#{score => score(H, Opts)} || H <- Hits],
    lists:sort(fun(A, B) -> maps:get(score, A) >= maps:get(score, B) end, Scored).

-spec score(bunko_store:hit(), map()) -> float().
score(Hit, Opts) ->
    Alpha = weight(alpha, Opts, 0.2),
    Beta = weight(beta, Opts, 0.2),
    Gamma = weight(gamma, Opts, 0.6),
    Alpha * recency(Hit, Opts) + Beta * importance(Hit) + Gamma * similarity(Hit).

recency(Hit, Opts) ->
    case maps:get(age_seconds, Hit, undefined) of
        Age when is_number(Age), Age >= 0 ->
            HalfLife = weight(half_life_seconds, Opts, ?DEFAULT_HALF_LIFE),
            math:exp(-Age / HalfLife * math:log(2));
        _ ->
            1.0
    end.

importance(#{metadata := Meta}) when is_map(Meta) ->
    case maps:get(~"importance", Meta, undefined) of
        I when is_number(I) -> clamp(I);
        _ -> 0.0
    end;
importance(_) ->
    0.0.

similarity(#{distance := D}) when is_number(D) -> 1.0 - D;
similarity(_) -> 0.0.

clamp(X) when X < 0.0 -> 0.0;
clamp(X) when X > 1.0 -> 1.0;
clamp(X) -> X * 1.0.

weight(Key, Opts, Default) ->
    case maps:get(Key, Opts, Default) of
        V when is_number(V) -> V * 1.0;
        _ -> Default
    end.
