-module(bunko_store).
-moduledoc """
Behaviour for memory stores: persist a memory and run namespaced similarity
search. The shipped implementation is `bunko_store_pgvector`; the behaviour is
the seam for others.
""".

-export([put/2, search/4, delete/2, all/2, resolve/1]).

-export_type([ref/0, memory/0, hit/0]).

-type ref() :: module() | {module(), map()}.
-type memory() :: #{
    id := binary(),
    namespace := binary(),
    content := binary(),
    embedding := [float()],
    metadata => map() | undefined
}.
-type hit() :: #{id := binary(), content := binary(), metadata := map(), distance := float()}.

-callback put(memory(), Opts :: map()) -> {ok, binary()} | {error, term()}.
-callback search(binary(), [float()], pos_integer(), Opts :: map()) ->
    {ok, [hit()]} | {error, term()}.
-callback delete([binary()], Opts :: map()) -> ok | {error, term()}.
-callback all(binary(), Opts :: map()) -> {ok, [memory()]} | {error, term()}.

-spec put(ref(), memory()) -> {ok, binary()} | {error, term()}.
put(Ref, Memory) ->
    {Mod, Opts} = resolve(Ref),
    Mod:put(Memory, Opts).

-spec search(ref(), binary(), [float()], pos_integer()) -> {ok, [hit()]} | {error, term()}.
search(Ref, Namespace, Vector, K) ->
    {Mod, Opts} = resolve(Ref),
    Mod:search(Namespace, Vector, K, Opts).

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
