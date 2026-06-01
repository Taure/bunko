-module(bunko_store_SUITE).

-export([all/0, init_per_suite/1, end_per_suite/1]).
-export([
    install_is_idempotent/1,
    remember_and_recall/1,
    recall_respects_limit/1,
    recall_clamps_bad_limit/1,
    recall_filters_by_metadata/1,
    recall_drops_past_max_distance/1,
    recall_reranks_by_recency/1,
    recall_hybrid_finds_keyword_match/1,
    consolidate_merges_similar/1
]).

-include_lib("common_test/include/ct.hrl").
-include_lib("stdlib/include/assert.hrl").

all() ->
    [
        install_is_idempotent,
        remember_and_recall,
        recall_respects_limit,
        recall_clamps_bad_limit,
        recall_filters_by_metadata,
        recall_drops_past_max_distance,
        recall_reranks_by_recency,
        recall_hybrid_finds_keyword_match,
        consolidate_merges_similar
    ].

init_per_suite(Config) ->
    application:set_env(bunko, embedding_dim, 8),
    {ok, _} = application:ensure_all_started(kura),
    {ok, _} = application:ensure_all_started(kura_postgres),
    ok = bunko_test_repo:start(),
    %% Provision the schema through the public install/1 helper (dogfooding it).
    %% The container's tmpfs survives between local runs, so drop first for a
    %% clean slate, then install (which is itself idempotent).
    try
        ok = bunko_store_pgvector:uninstall(#{repo => bunko_test_repo}),
        ok = bunko_store_pgvector:install(#{repo => bunko_test_repo}),
        Config
    catch
        Class:Reason -> {skip, {bunko_db_setup, Class, Reason}}
    end.

end_per_suite(_Config) ->
    %% Symmetric teardown: drop the schema we provisioned in init_per_suite so
    %% the container's tmpfs is left clean between local runs. Guarded so a
    %% teardown hiccup never masks a genuine test result.
    try
        bunko_store_pgvector:uninstall(#{repo => bunko_test_repo})
    catch
        _:_ -> ok
    end,
    ok.

install_is_idempotent(_Config) ->
    %% init_per_suite already installed; a second call must not error.
    ?assertEqual(ok, bunko_store_pgvector:install(#{repo => bunko_test_repo})).

remember_and_recall(_Config) ->
    Ctx = ctx(~"ns-recall"),
    {ok, _} = bunko:remember(Ctx, ~"the sky is blue", #{}),
    {ok, _} = bunko:remember(Ctx, ~"cats are mammals", #{}),
    {ok, _} = bunko:remember(Ctx, ~"erlang has lightweight processes", #{}),
    {ok, Hits} = bunko:recall(Ctx, ~"cats are mammals", #{limit => 3}),
    [Top | _] = Hits,
    ?assertEqual(~"cats are mammals", maps:get(content, Top)).

recall_respects_limit(_Config) ->
    Ctx = ctx(~"ns-limit"),
    _ = [bunko:remember(Ctx, integer_to_binary(N), #{}) || N <- lists:seq(1, 5)],
    {ok, Hits} = bunko:recall(Ctx, ~"3", #{limit => 2}),
    ?assertEqual(2, length(Hits)).

recall_clamps_bad_limit(_Config) ->
    Ctx = ctx(~"ns-badlimit"),
    _ = [bunko:remember(Ctx, integer_to_binary(N), #{}) || N <- lists:seq(1, 7)],
    {ok, Zero} = bunko:recall(Ctx, ~"3", #{limit => 0}),
    {ok, Bad} = bunko:recall(Ctx, ~"3", #{limit => not_an_int}),
    ?assertEqual(5, length(Zero)),
    ?assertEqual(5, length(Bad)).

recall_filters_by_metadata(_Config) ->
    Ctx = ctx(~"ns-filter"),
    {ok, _} = bunko:remember(Ctx, ~"kept fact", #{<<"kind">> => <<"keep">>}),
    {ok, _} = bunko:remember(Ctx, ~"other fact", #{<<"kind">> => <<"skip">>}),
    {ok, Hits} = bunko:recall(Ctx, ~"fact", #{filter => #{<<"kind">> => <<"keep">>}}),
    ?assertEqual(1, length(Hits)),
    [Hit] = Hits,
    ?assertEqual(~"kept fact", maps:get(content, Hit)).

recall_drops_past_max_distance(_Config) ->
    Ctx = ctx(~"ns-maxdist"),
    {ok, _} = bunko:remember(Ctx, ~"the only memory here", #{}),
    {ok, Exact} = bunko:recall(Ctx, ~"the only memory here", #{max_distance => 0.0001}),
    {ok, NoneNear} = bunko:recall(Ctx, ~"totally unrelated query string", #{max_distance => 0.0001}),
    ?assertEqual(1, length(Exact)),
    ?assertEqual(0, length(NoneNear)).

recall_reranks_by_recency(_Config) ->
    Ctx = ctx(~"ns-rerank"),
    {ok, _} = bunko:remember(Ctx, ~"low priority note", #{~"importance" => 0.0}),
    {ok, _} = bunko:remember(Ctx, ~"high priority note", #{~"importance" => 1.0}),
    Weights = #{alpha => 0.0, beta => 1.0, gamma => 0.0},
    {ok, Hits} = bunko:recall(Ctx, ~"note", #{rerank => recency, rerank_weights => Weights}),
    [Top | _] = Hits,
    ?assertEqual(~"high priority note", maps:get(content, Top)),
    ?assert(maps:is_key(score, Top)).

recall_hybrid_finds_keyword_match(_Config) ->
    Ctx = ctx(~"ns-hybrid"),
    {ok, _} = bunko:remember(Ctx, ~"the quick brown fox jumps", #{}),
    {ok, _} = bunko:remember(Ctx, ~"lorem ipsum dolor sit amet", #{}),
    {ok, _} = bunko:remember(Ctx, ~"completely different content here", #{}),
    {ok, Hits} = bunko:recall(Ctx, ~"brown fox", #{hybrid => true, limit => 3}),
    Contents = [maps:get(content, H) || H <- Hits],
    ?assert(lists:member(~"the quick brown fox jumps", Contents)),
    [Top | _] = Hits,
    ?assertEqual(~"the quick brown fox jumps", maps:get(content, Top)).

consolidate_merges_similar(_Config) ->
    Ctx = ctx(~"ns-consolidate"),
    {ok, _} = bunko:remember(Ctx, ~"duplicate fact", #{}),
    {ok, _} = bunko:remember(Ctx, ~"duplicate fact", #{}),
    {ok, _} = bunko:remember(Ctx, ~"unique fact", #{}),
    {ok, Stats} = bunko:consolidate(Ctx, #{threshold => 0.99}),
    ?assertEqual(1, maps:get(groups_merged, Stats)),
    ?assertEqual(2, maps:get(memories_removed, Stats)),
    {ok, All} = bunko_store:all(store(), ~"ns-consolidate"),
    ?assertEqual(2, length(All)).

%% --- helpers ---

ctx(Namespace) ->
    #{
        store => store(),
        embedder => bunko_embedder_stub,
        namespace => Namespace,
        summarizer => bunko_summarizer_stub
    }.

store() ->
    {bunko_store_pgvector, #{repo => bunko_test_repo}}.
