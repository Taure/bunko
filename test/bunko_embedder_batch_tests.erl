-module(bunko_embedder_batch_tests).
-include_lib("eunit/include/eunit.hrl").

setup() ->
    {ok, _} = application:ensure_all_started(crypto),
    application:set_env(bunko, embedding_dim, 8),
    bunko_embed_cache:clear(),
    bunko_counting_embedder:reset(),
    ok.

batch_test_() ->
    {setup, fun setup/0, [
        ?_test(embed_many_uses_callback()),
        ?_test(embed_many_falls_back_to_embed()),
        ?_test(cache_avoids_reembedding()),
        ?_test(batch_cache_only_embeds_misses())
    ]}.

embed_many_uses_callback() ->
    {ok, Vs} = bunko_embedder:embed_many(bunko_embedder_stub, [~"a", ~"b"]),
    ?assertEqual(2, length(Vs)),
    {ok, Va} = bunko_embedder:embed(bunko_embedder_stub, ~"a"),
    ?assertEqual(Va, hd(Vs)).

embed_many_falls_back_to_embed() ->
    bunko_counting_embedder:reset(),
    {ok, Vs} = bunko_embedder:embed_many(bunko_counting_embedder, [~"a", ~"b", ~"c"]),
    ?assertEqual(3, length(Vs)),
    ?assertEqual(3, bunko_counting_embedder:calls()).

cache_avoids_reembedding() ->
    bunko_counting_embedder:reset(),
    bunko_embed_cache:clear(),
    Ref = {bunko_counting_embedder, #{cache => true}},
    {ok, V1} = bunko_embedder:embed(Ref, ~"same"),
    {ok, V2} = bunko_embedder:embed(Ref, ~"same"),
    ?assertEqual(V1, V2),
    ?assertEqual(1, bunko_counting_embedder:calls()).

batch_cache_only_embeds_misses() ->
    bunko_counting_embedder:reset(),
    bunko_embed_cache:clear(),
    Ref = {bunko_counting_embedder, #{cache => true}},
    {ok, _} = bunko_embedder:embed(Ref, ~"warm"),
    ?assertEqual(1, bunko_counting_embedder:calls()),
    {ok, Vs} = bunko_embedder:embed_many(Ref, [~"warm", ~"cold", ~"warm"]),
    ?assertEqual(3, length(Vs)),
    ?assertEqual([lists:nth(1, Vs)], [lists:nth(3, Vs)]),
    ?assertEqual(2, bunko_counting_embedder:calls()).
