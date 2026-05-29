-module(bunko_summarizer).
-moduledoc """
Behaviour for summarizers: merge several memory contents into one, for
consolidation. bunko ships no LLM client - implement this over your model.
`bunko_summarizer_stub` is the deterministic offline reference.
""".

-export([summarize/2, resolve/1]).

-export_type([ref/0]).

-type ref() :: module() | {module(), map()}.

-callback summarize([binary()], Opts :: map()) -> {ok, binary()} | {error, term()}.

-doc "Summarize several contents into one via a summarizer reference.".
-spec summarize(ref(), [binary()]) -> {ok, binary()} | {error, term()}.
summarize(Ref, Contents) ->
    {Mod, Opts} = resolve(Ref),
    Mod:summarize(Contents, Opts).

-doc "Normalise a summarizer reference to `{Module, Opts}`.".
-spec resolve(ref()) -> {module(), map()}.
resolve({Mod, Opts}) when is_atom(Mod), is_map(Opts) -> {Mod, Opts};
resolve(Mod) when is_atom(Mod) -> {Mod, #{}}.
