-module(pty_session).
-export([start_session/1, send_input/2, close_stdin/1, terminate/1, await_result/2, await_event/3]).

start_session(Options0) ->
    try
        Options = session_identity:prepare(Options0),
        Id = maps:get(identity, Options), Key = session_identity:key(Id),
        case session_sup:start_session(Options#{owner => self(), notify_id => Key, api => true}) of
            {ok, Worker} -> {ok, #{key => Key, identity => Id, worker => Worker,
                receipt => maps:get(receipt, Options), monitor => monitor(process, Worker), owner => self()}};
            {error, Failure} -> {error, start_error(Failure)}
        end
    catch Class:Reason -> {error, {invalid_session, Class, Reason}} end.
start_error({Reason,Child}) when is_map(Child) -> Reason;
start_error({Reason,Child}) when is_tuple(Child), element(1,Child)=:=child -> Reason;
start_error(Reason) -> Reason.
send_input(Handle, Bytes) when is_binary(Bytes) ->
    call(Handle, #{<<"command">> => <<"write">>, <<"hex">> => binary:encode_hex(Bytes)}).
close_stdin(Handle) -> call(Handle, #{<<"command">> => <<"close_stdin">>}).
terminate(Handle) -> call(Handle, #{<<"command">> => <<"terminate">>}).
call(#{worker := Worker}, Command) -> session_worker:command(Worker, Command).

await_result(#{key := Key, monitor := Monitor, owner := Owner} = Handle, Timeout)
  when Owner =:= self(), is_integer(Timeout), Timeout >= 0 ->
    receive
        {session_result, Key, Result} -> demonitor(Monitor, [flush]), {ok, Result}
    after Timeout ->
        case is_process_alive(maps:get(worker, Handle)) of
            true -> {error, await_timeout};
            false -> {error, result_unavailable}
        end
    end.
await_event(#{key := Key, owner := Owner}, Name, Timeout)
  when Owner =:= self(), is_integer(Timeout), Timeout >= 0 ->
    receive {session_event, Key, #{<<"event">> := Name} = Event} -> {ok, Event}
    after Timeout -> {error, event_timeout} end.
