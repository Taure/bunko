-module(bunko_embed_cache_tests).
-include_lib("eunit/include/eunit.hrl").

setup() ->
    {ok, _} = application:ensure_all_started(crypto),
    application:set_env(bunko, embedding_dim, 8),
    bunko_embed_cache:clear(),
    ok.

cache_test_() ->
    {setup, fun setup/0, [
        ?_test(miss_then_hit()),
        ?_test(opts_partition_keys()),
        ?_test(cache_flag_ignored_in_key()),
        ?_test(clear_empties())
    ]}.

miss_then_hit() ->
    ?assertEqual(miss, bunko_embed_cache:get(bunko_embedder_stub, #{}, ~"x")),
    bunko_embed_cache:put(bunko_embedder_stub, #{}, ~"x", [1.0, 2.0]),
    ?assertEqual({ok, [1.0, 2.0]}, bunko_embed_cache:get(bunko_embedder_stub, #{}, ~"x")).

opts_partition_keys() ->
    bunko_embed_cache:put(bunko_embedder_stub, #{dim => 8}, ~"y", [1.0]),
    ?assertEqual({ok, [1.0]}, bunko_embed_cache:get(bunko_embedder_stub, #{dim => 8}, ~"y")),
    ?assertEqual(miss, bunko_embed_cache:get(bunko_embedder_stub, #{dim => 16}, ~"y")).

cache_flag_ignored_in_key() ->
    bunko_embed_cache:put(bunko_embedder_stub, #{cache => true}, ~"z", [3.0]),
    ?assertEqual({ok, [3.0]}, bunko_embed_cache:get(bunko_embedder_stub, #{}, ~"z")).

clear_empties() ->
    bunko_embed_cache:put(bunko_embedder_stub, #{}, ~"w", [9.0]),
    ok = bunko_embed_cache:clear(),
    ?assertEqual(miss, bunko_embed_cache:get(bunko_embedder_stub, #{}, ~"w")).
