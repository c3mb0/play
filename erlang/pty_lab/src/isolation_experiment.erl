-module(isolation_experiment).
-export([run/2]).

run(Root, Directory) ->
    {ok,_} = application:ensure_all_started(pty_lab),
    Helper = filename:join(Root,"target/debug/pty_helper"),
    Base = #{helper=>Helper,deadline_ms=>5000,
        spec=>#{<<"executable">>=><<"/bin/cat">>,<<"argv">>=>[],<<"attachment">>=><<"pipe">>,
            <<"environment">>=>#{<<"LANG">>=><<"C">>,<<"PATH">>=><<"/usr/bin:/bin">>},<<"cwd">>=>list_to_binary(Root)}},
    Writer = whereis(receipt_writer),
    %% Same cell/session names, different experiments, simultaneous lifetime.
    A = start(<<"identity-a">>,Base,Directory), B = start(<<"identity-b">>,Base,Directory),
    {error,duplicate_identity} = pty_session:start_session(options(<<"identity-a">>,Base,Directory)),
    ok = pty_session:send_input(A,<<"alpha\n">>), ok = pty_session:send_input(B,<<"beta\n">>),
    done(A,<<"alpha\n">>), done(B,<<"beta\n">>),
    true = Writer =:= whereis(receipt_writer),
    note(Directory,<<"identity">>,#{outcome=><<"pass">>,same_cell_session=>true,duplicate_rejected=>true}),

    [failure(Kind,Base,Root,Directory) || Kind <- [helper,open_error,write_error,backpressure]],

    %% The writer is a shared dependency; its death aborts all current sessions.
    C = start(<<"writer-death-a">>,Base,Directory), D = start(<<"writer-death-b">>,Base,Directory),
    OldWriter = whereis(receipt_writer),
    exit(OldWriter,kill),
    [begin
        {ok,#{outcome:= <<"receipt_writer_failure">>,receipt_status:=partial}=Result} = pty_session:await_result(H,3000),
        reclaim(Helper,maps:get(reported_pids,maps:get(cleanup,Result))),
        {ok,Raw} = file:read_file(maps:get(receipt,H)),
        #{classification:= <<"incomplete">>} = receipt_recovery:analyze(Raw,missing)
     end || H <- [C,D]],
    wait_writer(OldWriter,erlang:monotonic_time(millisecond)+1000),
    E = start(<<"after-writer-death">>,Base,Directory), done(E,<<>>),
    note(Directory,<<"writer-death">>,#{outcome=><<"pass">>,partial_receipts_preserved=>true,no_replay=>true}),
    note(Directory,<<"result">>,#{outcome=><<"pass">>,cases=>6,retries=>0}), ok.

failure(Kind,Base,Root,Directory) ->
    Name = atom_to_binary(Kind),
    Healthy = start(<<Name/binary,"-healthy">>,Base,Directory),
    Writer = whereis(receipt_writer), Helper = maps:get(helper,Base),
    case Kind of
        open_error ->
            Bad = options(Name,Base,Directory),
            {error,{receipt_io,open,_}} = pty_session:start_session(Bad#{receipt:=Directory});
        _ ->
            FaultBase = case Kind of
                helper -> Base#{spec := (maps:get(spec,Base))#{<<"executable">>=>list_to_binary(filename:join(Root,"target/debug/lifetime_probe"))}};
                _ -> Base
            end,
            Fault = start(Name,FaultBase,Directory),
            #{child:=Spawn} = session_worker:status(maps:get(worker,Fault)),
            Pids = [maps:get(K,Spawn) || K <- [<<"helper_pid">>,<<"guardian_pid">>,<<"pid">>]],
            Expected = case Kind of
                helper ->
                    {ok,_} = pty_session:await_event(Fault,<<"stdout">>,1000),
                    0 = os_process("/bin/kill",["-KILL",integer_to_list(hd(Pids))]), <<"helper_failure">>;
                write_error ->
                    Key = maps:get(key,Fault),
                    sys:replace_state(receipt_writer,fun(S) ->
                        Entry = maps:get(Key,maps:get(sessions,S)),
                        ok = file:close(maps:get(fd,Entry)), S
                    end),
                    {error,_} = pty_session:send_input(Fault,<<"fault\n">>), <<"receipt_failure">>;
                backpressure ->
                    Relay = hd(Pids),
                    0 = os_process("/bin/kill",["-STOP",integer_to_list(Relay)]),
                    try fill(Fault,32)
                    after 0 = os_process("/bin/kill",["-CONT",integer_to_list(Relay)]) end,
                    <<"port_send_failure">>
            end,
            {ok,#{outcome:=Expected}=Result} = pty_session:await_result(Fault,3000),
            reclaim(Helper,Pids),
            {error,session_closed} = pty_session:send_input(Fault,<<"late">>),
            note(Directory,Name,#{outcome=><<"pass">>,session_result=>Result,pids_absent=>Pids})
    end,
    ok = pty_session:send_input(Healthy,<<"healthy\n">>), done(Healthy,<<"healthy\n">>),
    true = Writer =:= whereis(receipt_writer),
    case Kind of open_error -> note(Directory,Name,#{outcome=><<"pass">>,sibling_completed=>true}); _ -> ok end.

fill(_Handle,0) -> error(backpressure_not_observed);
fill(Handle,N) ->
    case pty_session:send_input(Handle,binary:copy(<<"x">>,32768)) of
        ok -> fill(Handle,N-1);
        {error,port_busy} -> ok;
        Other -> error({unexpected_send_result,Other})
    end.
options(Name,Base,Directory) ->
    Base#{identity=>#{<<"run">>=>list_to_binary(filename:basename(Directory)),<<"experiment">>=>Name,
        <<"cell">>=><<"same-cell">>,<<"session">>=><<"same-session">>},
        receipt=>filename:join(Directory,binary_to_list(Name)++".jsonl")}.
start(Name,Base,Directory) ->
    {ok,H} = pty_session:start_session(options(Name,Base,Directory)),
    {ok,_} = pty_session:await_event(H,<<"spawned">>,2000), H.
done(H,Expected) ->
    ok = pty_session:close_stdin(H),
    {ok,#{outcome:= <<"completed">>,receipt_status:=sealed,child_exit:=#{<<"code">>:=0,<<"signal">>:=null}}=R} =
        pty_session:await_result(H,3000),
    {ok,Bytes} = file:read_file(maps:get(receipt,H)),
    {ok,Seal} = file:read_file(maps:get(receipt,H)++".sha256"),
    #{classification:= <<"complete">>,integrity:= <<"verified">>} = receipt_recovery:analyze(Bytes,{present,Seal}),
    Events = [json:decode(L) || L<-binary:split(Bytes,<<"\n">>,[global]),L=/= <<>>],
    Expected = iolist_to_binary([binary:decode_hex(Hex) ||
        #{<<"event">>:= <<"helper_event">>,<<"data">>:=#{<<"event">>:= <<"stdout">>,<<"data">>:=#{<<"hex">>:=Hex}}}<-Events]),
    Spec = maps:get(<<"data">>,hd(Events)),
    Helper = binary_to_list(maps:get(<<"path">>,maps:get(<<"helper">>,Spec))),
    reclaim(Helper,maps:get(reported_pids,maps:get(cleanup,R))).
reclaim(Helper,Pids) -> reclaim(Helper,Pids,erlang:monotonic_time(millisecond)+3000).
reclaim(Helper,Pids,Deadline) ->
    Alive = [P || P<-Pids,os_process(Helper,["--alive",integer_to_list(P)])=:=0],
    case Alive of
        [] -> ok;
        _ -> true = erlang:monotonic_time(millisecond)<Deadline,
             receive after 10 -> reclaim(Helper,Pids,Deadline) end
    end.
wait_writer(Old,Deadline) ->
    case whereis(receipt_writer) of
        New when is_pid(New),New=/=Old -> ok;
        _ -> true = erlang:monotonic_time(millisecond)<Deadline,
             receive after 10 -> wait_writer(Old,Deadline) end
    end.
os_process(Exe,Args) ->
    P = open_port({spawn_executable,Exe},[binary,exit_status,{args,Args},hide]),
    receive {P,{exit_status,Code}} -> Code after 1000 -> erlang:port_close(P),error(os_process_timeout) end.
note(Directory,Name,Data) ->
    {ok,Fd} = file:open(filename:join(Directory,binary_to_list(Name)++".check.json"),[write,binary,exclusive]),
    try ok=file:write(Fd,[json:encode(Data),$\n]),ok=file:sync(Fd) after file:close(Fd) end.
