-module(m20260529063800_pgvector).
-moduledoc false.
-behaviour(kura_migration).
-export([up/0, down/0]).

%% pgvector-specific DDL: kura has no `vector` type, so the embedding column,
%% the extension, and the index are added with raw {execute, SQL} ops. The
%% dimension comes from {bunko, embedding_dim} so the column matches the
%% configured embedder.
-spec up() -> [kura_migration:operation()].
up() ->
    Dim = integer_to_binary(application:get_env(bunko, embedding_dim, 1536)),
    [
        {execute, ~"CREATE EXTENSION IF NOT EXISTS vector"},
        {execute, <<"ALTER TABLE bunko_memories ADD COLUMN embedding vector(", Dim/binary, ")">>},
        {execute,
            ~"CREATE INDEX bunko_memories_embedding_idx ON bunko_memories USING hnsw (embedding vector_cosine_ops)"}
    ].

-spec down() -> [kura_migration:operation()].
down() ->
    [
        {execute, ~"DROP INDEX IF EXISTS bunko_memories_embedding_idx"},
        {execute, ~"ALTER TABLE bunko_memories DROP COLUMN IF EXISTS embedding"}
    ].
