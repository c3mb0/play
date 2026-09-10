-module(session_worker).
-behaviour(gen_server).
-export([start_link/1, command/2, status/1]).
-export([init/1, handle_continue/2, handle_call/3, handle_cast/2, handle_info/2, terminate/2]).
start_link(Options) -> gen_server:start_link(?MODULE, Options, []).
command(Pid, Command) -> safe_call(Pid,{command,Command}).
status(Pid) -> safe_call(Pid,status).
safe_call(Pid,Message) ->
    try gen_server:call(Pid,Message,2000)
    catch exit:{noproc,_} -> {error,session_closed}; exit:Reason -> {error,{session_call,Reason}} end.

init(Options0) ->
    process_flag(trap_exit,true),
    try
        Options = session_identity:prepare(Options0), Deadline = maps:get(deadline_ms,Options),
        true = is_integer(Deadline) andalso Deadline > 0 andalso Deadline =< 60000,
        Identity = maps:get(identity,Options), Key = session_identity:key(Identity),
        Writer = whereis(receipt_writer), true = is_pid(Writer),
        WriterMonitor = monitor(process,Writer), Metadata = receipt_metadata:build(Options),
        case receipt_writer:open(self(),Options#{metadata=>Metadata},Identity,maps:get(owner,Options)) of
            ok ->
                Timer = erlang:send_after(Deadline,self(),deadline),
                {ok,#{port=>undefined,helper_pid=>undefined,identity=>Identity,id=>Key,
                    seq=>0,received=>0,outcome=>undefined,child=>undefined,child_exit=>null,
                    timer=>Timer,owner=>maps:get(owner,Options),writer=>Writer,writer_monitor=>WriterMonitor,
                    options=>Options}, {continue,open_port}};
            {error,Reason} -> demonitor(WriterMonitor,[flush]), {stop,Reason}
        end
    catch Class:Error -> {stop,{invalid_session,Class,Error}} end.

handle_continue(open_port,State) ->
    Options = maps:get(options,State),
    Opened = try
        Port = open_port({spawn_executable,maps:get(helper,Options)},
            [binary,{packet,4},use_stdio,exit_status,{args,["--port"]},hide,
             {busy_limits_port,{65536,131072}}]),
        {os_pid,Pid} = erlang:port_info(Port,os_pid), {ok,Port,Pid}
    catch C:R -> {error,{C,R}} end,
    case Opened of
        {ok,P,H} ->
            S = State#{port:=P,helper_pid:=H},
            case record(<<"port_open">>,#{helper_pid=>H},S) of
                ok ->
                    case send(#{<<"command">>=><<"spawn">>,<<"spec">>=>maps:get(spec,Options)},S) of
                        {ok,Next} -> {noreply,Next};
                        {error,Reason,Next} -> stop_failure(Reason,Next)
                    end;
                {error,Reason} -> stop_failure(Reason,S)
            end;
        {error,Reason} -> finish(State,<<"helper_start_failure">>,#{reason=>printable(Reason)})
    end.

handle_call(status,_From,State) -> {reply,maps:with([helper_pid,child],State),State};
handle_call({command,Command},_From,State) ->
    case send(Command,State) of
        {ok,Next} -> {reply,ok,Next};
        {error,Reason,Next} ->
            {stop,normal,Final} = stop_failure(Reason,Next),
            {stop,normal,{error,Reason},Final}
    end.
handle_cast(_,State) -> {noreply,State}.

handle_info({Port,{data,Bytes}},#{port:=Port}=State) ->
    Decoded = try {ok,port_protocol:decode(Bytes,maps:get(identity,State),maps:get(received,State)+1)}
              catch C:R -> {error,{C,R}} end,
    case Decoded of
        {error,Reason} -> finish(State,<<"protocol_failure">>,#{reason=>printable(Reason)});
        {ok,Event} ->
            case record(<<"helper_event">>,Event,State) of
                {error,Reason} -> stop_failure(Reason,State);
                ok ->
                    Options = maps:get(options,State),
                    Notify = maps:get(notify_id,Options,maps:get(<<"session">>,maps:get(identity,State))),
                    maps:get(owner,State) ! {session_event,Notify,Event},
                    S = State#{received:=maps:get(received,State)+1},
                    case maps:get(<<"event">>,Event) of
                        <<"spawned">> -> {noreply,S#{child:=maps:get(<<"data">>,Event)}};
                        <<"child_exit">> -> {noreply,outcome(S#{child_exit:=maps:get(<<"data">>,Event)},<<"completed">>)};
                        <<"error">> -> {noreply,outcome(S,<<"helper_error">>)};
                        _ -> {noreply,S}
                    end
            end
    end;
handle_info({Port,{exit_status,Code}},#{port:=Port}=State) ->
    case record(<<"helper_exit">>,#{code=>Code},State) of
        {error,Reason} -> stop_failure(Reason,State);
        ok ->
            Outcome = case {Code,maps:get(outcome,State)} of
                {0,undefined} -> <<"helper_failure">>;
                {0,O} -> O;
                {_,<<"timeout">>} -> <<"timeout">>;
                _ -> <<"helper_failure">>
            end,
            finish(State,Outcome,#{helper_exit_code=>Code})
    end;
handle_info({'EXIT',Port,normal},#{port:=Port}=State) -> {noreply,State};
handle_info({'EXIT',Port,Reason},#{port:=Port}=State) -> finish(State,<<"helper_failure">>,#{reason=>printable(Reason)});
handle_info({'DOWN',Ref,process,_,Reason},#{writer_monitor:=Ref}=State) ->
    finish(State,<<"receipt_writer_failure">>,#{reason=>printable(Reason)});
handle_info({receipt_failed,Key,Reason},#{id:=Key}=State) -> stop_failure(Reason,State);
handle_info(deadline,State) ->
    case record(<<"timeout">>,#{},State) of
        {error,Reason} -> stop_failure(Reason,State);
        ok ->
            erlang:send_after(1500,self(),cleanup_deadline),
            case send(#{<<"command">>=><<"terminate">>},State#{outcome:= <<"timeout">>}) of
                {ok,Next} -> {noreply,Next};
                {error,Reason,Next} -> stop_failure(Reason,Next)
            end
    end;
handle_info(cleanup_deadline,State) -> finish(State,<<"cleanup_timeout">>,#{});
handle_info(_,State) -> {noreply,State}.

outcome(#{outcome:=undefined}=S,O) -> S#{outcome:=O}; outcome(S,_) -> S.
record(Kind,Data,State) ->
    case whereis(receipt_writer)=:=maps:get(writer,State) of
        true -> receipt_writer:event(maps:get(id,State),Kind,Data);
        false -> {error,writer_unavailable}
    end.
send(Command,State) ->
    Seq = maps:get(seq,State)+1,
    Encoded = try
        V = Command#{<<"v">>=>1,<<"identity">>=>maps:get(identity,State),<<"seq">>=>Seq},
        {ok,V,port_protocol:encode(V)}
    catch C:R -> {error,{invalid_command,C,R}} end,
    case Encoded of
        {error,Reason} -> {error,Reason,State};
        {ok,Value,Bytes} ->
            case record(<<"command">>,Value,State) of
                {error,Reason} -> {error,Reason,State};
                ok ->
                    S = State#{seq:=Seq},
                    case port_protocol:send(maps:get(port,State),Bytes) of
                        ok -> {ok,S};
                        {error,Reason} -> {error,Reason,S}
                    end
            end
    end.
stop_failure(Reason,State) ->
    Outcome = case Reason of
        port_busy -> <<"port_send_failure">>; port_closed -> <<"port_send_failure">>;
        {invalid_command,_,_} -> <<"command_failure">>;
        writer_unavailable -> <<"receipt_writer_failure">>;
        {writer_unavailable,_} -> <<"receipt_writer_failure">>;
        _ -> <<"receipt_failure">>
    end,
    finish(State,Outcome,#{reason=>printable(Reason)}).
finish(State,Outcome,Details0) ->
    erlang:cancel_timer(maps:get(timer,State)), close_port(State),
    Details = Details0#{child_exit=>maps:get(child_exit,State),reported_pids=>pids(State)},
    Result = case whereis(receipt_writer)=:=maps:get(writer,State) of
        true -> receipt_writer:finish(maps:get(id,State),Outcome,Details);
        false -> {error,writer_unavailable}
    end,
    case Result of
        ok -> ok;
        {error,Error} ->
            Options = maps:get(options,State),
            E = #{identity=>maps:get(identity,State),owner=>maps:get(owner,State),file=>maps:get(receipt,Options),
                notify_id=>maps:get(notify_id,Options,maps:get(<<"session">>,maps:get(identity,State))),api=>maps:get(api,Options,false)},
            receipt_writer:publish(E,Outcome,Details#{receipt_error=>printable(Error)},partial)
    end,
    {stop,normal,State}.
pids(State) ->
    Child = maps:get(child,State),
    case is_map(Child) of
        true -> [maps:get(K,Child) || K <- [<<"helper_pid">>,<<"guardian_pid">>,<<"pid">>]];
        false -> case maps:get(helper_pid,State) of undefined -> []; Pid -> [Pid] end
    end.
terminate(_,State) -> close_port(State),ok.
close_port(State) -> try erlang:port_close(maps:get(port,State)) catch error:badarg -> ok end.
printable(Term) -> iolist_to_binary(io_lib:format("~p",[Term])).
