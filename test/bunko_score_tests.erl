-module(bunko_score_tests).
-include_lib("eunit/include/eunit.hrl").

hit(Distance, Age, Importance) ->
    Meta =
        case Importance of
            undefined -> #{};
            I -> #{~"importance" => I}
        end,
    #{
        id => ~"x",
        content => ~"c",
        metadata => Meta,
        distance => Distance,
        age_seconds => Age
    }.

recency_decays_with_age_test() ->
    Fresh = bunko_score:score(hit(0.0, 0.0, undefined), #{alpha => 1.0, beta => 0.0, gamma => 0.0}),
    HalfLife = bunko_score:score(
        hit(0.0, 604800.0, undefined),
        #{alpha => 1.0, beta => 0.0, gamma => 0.0}
    ),
    ?assert(abs(Fresh - 1.0) < 1.0e-9),
    ?assert(abs(HalfLife - 0.5) < 1.0e-6).

importance_clamped_test() ->
    S = bunko_score:score(hit(1.0, 0.0, 5.0), #{alpha => 0.0, beta => 1.0, gamma => 0.0}),
    ?assert(abs(S - 1.0) < 1.0e-9).

similarity_from_distance_test() ->
    S = bunko_score:score(hit(0.25, 0.0, undefined), #{alpha => 0.0, beta => 0.0, gamma => 1.0}),
    ?assert(abs(S - 0.75) < 1.0e-9).

missing_age_treated_fresh_test() ->
    H = #{id => ~"y", content => ~"c", metadata => #{}, distance => 0.0},
    S = bunko_score:score(H, #{alpha => 1.0, beta => 0.0, gamma => 0.0}),
    ?assert(abs(S - 1.0) < 1.0e-9).

rerank_orders_by_score_test() ->
    Old = hit(0.1, 604800.0, undefined),
    New = (hit(0.1, 0.0, undefined))#{id => ~"new"},
    [First | _] = bunko_score:rerank([Old, New], #{alpha => 1.0, beta => 0.0, gamma => 0.0}),
    ?assertEqual(~"new", maps:get(id, First)),
    ?assert(maps:is_key(score, First)).
