-module(bunko_store_SUITE).

-export([all/0, init_per_suite/1]).
-export([
    remember_and_recall/1,
    recall_respects_limit/1,
    recall_clamps_bad_limit/1,
    consolidate_merges_similar/1
]).

-include_lib("common_test/include/ct.hrl").
-include_lib("stdlib/include/assert.hrl").

all() ->
    [
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
    %% kura_migrator:migrate/1 discovers migrations via the repo module's
    %% owning app, but a test-module repo belongs to no app - so apply bunko's
    %% migrations directly (compile_operation + kura_db:query, as the migrator
    %% does internally).
    try
        apply_migrations(bunko_test_repo),
        Config
    catch
        Class:Reason -> {skip, {bunko_db_setup, Class, Reason}}
    end.

apply_migrations(Repo) ->
    _ = application:load(bunko),
    %% Clean slate: the container's tmpfs survives between local runs, so drop
    %% the table first (the kura-generated CREATE TABLE is not idempotent).
    _ = kura_db:query(Repo, ~"DROP TABLE IF EXISTS bunko_memories CASCADE", []),
    {ok, Modules} = application:get_key(bunko, modules),
    Migrations = lists:sort([M || M <- Modules, is_migration(M)]),
    _ = [exec_op(Repo, Op) || M <- Migrations, Op <- M:up()],
    ok.

is_migration(Module) ->
    re:run(atom_to_list(Module), "^m[0-9]{14}_") =/= nomatch.

exec_op(Repo, Op) ->
    SQL = kura_migrator:compile_operation(Repo, Op),
    case kura_db:query(Repo, SQL, []) of
        {error, Reason} -> error({migration_op_failed, Op, Reason});
        _ -> ok
    end.

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
