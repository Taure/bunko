-module(bunko_store_pgvector).
-moduledoc """
pgvector-backed `m:bunko_store`. Uses the caller's kura repo (`opts.repo`) and
raw SQL - kura has no `vector` type, so vectors are passed as text literals cast
to `::vector` and search orders by the `<=>` cosine-distance operator.

Opts: `#{repo := module()}` - a kura repo module exporting `query/2`.

## Installing the schema

Because kura discovers migrations through the *consuming* app, a consumer's repo
cannot auto-apply bunko's migrations. Call `install/1` once at setup to create
the `vector` extension, the `bunko_memories` table, and the cosine index in your
repo - idempotent, so it is safe to call on every boot:

```erlang
ok = bunko_store_pgvector:install(#{repo => myapp_repo}).
```

The embedding column is `vector(N)` where `N` is `{bunko, embedding_dim}`
(default 1536), so set that before installing and match it in your embedder.
""".
-behaviour(bunko_store).

-export([put/2, search/4, delete/2, all/2]).
-export([install/1, uninstall/1]).

-ifdef(TEST).
-export([parse_vector/1, vec_literal/1]).
-endif.

-spec put(bunko_store:memory(), map()) -> {ok, binary()} | {error, term()}.
put(#{id := Id, namespace := NS, content := Content, embedding := Vec} = Mem, #{repo := Repo}) ->
    Meta = maps:get(metadata, Mem, undefined),
    %% The vector is inlined as a literal (pgo cannot bind a `vector`-typed
    %% parameter); the floats are code-generated, so there is no injection risk.
    SQL = iolist_to_binary([
        ~"INSERT INTO bunko_memories (id, namespace, content, embedding, metadata, inserted_at, updated_at) VALUES ($1, $2, $3, ",
        vec_literal(Vec),
        ~", $4::jsonb, now(), now()) RETURNING id"
    ]),
    case Repo:query(SQL, [Id, NS, Content, meta_json(Meta)]) of
        {ok, _} -> {ok, Id};
        {error, _} = Err -> Err
    end.

-spec search(binary(), [float()], pos_integer(), map()) ->
    {ok, [bunko_store:hit()]} | {error, term()}.
search(NS, Vec, K, #{repo := Repo}) ->
    Lit = vec_literal(Vec),
    SQL = iolist_to_binary([
        ~"SELECT id, content, metadata, (embedding <=> ",
        Lit,
        ~") AS distance FROM bunko_memories WHERE namespace = $1 ORDER BY embedding <=> ",
        Lit,
        ~" LIMIT $2"
    ]),
    case Repo:query(SQL, [NS, K]) of
        {ok, Rows} -> {ok, [to_hit(R) || R <- Rows]};
        {error, _} = Err -> Err
    end.

-spec delete([binary()], map()) -> ok | {error, term()}.
delete([], _Opts) ->
    ok;
delete(Ids, #{repo := Repo}) ->
    case Repo:query(~"DELETE FROM bunko_memories WHERE id = ANY($1::text[]) RETURNING id", [Ids]) of
        {ok, _} -> ok;
        {error, _} = Err -> Err
    end.

-spec all(binary(), map()) -> {ok, [bunko_store:memory()]} | {error, term()}.
all(NS, #{repo := Repo}) ->
    SQL =
        ~"SELECT id, namespace, content, metadata, embedding::text AS embedding FROM bunko_memories WHERE namespace = $1",
    case Repo:query(SQL, [NS]) of
        {ok, Rows} -> {ok, [to_memory(R) || R <- Rows]};
        {error, _} = Err -> Err
    end.

%% --- schema install ---

-doc """
Create the pgvector extension, the `bunko_memories` table, and the cosine index
in the given repo. Idempotent (every statement is `IF NOT EXISTS`), so it is
safe to call on every boot. The embedding column dimension is `{bunko,
embedding_dim}` (default 1536).
""".
-spec install(map()) -> ok | {error, term()}.
install(#{repo := Repo}) ->
    Dim = integer_to_binary(application:get_env(bunko, embedding_dim, 1536)),
    run_all(Repo, [
        ~"CREATE EXTENSION IF NOT EXISTS vector",
        create_table_sql(Dim),
        ~"CREATE INDEX IF NOT EXISTS bunko_memories_embedding_idx ON bunko_memories USING hnsw (embedding vector_cosine_ops)"
    ]).

-doc "Drop the `bunko_memories` table. Irreversible; intended for teardown/tests.".
-spec uninstall(map()) -> ok | {error, term()}.
uninstall(#{repo := Repo}) ->
    run_all(Repo, [~"DROP TABLE IF EXISTS bunko_memories CASCADE"]).

create_table_sql(Dim) ->
    iolist_to_binary([
        ~"CREATE TABLE IF NOT EXISTS bunko_memories (",
        ~"id text PRIMARY KEY, namespace text NOT NULL, content text NOT NULL, ",
        ~"embedding vector(",
        Dim,
        ~"), metadata jsonb, inserted_at timestamptz NOT NULL, updated_at timestamptz NOT NULL)"
    ]).

run_all(_Repo, []) ->
    ok;
run_all(Repo, [SQL | Rest]) ->
    case Repo:query(SQL, []) of
        {error, _} = Err -> Err;
        _ -> run_all(Repo, Rest)
    end.

%% --- row mapping ---

to_hit(#{id := Id, content := Content, metadata := Meta, distance := Distance}) ->
    #{id => Id, content => Content, metadata => decode_meta(Meta), distance => to_float(Distance)}.

to_memory(#{id := Id, namespace := NS, content := Content, metadata := Meta, embedding := Emb}) ->
    #{
        id => Id,
        namespace => NS,
        content => Content,
        metadata => decode_meta(Meta),
        embedding => parse_vector(Emb)
    }.

%% --- vector + json encoding ---

%% A pgvector literal: '[f1,f2,...]'::vector. Inlined into SQL (not a bound
%% parameter); safe because the floats are code-generated.
vec_literal(Floats) ->
    Inner = lists:join($,, [float_to_binary(F * 1.0, [{decimals, 8}]) || F <- Floats]),
    iolist_to_binary([$', $[, Inner, $], $', "::vector"]).

parse_vector(null) ->
    [];
parse_vector(undefined) ->
    [];
parse_vector(Text) when is_binary(Text), byte_size(Text) >= 2 ->
    Inner = binary:part(Text, 1, byte_size(Text) - 2),
    [to_float(P) || P <- binary:split(Inner, ~",", [global]), P =/= <<>>];
parse_vector(_) ->
    [].

to_float(F) when is_float(F) -> F;
to_float(I) when is_integer(I) -> float(I);
to_float(B) when is_binary(B) ->
    try
        binary_to_float(B)
    catch
        _:_ -> float(binary_to_integer(B))
    end.

meta_json(undefined) -> ~"null";
meta_json(Map) -> iolist_to_binary(json:encode(Map)).

decode_meta(null) ->
    #{};
decode_meta(undefined) ->
    #{};
decode_meta(Map) when is_map(Map) -> Map;
decode_meta(B) when is_binary(B) ->
    try
        json:decode(B)
    catch
        _:_ -> #{}
    end.
