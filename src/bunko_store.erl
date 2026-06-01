-module(bunko_store).
-moduledoc """
Behaviour for memory stores: persist a memory and run namespaced similarity
search. The shipped implementation is `bunko_store_pgvector`; the behaviour is
the seam for others.

`search/5` takes a `t:query/0` map of query-time options (a metadata containment
filter, a distance threshold) on top of the store's static config `Opts`. This
keeps store configuration (the repo) separate from per-call retrieval tuning.
""".

-export([put/2, search/5, delete/2, all/2, resolve/1]).

-export_type([ref/0, memory/0, hit/0, query/0]).

-type ref() :: module() | {module(), map()}.
-type memory() :: #{
    id := binary(),
    namespace := binary(),
    content := binary(),
    embedding := [float()],
    metadata => map() | undefined
}.
-type hit() :: #{
    id := binary(),
    content := binary(),
    metadata := map(),
    distance := float(),
    age_seconds => float(),
    score => float()
}.
-type query() :: #{
    filter => map(),
    max_distance => number(),
    hybrid => boolean(),
    text => binary(),
    rrf_k => pos_integer(),
    rrf_pool => pos_integer()
}.

-callback put(memory(), Opts :: map()) -> {ok, binary()} | {error, term()}.
-callback search(binary(), [float()], pos_integer(), query(), Opts :: map()) ->
    {ok, [hit()]} | {error, term()}.
-callback delete([binary()], Opts :: map()) -> ok | {error, term()}.
-callback all(binary(), Opts :: map()) -> {ok, [memory()]} | {error, term()}.

-spec put(ref(), memory()) -> {ok, binary()} | {error, term()}.
put(Ref, Memory) ->
    {Mod, Opts} = resolve(Ref),
    Mod:put(Memory, Opts).

-spec search(ref(), binary(), [float()], pos_integer(), query()) ->
    {ok, [hit()]} | {error, term()}.
search(Ref, Namespace, Vector, K, Query) ->
    {Mod, Opts} = resolve(Ref),
    Mod:search(Namespace, Vector, K, Query, Opts).

-spec delete(ref(), [binary()]) -> ok | {error, term()}.
delete(Ref, Ids) ->
    {Mod, Opts} = resolve(Ref),
    Mod:delete(Ids, Opts).

-spec all(ref(), binary()) -> {ok, [memory()]} | {error, term()}.
all(Ref, Namespace) ->
    {Mod, Opts} = resolve(Ref),
    Mod:all(Namespace, Opts).

-doc "Normalise a store reference to `{Module, Opts}`.".
-spec resolve(ref()) -> {module(), map()}.
resolve({Mod, Opts}) when is_atom(Mod), is_map(Opts) -> {Mod, Opts};
resolve(Mod) when is_atom(Mod) -> {Mod, #{}}.
