-module(bunko_counting_embedder).
-moduledoc false.
-behaviour(bunko_embedder).

-export([embed/2, calls/0, reset/0]).

embed(Text, _Opts) ->
    ets_bump(),
    {ok, [float(erlang:phash2(Text, 1000))]}.

calls() ->
    ensure(),
    case ets:lookup(?MODULE, calls) of
        [{calls, N}] -> N;
        [] -> 0
    end.

reset() ->
    ensure(),
    ets:insert(?MODULE, {calls, 0}),
    ok.

ets_bump() ->
    ensure(),
    ets:update_counter(?MODULE, calls, 1, {calls, 0}).

ensure() ->
    case ets:whereis(?MODULE) of
        undefined -> ets:new(?MODULE, [named_table, public, set]);
        _ -> ok
    end.
