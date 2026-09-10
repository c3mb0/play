-module(receipt_recovery_tests).
-include_lib("eunit/include/eunit.hrl").

event(Seq, Kind, Data) ->
    #{<<"v">> => 1, <<"seq">> => Seq, <<"unix_ns">> => Seq, <<"monotonic_ns">> => Seq,
      <<"identity">> => #{<<"experiment">> => <<"synthetic">>, <<"cell">> => <<"fixture">>, <<"session">> => <<"fixture">>},
      <<"event">> => Kind, <<"data">> => Data}.
line(E) -> iolist_to_binary([json:encode(E), $\n]).
start() -> line(event(1, <<"session_start">>, #{})).
terminal() -> line(event(2, <<"session_terminal">>, #{<<"outcome">> => <<"worker_failure">>})).
analysis(Bytes) -> receipt_recovery:analyze(Bytes, missing).
class(Bytes) -> maps:get(classification, analysis(Bytes)).

incomplete_test() ->
    ?assertEqual(<<"incomplete">>, class(<<>>)),
    A = analysis(start()),
    ?assertEqual(<<"unknown">>, maps:get(outcome, A)),
    ?assertEqual(null, maps:get(observed_terminal, A)),
    ?assertEqual(1, maps:get(valid_events, A)),
    ?assertEqual(false, maps:get(metadata_complete, A)).

torn_tail_test() ->
    Prefix = start(),
    Tail = <<"{\"seq\":2">>,
    A = analysis(<<Prefix/binary, Tail/binary>>),
    ?assertEqual(<<"incomplete">>, maps:get(classification, A)),
    ?assertEqual(byte_size(Prefix), maps:get(valid_prefix_bytes, A)),
    ?assertEqual(byte_size(Tail), maps:get(trailing_bytes, A)).

unsealed_complete_test() ->
    A = analysis(<<(start())/binary, (terminal())/binary>>),
    ?assertEqual(<<"complete">>, maps:get(classification, A)),
    ?assertEqual(<<"absent">>, maps:get(integrity, A)),
    ?assertEqual(<<"worker_failure">>, maps:get(outcome, A)).

corruption_test() ->
    Prefix = start(),
    A = analysis(<<Prefix/binary, "bad-json\n", (terminal())/binary>>),
    ?assertEqual(<<"quarantined">>, maps:get(classification, A)),
    ?assertEqual(1, maps:get(valid_events, A)),
    ?assertEqual(null, maps:get(observed_terminal, A)),
    BadSeq = line(event(3, <<"session_terminal">>, #{<<"outcome">> => <<"worker_failure">>})),
    ?assertEqual(<<"quarantined">>, class(<<Prefix/binary, BadSeq/binary>>)),
    ChangedId = line((event(2, <<"port_open">>, #{}))#{<<"identity">> := #{}}),
    ?assertEqual(<<"quarantined">>, class(<<Prefix/binary, ChangedId/binary>>)),
    ?assertEqual(<<"quarantined">>, class(<<Prefix/binary, (terminal())/binary, "x">>)).

seal_test() ->
    Bytes = <<(start())/binary, (terminal())/binary>>,
    Hash = binary:encode_hex(crypto:hash(sha256, Bytes)),
    ?assertEqual(<<"verified">>, maps:get(integrity, receipt_recovery:analyze(Bytes, {present, <<Hash/binary, $\n>>}))),
    [begin
        A = receipt_recovery:analyze(Bytes, Seal),
        ?assertEqual(<<"quarantined">>, maps:get(classification, A)),
        ?assertEqual(<<"unknown">>, maps:get(outcome, A))
     end || Seal <- [{present, binary:copy(<<"0">>,64)}, {present, <<"garbage">>}, {error, eacces}]].

environment_encoding_test() ->
    ?assertEqual(receipt_metadata:environment_hash(#{<<"a">> => <<"bc">>, <<"d">> => <<"e">>}),
                 receipt_metadata:environment_hash(maps:from_list([{<<"d">>, <<"e">>}, {<<"a">>, <<"bc">>}]))),
    ?assertNotEqual(receipt_metadata:environment_hash(#{<<"a">> => <<"bc">>}),
                    receipt_metadata:environment_hash(#{<<"ab">> => <<"c">>})).
