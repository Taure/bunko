-module(bunko_memory_schema).
-moduledoc """
The base memory table. The `embedding vector(N)` column and its index are added
by a separate pgvector migration (kura has no vector type), so they are not
declared here.
""".

-behaviour(kura_schema).

-include_lib("kura/include/kura.hrl").

-export([table/0, fields/0]).

table() -> ~"bunko_memories".

fields() ->
    [
        #kura_field{name = id, type = string, primary_key = true, nullable = false},
        #kura_field{name = namespace, type = string, nullable = false},
        #kura_field{name = content, type = text, nullable = false},
        #kura_field{name = metadata, type = jsonb, nullable = true},
        #kura_field{name = inserted_at, type = utc_datetime, nullable = false},
        #kura_field{name = updated_at, type = utc_datetime, nullable = false}
    ].
