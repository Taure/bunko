-module(bunko_reranker_stub).
-moduledoc """
Deterministic reranker for tests and offline CI. Reorders hits by how many of
the query's whitespace tokens appear in the hit content (descending), breaking
ties by the first-stage order. No model; the same inputs always reorder the
same way.
""".
-behaviour(bunko_reranker).

-export([rerank/3]).

-spec rerank(binary(), [bunko_store:hit()], map()) -> {ok, [bunko_store:hit()]}.
rerank(Query, Hits, _Opts) ->
    Tokens = [T || T <- binary:split(Query, ~" ", [global]), T =/= <<>>],
    Indexed = lists:enumerate(Hits),
    Sorted = lists:sort(
        fun({Ia, A}, {Ib, B}) ->
            Sa = overlap(Tokens, maps:get(content, A)),
            Sb = overlap(Tokens, maps:get(content, B)),
            case Sa =:= Sb of
                true -> Ia =< Ib;
                false -> Sa > Sb
            end
        end,
        Indexed
    ),
    {ok, [H || {_, H} <- Sorted]}.

overlap(Tokens, Content) ->
    overlap(Tokens, Content, 0).

overlap([], _Content, Count) ->
    Count;
overlap([T | Rest], Content, Count) ->
    case binary:match(Content, T) of
        nomatch -> overlap(Rest, Content, Count);
        _ -> overlap(Rest, Content, Count + 1)
    end.
