-module(m20260529063738_create_bunko_memories).
-moduledoc false.
-behaviour(kura_migration).
-include_lib("kura/include/kura.hrl").
-export([up/0, down/0]).

-spec up() -> [kura_migration:operation()].
up() ->
    [{create_table, ~"bunko_memories", [
        #kura_column{name = id, type = string, primary_key = true, nullable = false},
        #kura_column{name = namespace, type = string, nullable = false},
        #kura_column{name = content, type = text, nullable = false},
        #kura_column{name = metadata, type = jsonb},
        #kura_column{name = inserted_at, type = utc_datetime, nullable = false},
        #kura_column{name = updated_at, type = utc_datetime, nullable = false}
    ]}].

-spec down() -> [kura_migration:operation()].
down() ->
    [{drop_table, ~"bunko_memories"}].
