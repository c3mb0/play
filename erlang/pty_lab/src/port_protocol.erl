-module(port_protocol).
-export([encode/1, decode/3, send/2]).
send(Port, Bytes) ->
    try erlang:port_command(Port, Bytes, [nosuspend]) of
        true -> ok;
        false -> {error, port_busy}
    catch error:badarg -> {error, port_closed} end.
encode(Value) ->
    Bytes = iolist_to_binary(json:encode(Value)),
    true = byte_size(Bytes) =< 1048576,
    Bytes.
decode(Bytes, Identity, Sequence) when byte_size(Bytes) =< 1048576 ->
    Value = json:decode(Bytes),
    #{<<"v">> := 1, <<"identity">> := Identity, <<"seq">> := Sequence,
      <<"event">> := Event, <<"unix_ns">> := Unix, <<"monotonic_ns">> := Mono,
      <<"data">> := Data} = Value,
    true = is_binary(Event) andalso is_integer(Unix) andalso is_integer(Mono) andalso is_map(Data),
    Value.
