-module(port_protocol_tests).
-include_lib("eunit/include/eunit.hrl").

boundary_test() ->
    Id = #{<<"experiment">> => <<"e">>, <<"cell">> => <<"c">>, <<"session">> => <<"s">>},
    Event = #{<<"v">> => 1, <<"identity">> => Id, <<"seq">> => 1,
              <<"event">> => <<"stdout">>, <<"unix_ns">> => 100, <<"monotonic_ns">> => 10,
              <<"data">> => #{<<"hex">> => <<"00ff">>}},
    Bytes = port_protocol:encode(Event),
    ?assertEqual(Event, port_protocol:decode(Bytes, Id, 1)),
    ?assertException(error, _, port_protocol:decode(Bytes, Id, 2)),
    ?assertException(error, _, port_protocol:decode(Bytes, Id#{<<"session">> := <<"other">>}, 1)),
    ?assertException(error, _, port_protocol:decode(port_protocol:encode(Event#{<<"v">> := 2}), Id, 1)),
    ?assertException(error, _, port_protocol:decode(<<"{">>, Id, 1)).
