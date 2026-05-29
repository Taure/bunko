-module(bunko).
-moduledoc """
Agent memory and semantic retrieval.

A *context* bundles the store, embedder, namespace, and (for consolidation) a
summarizer:

```erlang
Ctx = #{
    store => {bunko_store_pgvector, #{repo => myapp_repo}},
    embedder => {my_embedder, #{}},
    namespace => ~"agent:42",
    summarizer => {my_summarizer, #{}}
}.
```

`remember` embeds then stores; `recall` embeds the query then searches (top-k
cosine); `consolidate` merges near-duplicate memories via the summarizer.
""".

-export([remember/3, recall/3, consolidate/2]).

-export_type([context/0]).

-type context() :: #{
    store := bunko_store:ref(),
    embedder := bunko_embedder:ref(),
    namespace := binary(),
    summarizer => bunko_summarizer:ref()
}.

-doc "Embed `Content` and store it as a memory in the context's namespace.".
-spec remember(context(), binary(), map()) -> {ok, binary()} | {error, term()}.
remember(Ctx, Content, Metadata) ->
    case bunko_embedder:embed(embedder(Ctx), Content) of
        {ok, Vector} ->
            Memory = #{
                id => new_id(),
                namespace => namespace(Ctx),
                content => Content,
                embedding => Vector,
                metadata => Metadata
            },
            bunko_store:put(store(Ctx), Memory);
        {error, _} = Err ->
            Err
    end.

-doc "Recall the most relevant memories for `Query` (option `limit`, default 5).".
-spec recall(context(), binary(), map()) -> {ok, [bunko_store:hit()]} | {error, term()}.
recall(Ctx, Query, Opts) ->
    case bunko_embedder:embed(embedder(Ctx), Query) of
        {ok, Vector} ->
            bunko_store:search(store(Ctx), namespace(Ctx), Vector, limit(Opts));
        {error, _} = Err ->
            Err
    end.

limit(Opts) ->
    case maps:get(limit, Opts, 5) of
        N when is_integer(N), N > 0 -> N;
        _ -> 5
    end.

-doc """
Consolidate the namespace: group memories whose pairwise cosine similarity is at
or above `threshold` (default 0.9), summarize each group into one memory, and
delete the originals. Returns counts of groups merged and memories removed.

Best-effort, not atomic: each group is written (summary inserted, then originals
deleted) in turn, so a store error mid-run leaves earlier groups consolidated and
the failing one duplicated. The insert-before-delete order means a failure never
loses data, only leaves duplicates to re-consolidate.
""".
-spec consolidate(context(), map()) -> {ok, map()} | {error, term()}.
consolidate(Ctx, Opts) ->
    Threshold = maps:get(threshold, Opts, 0.9),
    case bunko_store:all(store(Ctx), namespace(Ctx)) of
        {ok, Memories} ->
            Groups = [G || G <- cluster(Memories, Threshold), length(G) > 1],
            merge_groups(Ctx, Groups, 0, 0);
        {error, _} = Err ->
            Err
    end.

%% --- consolidation ---

merge_groups(_Ctx, [], Merged, Removed) ->
    {ok, #{groups_merged => Merged, memories_removed => Removed}};
merge_groups(Ctx, [Group | Rest], Merged, Removed) ->
    Contents = [maps:get(content, M) || M <- Group],
    Ids = [maps:get(id, M) || M <- Group],
    case bunko_summarizer:summarize(summarizer(Ctx), Contents) of
        {ok, Summary} ->
            case remember(Ctx, Summary, #{consolidated_from => length(Ids)}) of
                {ok, _NewId} ->
                    case bunko_store:delete(store(Ctx), Ids) of
                        ok -> merge_groups(Ctx, Rest, Merged + 1, Removed + length(Ids));
                        {error, _} = Err -> Err
                    end;
                {error, _} = Err ->
                    Err
            end;
        {error, _} = Err ->
            Err
    end.

%% Greedy clustering by cosine similarity over the stored embeddings.
cluster(Memories, Threshold) ->
    cluster(Memories, Threshold, []).

cluster([], _Threshold, Acc) ->
    lists:reverse(Acc);
cluster([M | Rest], Threshold, Acc) ->
    {Similar, Others} = lists:partition(
        fun(X) -> cosine(embedding(M), embedding(X)) >= Threshold end, Rest
    ),
    cluster(Others, Threshold, [[M | Similar] | Acc]).

cosine(A, B) ->
    dot(A, B) / (norm(A) * norm(B) + 1.0e-12).

dot(A, B) ->
    lists:sum([X * Y || {X, Y} <- lists:zip(A, B)]).

norm(A) ->
    math:sqrt(dot(A, A)).

%% --- context accessors ---

store(#{store := S}) -> S.
embedder(#{embedder := E}) -> E.
namespace(#{namespace := N}) -> N.
summarizer(#{summarizer := S}) -> S.
embedding(#{embedding := E}) -> E.

new_id() ->
    binary:encode_hex(crypto:strong_rand_bytes(16), lowercase).
