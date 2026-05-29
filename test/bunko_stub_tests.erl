-module(bunko_stub_tests).
-include_lib("eunit/include/eunit.hrl").

setup() ->
    {ok, _} = application:ensure_all_started(crypto),
    application:set_env(bunko, embedding_dim, 8),
    ok.

embedder_deterministic_test_() ->
    {setup, fun setup/0, [
        ?_test(same_text_same_vector()),
        ?_test(dim_matches_config()),
        ?_test(different_text_differs())
    ]}.

same_text_same_vector() ->
    {ok, V1} = bunko_embedder_stub:embed(~"hello", #{}),
    {ok, V2} = bunko_embedder_stub:embed(~"hello", #{}),
    ?assertEqual(V1, V2).

dim_matches_config() ->
    {ok, V} = bunko_embedder_stub:embed(~"hello", #{}),
    ?assertEqual(8, length(V)),
    {ok, V16} = bunko_embedder_stub:embed(~"hello", #{dim => 16}),
    ?assertEqual(16, length(V16)).

different_text_differs() ->
    {ok, A} = bunko_embedder_stub:embed(~"alpha", #{}),
    {ok, B} = bunko_embedder_stub:embed(~"beta", #{}),
    ?assertNotEqual(A, B).

summarizer_joins_test() ->
    ?assertEqual(
        {ok, ~"a | b | c"},
        bunko_summarizer_stub:summarize([~"a", ~"b", ~"c"], #{})
    ).
