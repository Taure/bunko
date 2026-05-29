-module(bunko_embedder).
-moduledoc """
Behaviour for embedders: map text to a fixed-dimension vector. bunko ships no
embedding client - implement this over your model (gakudan_llm, sekisho, a
vendor SDK). `bunko_embedder_stub` is the deterministic offline reference.
""".

-export([embed/2, resolve/1]).

-export_type([ref/0, vector/0]).

-type ref() :: module() | {module(), map()}.
-type vector() :: [float()].

-callback embed(binary(), Opts :: map()) -> {ok, vector()} | {error, term()}.

-doc "Embed text via an embedder reference.".
-spec embed(ref(), binary()) -> {ok, vector()} | {error, term()}.
embed(Ref, Text) ->
    {Mod, Opts} = resolve(Ref),
    Mod:embed(Text, Opts).

-doc "Normalise an embedder reference to `{Module, Opts}`.".
-spec resolve(ref()) -> {module(), map()}.
resolve({Mod, Opts}) when is_atom(Mod), is_map(Opts) -> {Mod, Opts};
resolve(Mod) when is_atom(Mod) -> {Mod, #{}}.
