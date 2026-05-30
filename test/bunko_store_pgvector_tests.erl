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

%% pgvector emits scientific notation for small float4 values; parsing must
%% not crash on tokens like ~"-2e-06" or ~"1.5E+3".
parse_vector_scientific_notation_test() ->
    [V1, V2, V3] = bunko_store_pgvector:parse_vector(~"[-2e-06,1.5e-3,3E+2]"),
    ?assert(abs(V1 - -2.0e-6) < 1.0e-12),
    ?assert(abs(V2 - 1.5e-3) < 1.0e-12),
    ?assert(abs(V3 - 300.0) < 1.0e-9).
