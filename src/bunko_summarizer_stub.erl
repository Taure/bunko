-module(bunko_summarizer_stub).
-moduledoc "Deterministic summarizer for tests: joins the contents with ` | `.".
-behaviour(bunko_summarizer).

-export([summarize/2]).

-spec summarize([binary()], map()) -> {ok, binary()}.
summarize(Contents, _Opts) ->
    {ok, iolist_to_binary(lists:join(~" | ", Contents))}.
