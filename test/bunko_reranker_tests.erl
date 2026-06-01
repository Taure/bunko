-module(bunko_reranker_tests).
-include_lib("eunit/include/eunit.hrl").

hit(Id, Content) ->
    #{id => Id, content => Content, metadata => #{}, distance => 0.5}.

resolve_test() ->
    ?assertEqual({m, #{}}, bunko_reranker:resolve(m)),
    ?assertEqual({m, #{a => 1}}, bunko_reranker:resolve({m, #{a => 1}})).

stub_orders_by_token_overlap_test() ->
    Hits = [
        hit(~"a", ~"nothing relevant"),
        hit(~"b", ~"the brown fox runs"),
        hit(~"c", ~"a brown leaf")
    ],
    {ok, [First | _]} = bunko_reranker_stub:rerank(~"brown fox", Hits, #{}),
    ?assertEqual(~"b", maps:get(id, First)).

stub_stable_on_tie_test() ->
    Hits = [hit(~"a", ~"none"), hit(~"b", ~"none")],
    {ok, [F, S]} = bunko_reranker_stub:rerank(~"xyz", Hits, #{}),
    ?assertEqual(~"a", maps:get(id, F)),
    ?assertEqual(~"b", maps:get(id, S)).

score_adapter_delegates_test() ->
    Hits = [
        (hit(~"old", ~"x"))#{age_seconds => 604800.0},
        (hit(~"new", ~"x"))#{age_seconds => 0.0}
    ],
    Opts = #{alpha => 1.0, beta => 0.0, gamma => 0.0},
    {ok, [First | _]} = bunko_reranker_score:rerank(~"q", Hits, Opts),
    ?assertEqual(~"new", maps:get(id, First)),
    ?assert(maps:is_key(score, First)).

dispatch_merges_opts_test() ->
    {ok, [First | _]} = bunko_reranker:rerank(
        {bunko_reranker_stub, #{}}, ~"fox", [hit(~"a", ~"cat"), hit(~"b", ~"fox")], #{}
    ),
    ?assertEqual(~"b", maps:get(id, First)).
