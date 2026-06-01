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

-export([put/2, search/5, delete/2, all/2, expire/3, touch/2]).
-export([install/1, uninstall/1]).

-ifdef(TEST).
-export([parse_vector/1, vec_literal/1, filter_params/1, expire_clauses/1]).
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

-spec search(binary(), [float()], pos_integer(), bunko_store:query(), map()) ->
    {ok, [bunko_store:hit()]} | {error, term()}.
search(NS, Vec, K, #{hybrid := true, text := Text} = Query, #{repo := Repo}) when
    is_binary(Text)
->
    hybrid_search(NS, Vec, K, Text, Query, Repo);
search(NS, Vec, K, Query, #{repo := Repo}) ->
    Lit = vec_literal(Vec),
    Distance = iolist_to_binary([~"(embedding <=> ", Lit, ~")"]),
    {FilterClause, FilterParams} = filter_clause(Query, 3),
    DistClause = distance_clause(Query, Distance),
    SQL = iolist_to_binary([
        ~"SELECT id, content, metadata, extract(epoch from now() - inserted_at) AS age_seconds, ",
        Distance,
        ~" AS distance FROM bunko_memories WHERE namespace = $1",
        FilterClause,
        DistClause,
        ~" ORDER BY ",
        Distance,
        ~" LIMIT $2"
    ]),
    case Repo:query(SQL, [NS, K | FilterParams]) of
        {ok, Rows} -> {ok, [to_hit(R) || R <- Rows]};
        {error, _} = Err -> Err
    end.

%% Reciprocal Rank Fusion of a cosine lane and a tsvector keyword lane: fused
%% score is the sum over lanes of 1/(rrf_k + rank). Text is bound at $3, the
%% optional metadata filter at $4 (applied to both lanes).
hybrid_search(NS, Vec, K, Text, Query, Repo) ->
    Lit = vec_literal(Vec),
    Distance = iolist_to_binary([~"(embedding <=> ", Lit, ~")"]),
    RrfK = integer_to_binary(rrf_k(Query)),
    Pool = integer_to_binary(rrf_pool(Query, K)),
    {FilterClause, FilterParams} = filter_clause(Query, 4),
    SQL = iolist_to_binary([
        ~"WITH vec AS (",
        ~"SELECT id, content, metadata, extract(epoch from now() - inserted_at) AS age_seconds, ",
        Distance,
        ~" AS distance, row_number() OVER (ORDER BY ",
        Distance,
        ~") AS rnk FROM bunko_memories WHERE namespace = $1",
        FilterClause,
        ~" ORDER BY ",
        Distance,
        ~" LIMIT ",
        Pool,
        ~"), kw AS (",
        ~"SELECT id, content, metadata, extract(epoch from now() - inserted_at) AS age_seconds, ",
        ~"row_number() OVER (ORDER BY ts_rank_cd(to_tsvector('english', content), plainto_tsquery('english', $3)) DESC) AS rnk ",
        ~"FROM bunko_memories WHERE namespace = $1",
        FilterClause,
        ~" AND to_tsvector('english', content) @@ plainto_tsquery('english', $3) LIMIT ",
        Pool,
        ~") SELECT coalesce(vec.id, kw.id) AS id, coalesce(vec.content, kw.content) AS content, ",
        ~"coalesce(vec.metadata, kw.metadata) AS metadata, ",
        ~"coalesce(vec.age_seconds, kw.age_seconds) AS age_seconds, coalesce(vec.distance, 1.0) AS distance, ",
        ~"(coalesce(1.0 / (",
        RrfK,
        ~" + vec.rnk), 0.0) + coalesce(1.0 / (",
        RrfK,
        ~" + kw.rnk), 0.0)) AS rrf ",
        ~"FROM vec FULL OUTER JOIN kw ON vec.id = kw.id ",
        ~"ORDER BY rrf DESC LIMIT $2"
    ]),
    case Repo:query(SQL, [NS, K, Text | FilterParams]) of
        {ok, Rows} -> {ok, [to_hit(R) || R <- Rows]};
        {error, _} = Err -> Err
    end.

rrf_k(Query) ->
    case maps:get(rrf_k, Query, 60) of
        N when is_integer(N), N > 0 -> N;
        _ -> 60
    end.

rrf_pool(Query, K) ->
    case maps:get(rrf_pool, Query, K * 4) of
        N when is_integer(N), N > 0 -> N;
        _ -> K * 4
    end.

filter_clause(Query, Pos) ->
    case filter_params(Query) of
        [] ->
            {~"", []};
        Params ->
            {iolist_to_binary([~" AND metadata @> $", integer_to_binary(Pos), ~"::jsonb"]), Params}
    end.

filter_params(#{filter := Filter}) when is_map(Filter), map_size(Filter) > 0 ->
    [iolist_to_binary(json:encode(Filter))];
filter_params(_) ->
    [].

distance_clause(#{max_distance := Max}, Distance) when is_number(Max) ->
    iolist_to_binary([~" AND ", Distance, ~" <= ", float_to_binary(Max * 1.0, [{decimals, 8}])]);
distance_clause(_, _) ->
    ~"".

-spec delete([binary()], map()) -> ok | {error, term()}.
delete([], _Opts) ->
    ok;
delete(Ids, #{repo := Repo}) ->
    case Repo:query(~"DELETE FROM bunko_memories WHERE id = ANY($1::text[]) RETURNING id", [Ids]) of
        {ok, _} -> ok;
        {error, _} = Err -> Err
    end.

-spec expire(binary(), map(), map()) -> {ok, non_neg_integer()} | {error, term()}.
expire(NS, Expiry, #{repo := Repo}) ->
    case expire_clauses(Expiry) of
        [] ->
            {ok, 0};
        Clauses ->
            Where = iolist_to_binary(lists:join(~" OR ", Clauses)),
            SQL = iolist_to_binary([
                ~"DELETE FROM bunko_memories WHERE namespace = $1 AND (",
                Where,
                ~") RETURNING id"
            ]),
            case Repo:query(SQL, [NS]) of
                {ok, Rows} -> {ok, length(Rows)};
                {error, _} = Err -> Err
            end
    end.

expire_clauses(Expiry) ->
    age_clause(Expiry) ++ idle_clause(Expiry).

age_clause(#{max_age_seconds := S}) when is_number(S), S >= 0 ->
    [iolist_to_binary([~"inserted_at < now() - interval '", secs(S), ~" seconds'"])];
age_clause(_) ->
    [].

idle_clause(#{max_idle_seconds := S}) when is_number(S), S >= 0 ->
    [
        iolist_to_binary([
            ~"coalesce(last_accessed_at, inserted_at) < now() - interval '", secs(S), ~" seconds'"
        ])
    ];
idle_clause(_) ->
    [].

secs(S) -> float_to_binary(S * 1.0, [{decimals, 3}]).

-spec touch([binary()], map()) -> ok | {error, term()}.
touch([], _Opts) ->
    ok;
touch(Ids, #{repo := Repo}) ->
    SQL = ~"UPDATE bunko_memories SET last_accessed_at = now() WHERE id = ANY($1::text[])",
    case Repo:query(SQL, [Ids]) of
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
Create the pgvector extension, the `bunko_memories` table, the cosine (HNSW)
index, and a GIN full-text index on `content` (for hybrid search) in the given
repo. Idempotent (every statement is `IF NOT EXISTS`), so it is safe to call on
every boot. The embedding column dimension is `{bunko, embedding_dim}` (default
1536).
""".
-spec install(map()) -> ok | {error, term()}.
install(#{repo := Repo}) ->
    Dim = integer_to_binary(application:get_env(bunko, embedding_dim, 1536)),
    run_all(Repo, [
        ~"CREATE EXTENSION IF NOT EXISTS vector",
        create_table_sql(Dim),
        ~"ALTER TABLE bunko_memories ADD COLUMN IF NOT EXISTS last_accessed_at timestamptz",
        ~"CREATE INDEX IF NOT EXISTS bunko_memories_embedding_idx ON bunko_memories USING hnsw (embedding vector_cosine_ops)",
        ~"CREATE INDEX IF NOT EXISTS bunko_memories_content_fts_idx ON bunko_memories USING gin (to_tsvector('english', content))"
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
        ~"), metadata jsonb, inserted_at timestamptz NOT NULL, updated_at timestamptz NOT NULL, ",
        ~"last_accessed_at timestamptz)"
    ]).

run_all(_Repo, []) ->
    ok;
run_all(Repo, [SQL | Rest]) ->
    case Repo:query(SQL, []) of
        {error, _} = Err -> Err;
        _ -> run_all(Repo, Rest)
    end.

%% --- row mapping ---

to_hit(#{id := Id, content := Content, metadata := Meta, distance := Distance} = Row) ->
    Base = #{
        id => Id,
        content => Content,
        metadata => decode_meta(Meta),
        distance => to_float(Distance)
    },
    case maps:get(age_seconds, Row, undefined) of
        undefined -> Base;
        Age -> Base#{age_seconds => to_float(Age)}
    end.

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
    %% pgvector serialises small float4 values in scientific notation
    %% (e.g. ~"-2e-06"), which binary_to_float/binary_to_integer both reject.
    case binary:split(B, [~"e", ~"E"]) of
        [Mantissa, Exp] -> mantissa_to_float(Mantissa) * math:pow(10, exp_to_int(Exp));
        [Mantissa] -> mantissa_to_float(Mantissa)
    end.

mantissa_to_float(M) ->
    try
        binary_to_float(M)
    catch
        _:_ ->
            try
                float(binary_to_integer(M))
            catch
                _:_ -> binary_to_float(<<M/binary, ".0">>)
            end
    end.

exp_to_int(<<"+", E/binary>>) -> binary_to_integer(E);
exp_to_int(E) -> binary_to_integer(E).

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
