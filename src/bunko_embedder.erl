-module(bunko_embedder).
-moduledoc """
Behaviour for embedders: map text to a fixed-dimension vector. bunko ships no
embedding client - implement this over your model (gakudan_llm, sekisho, a
vendor SDK). `bunko_embedder_stub` is the deterministic offline reference.

An embedder may also implement the optional `embed_many/2` callback to embed a
batch in one call (most embedding APIs are far cheaper per item in bulk); when it
is absent, `embed_many/2` falls back to mapping `embed/2`. A content-hash cache
(`m:bunko_embed_cache`) sits in front of both so identical content is never
re-embedded; enable it with the `cache => true` option on the embedder ref.
""".

-export([embed/2, embed_many/2, resolve/1]).

-export_type([ref/0, vector/0]).

-type ref() :: module() | {module(), map()}.
-type vector() :: [float()].

-callback embed(binary(), Opts :: map()) -> {ok, vector()} | {error, term()}.
-callback embed_many([binary()], Opts :: map()) -> {ok, [vector()]} | {error, term()}.

-optional_callbacks([embed_many/2]).

-doc "Embed text via an embedder reference (cached when `cache => true`).".
-spec embed(ref(), binary()) -> {ok, vector()} | {error, term()}.
embed(Ref, Text) ->
    {Mod, Opts} = resolve(Ref),
    case caching(Opts) of
        true -> cached_embed(Mod, Opts, Text);
        false -> Mod:embed(Text, Opts)
    end.

-doc """
Embed a batch of texts. Uses the embedder's `embed_many/2` when implemented,
otherwise maps `embed/2`. With `cache => true`, already-seen content is served
from the cache and only the misses are sent to the embedder.
""".
-spec embed_many(ref(), [binary()]) -> {ok, [vector()]} | {error, term()}.
embed_many(Ref, Texts) ->
    {Mod, Opts} = resolve(Ref),
    case caching(Opts) of
        true -> cached_embed_many(Mod, Opts, Texts);
        false -> embed_batch(Mod, Opts, Texts)
    end.

embed_batch(Mod, Opts, Texts) ->
    case erlang:function_exported(Mod, embed_many, 2) of
        true -> Mod:embed_many(Texts, Opts);
        false -> map_embed(Mod, Opts, Texts, [])
    end.

map_embed(_Mod, _Opts, [], Acc) ->
    {ok, lists:reverse(Acc)};
map_embed(Mod, Opts, [T | Rest], Acc) ->
    case Mod:embed(T, Opts) of
        {ok, V} -> map_embed(Mod, Opts, Rest, [V | Acc]);
        {error, _} = Err -> Err
    end.

caching(Opts) -> maps:get(cache, Opts, false) =:= true.

cached_embed(Mod, Opts, Text) ->
    case bunko_embed_cache:get(Mod, Opts, Text) of
        {ok, V} ->
            {ok, V};
        miss ->
            case Mod:embed(Text, Opts) of
                {ok, V} = Ok ->
                    bunko_embed_cache:put(Mod, Opts, Text, V),
                    Ok;
                {error, _} = Err ->
                    Err
            end
    end.

cached_embed_many(Mod, Opts, Texts) ->
    Misses = [T || T <- Texts, bunko_embed_cache:get(Mod, Opts, T) =:= miss],
    case embed_batch(Mod, Opts, lists:uniq(Misses)) of
        {ok, Vectors} ->
            _ = [
                bunko_embed_cache:put(Mod, Opts, T, V)
             || {T, V} <- lists:zip(lists:uniq(Misses), Vectors)
            ],
            collect_cached(Mod, Opts, Texts, []);
        {error, _} = Err ->
            Err
    end.

collect_cached(_Mod, _Opts, [], Acc) ->
    {ok, lists:reverse(Acc)};
collect_cached(Mod, Opts, [T | Rest], Acc) ->
    case bunko_embed_cache:get(Mod, Opts, T) of
        {ok, V} -> collect_cached(Mod, Opts, Rest, [V | Acc]);
        miss -> {error, {cache_miss, T}}
    end.

-doc "Normalise an embedder reference to `{Module, Opts}`.".
-spec resolve(ref()) -> {module(), map()}.
resolve({Mod, Opts}) when is_atom(Mod), is_map(Opts) -> {Mod, Opts};
resolve(Mod) when is_atom(Mod) -> {Mod, #{}}.
