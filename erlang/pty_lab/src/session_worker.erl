-module(session_worker).
-behaviour(gen_server).
-export([start_link/1, command/2, status/1]).
-export([init/1, handle_call/3, handle_cast/2, handle_info/2, terminate/2]).
start_link(Options) -> gen_server:start_link(?MODULE, Options, []).
command(Pid, Command) -> gen_server:call(Pid, {command, Command}, 2000).
status(Pid) -> gen_server:call(Pid, status, 2000).

init(Options) ->
    process_flag(trap_exit, true),
    Deadline = maps:get(deadline_ms, Options),
    true = is_integer(Deadline) andalso Deadline > 0 andalso Deadline =< 60000,
    Identity = maps:get(identity, Options),
    Id = maps:get(<<"session">>, Identity),
    ok = receipt_writer:open(self(), Options, Identity, maps:get(owner, Options)),
    Port = open_port({spawn_executable, maps:get(helper, Options)},
                     [binary, {packet, 4}, use_stdio, exit_status, {args, ["--port"]}, hide]),
    {os_pid, HelperPid} = erlang:port_info(Port, os_pid),
    ok = receipt_writer:event(Id, <<"port_open">>, #{helper_pid => HelperPid}),
    Timer = erlang:send_after(Deadline, self(), deadline),
    State = #{port => Port, helper_pid => HelperPid, identity => Identity, id => Id,
              seq => 0, received => 0, outcome => undefined, child => undefined,
              timer => Timer, owner => maps:get(owner, Options)},
    {ok, send(#{<<"command">> => <<"spawn">>, <<"spec">> => maps:get(spec, Options)}, State)}.

handle_call(status, _From, State) -> {reply, maps:with([helper_pid, child], State), State};
handle_call({command, Command}, _From, State) -> {reply, ok, send(Command, State)}.
handle_cast(_, State) -> {noreply, State}.

handle_info({Port, {data, Bytes}}, #{port := Port} = State) ->
    try port_protocol:decode(Bytes, maps:get(identity, State), maps:get(received, State) + 1) of
        Event ->
            ok = receipt_writer:event(maps:get(id, State), <<"helper_event">>, Event),
            maps:get(owner, State) ! {session_event, maps:get(id, State), Event},
            S = State#{received := maps:get(received, State) + 1},
            case maps:get(<<"event">>, Event) of
                <<"spawned">> -> {noreply, S#{child := maps:get(<<"data">>, Event)}};
                <<"child_exit">> -> {noreply, outcome(S, <<"completed">>)};
                <<"error">> -> {noreply, outcome(S, <<"helper_error">>)};
                _ -> {noreply, S}
            end
    catch Class:Reason ->
        finish(State, <<"protocol_failure">>, #{reason => printable({Class, Reason})})
    end;
handle_info({Port, {exit_status, Code}}, #{port := Port} = State) ->
    ok = receipt_writer:event(maps:get(id, State), <<"helper_exit">>, #{code => Code}),
    Outcome = case {Code, maps:get(outcome, State)} of
        {0, undefined} -> <<"helper_failure">>;
        {0, O} -> O;
        {_, <<"timeout">>} -> <<"timeout">>;
        _ -> <<"helper_failure">>
    end,
    finish(State, Outcome, #{helper_exit_code => Code});
handle_info({'EXIT', Port, normal}, #{port := Port} = State) -> {noreply, State};
handle_info({'EXIT', Port, Reason}, #{port := Port} = State) ->
    finish(State, <<"helper_failure">>, #{port_reason => printable(Reason)});
handle_info(deadline, State) ->
    ok = receipt_writer:event(maps:get(id, State), <<"timeout">>, #{}),
    erlang:send_after(1500, self(), cleanup_deadline),
    {noreply, send(#{<<"command">> => <<"terminate">>}, State#{outcome := <<"timeout">>})};
handle_info(cleanup_deadline, State) -> finish(State, <<"cleanup_timeout">>, #{});
handle_info(_, State) -> {noreply, State}.

outcome(#{outcome := undefined} = S, O) -> S#{outcome := O};
outcome(S, _) -> S.
send(Command, State) ->
    Seq = maps:get(seq, State) + 1,
    Value = Command#{<<"v">> => 1, <<"identity">> => maps:get(identity, State), <<"seq">> => Seq},
    ok = receipt_writer:event(maps:get(id, State), <<"command">>, Value),
    true = erlang:port_command(maps:get(port, State), port_protocol:encode(Value), [nosuspend]),
    State#{seq := Seq}.
finish(State, Outcome, Details) ->
    erlang:cancel_timer(maps:get(timer, State)),
    close_port(State),
    ok = receipt_writer:finish(maps:get(id, State), Outcome, Details),
    {stop, normal, State}.
terminate(_, State) -> close_port(State), ok.
close_port(State) -> try erlang:port_close(maps:get(port, State)) catch error:badarg -> ok end.
printable(Term) -> iolist_to_binary(io_lib:format("~p", [Term])).
