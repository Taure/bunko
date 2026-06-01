-module(bunko_embed_cache).
-moduledoc """
Content-hash cache for embeddings, so identical content is embedded once.

Backed by a public named ETS table created lazily on first use. The key is the
embedder module, the relevant embedder options, and a SHA-256 of the content, so
two embedders (or two configurations of one) never share vectors. Enabled per
embedder ref with the `cache => true` option; the `cache` flag itself is excluded
from the key.

This is a process-independent, best-effort cache: no eviction policy ships, so a
caller embedding unbounded distinct content should call `clear/0` periodically or
leave caching off. The table survives for the lifetime of the node.
""".

-export([get/3, put/4, clear/0]).

-define(TABLE, bunko_embed_cache).

-spec get(module(), map(), binary()) -> {ok, [float()]} | miss.
get(Mod, Opts, Content) ->
    ensure_table(),
    case ets:lookup(?TABLE, key(Mod, Opts, Content)) of
        [{_, Vector}] -> {ok, Vector};
        [] -> miss
    end.

-spec put(module(), map(), binary(), [float()]) -> ok.
put(Mod, Opts, Content, Vector) ->
    ensure_table(),
    true = ets:insert(?TABLE, {key(Mod, Opts, Content), Vector}),
    ok.

-doc "Empty the cache.".
-spec clear() -> ok.
clear() ->
    ensure_table(),
    true = ets:delete_all_objects(?TABLE),
    ok.

key(Mod, Opts, Content) ->
    {Mod, maps:remove(cache, Opts), crypto:hash(sha256, Content)}.

ensure_table() ->
    case ets:whereis(?TABLE) of
        undefined ->
            try
                _ = ets:new(?TABLE, [named_table, public, set, {read_concurrency, true}]),
                ok
            catch
                error:badarg -> ok
            end;
        _ ->
            ok
    end.
