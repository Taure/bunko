-module(bunko_reranker).
-moduledoc """
Behaviour for rerankers: reorder recall hits as an optional second stage.

A reranker receives the query and the first-stage hits and returns them
reordered (and optionally trimmed). This is the seam for cross-encoder or
LLM-based rerankers; bunko ships no model. `bunko_reranker_stub` is the
deterministic offline reference and `bunko_reranker_score` wraps the built-in
recency/importance scorer (`m:bunko_score`).

`bunko:recall/3` applies a reranker when given `#{rerank => Ref}` where `Ref` is
a reranker reference; reranker-specific tuning goes under `rerank_opts`.
""".

-export([rerank/4, resolve/1]).

-export_type([ref/0]).

-type ref() :: module() | {module(), map()}.

-callback rerank(Query :: binary(), [bunko_store:hit()], Opts :: map()) ->
    {ok, [bunko_store:hit()]} | {error, term()}.

-doc "Rerank hits for a query via a reranker reference.".
-spec rerank(ref(), binary(), [bunko_store:hit()], map()) ->
    {ok, [bunko_store:hit()]} | {error, term()}.
rerank(Ref, Query, Hits, Opts) ->
    {Mod, RefOpts} = resolve(Ref),
    Mod:rerank(Query, Hits, maps:merge(RefOpts, Opts)).

-doc "Normalise a reranker reference to `{Module, Opts}`.".
-spec resolve(ref()) -> {module(), map()}.
resolve({Mod, Opts}) when is_atom(Mod), is_map(Opts) -> {Mod, Opts};
resolve(Mod) when is_atom(Mod) -> {Mod, #{}}.
