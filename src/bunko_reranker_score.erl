-module(bunko_reranker_score).
-moduledoc """
A `m:bunko_reranker` that wraps the built-in recency + importance + similarity
scorer (`m:bunko_score`). Deterministic, no model. Options (`alpha`, `beta`,
`gamma`, `half_life_seconds`) are forwarded to `bunko_score:rerank/2`.
""".
-behaviour(bunko_reranker).

-export([rerank/3]).

-spec rerank(binary(), [bunko_store:hit()], map()) -> {ok, [bunko_store:hit()]}.
rerank(_Query, Hits, Opts) ->
    {ok, bunko_score:rerank(Hits, Opts)}.
