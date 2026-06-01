-module(bunko_embedder_stub).
-moduledoc """
Deterministic embedder for tests and offline CI. Hashes the text into a fixed
vector of length `dim` (option `dim`, else `{bunko, embedding_dim}`). The same
text always yields the same vector, so exact-match recall is deterministic.
""".
-behaviour(bunko_embedder).

-export([embed/2, embed_many/2]).

-spec embed(binary(), map()) -> {ok, [float()]}.
embed(Text, Opts) ->
    Dim = maps:get(dim, Opts, application:get_env(bunko, embedding_dim, 1536)),
    {ok, [component(Text, I) || I <- lists:seq(1, Dim)]}.

-spec embed_many([binary()], map()) -> {ok, [[float()]]}.
embed_many(Texts, Opts) ->
    {ok, [
        begin
            {ok, V} = embed(T, Opts),
            V
        end
     || T <- Texts
    ]}.

%% Deterministic component in [-1.0, 1.0) from (text, dimension index).
component(Text, I) ->
    H = erlang:phash2({Text, I}, 1_000_000),
    H / 500_000.0 - 1.0.
