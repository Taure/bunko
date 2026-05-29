-module(bunko_store_pgvector_tests).
-include_lib("eunit/include/eunit.hrl").

parse_vector_roundtrip_test() ->
    Lit = bunko_store_pgvector:vec_literal([0.5, -1.25, 2.0]),
    %% strip the leading '[' / trailing ']'::vector wrapping back to pgvector text
    Text = ~"[0.50000000,-1.25000000,2.00000000]",
    ?assertEqual([0.5, -1.25, 2.0], bunko_store_pgvector:parse_vector(Text)),
    ?assertMatch(<<"'[", _/binary>>, Lit).

parse_vector_empty_test() ->
    ?assertEqual([], bunko_store_pgvector:parse_vector(~"[]")).

parse_vector_null_test() ->
    ?assertEqual([], bunko_store_pgvector:parse_vector(null)),
    ?assertEqual([], bunko_store_pgvector:parse_vector(undefined)),
    ?assertEqual([], bunko_store_pgvector:parse_vector(<<>>)).
