-module(bunko_store_SUITE).

-export([all/0, init_per_suite/1]).
-export([
    install_is_idempotent/1,
    remember_and_recall/1,
    recall_respects_limit/1,
    recall_clamps_bad_limit/1,
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
