-module(experiment_runner).
-export([run/2]).

run(Root, Directory) ->
    {ok, _} = application:ensure_all_started(pty_lab),
    Sup = whereis(pty_lab_sup),
    {ok, ConfigBytes} = file:read_file(filename:join(Root, "receipts/gate-20260910T194539Z/terminal-config.json")),
    Config = json:decode(ConfigBytes),
    Helper = filename:join(Root, "target/debug/pty_helper"),
    Probe = filename:join(Root, "target/debug/topology_probe"),
    Snapshot = filename:join(Directory, "observation.json"),
    Base = #{<<"executable">> => list_to_binary(Probe),
        <<"argv">> => [<<"--snapshot">>, list_to_binary(Snapshot)],
        <<"cwd">> => list_to_binary(Root),
        <<"environment">> => #{<<"PATH">> => <<"/usr/bin:/bin">>, <<"LANG">> => <<"C">>, <<"TERM">> => <<"xterm-256color">>},
        <<"terminal">> => Config},
    [begin
        Spec = Base#{<<"attachment">> => Mode},
        {Worker, Id} = start(Mode, Spec, Helper, Directory, 5000),
        <<"completed">> = terminal(Id),
        dead_worker(Worker),
        {ok, ObservationBytes} = file:read_file(Snapshot),
        Observation = json:decode(ObservationBytes),
        Expected = Mode =/= <<"pipe">>,
        true = lists:all(fun(Fd) -> maps:get(<<"value">>, maps:get(<<"isatty">>, Fd)) =:= Expected end,
                         maps:get(<<"stdio">>, Observation)),
        true = maps:get(<<"accessible">>, maps:get(<<"controlling_tty">>, Observation)) =:= (Mode =:= <<"ctty">>),
        ok = file:rename(Snapshot, filename:join(Directory, binary_to_list(Mode) ++ ".observation.json"))
    end || Mode <- [<<"pipe">>, <<"slave">>, <<"ctty">>]],

    Cat = Base#{<<"executable">> => <<"/bin/cat">>, <<"argv">> => [], <<"attachment">> => <<"pipe">>},
    {CatWorker, CatId} = start(<<"binary-input">>, Cat, Helper, Directory, 5000),
    _ = event(CatId, <<"spawned">>),
    Input = <<0, 255, 10, 65, 13, 66>>,
    ok = session_worker:command(CatWorker, #{<<"command">> => <<"write">>, <<"hex">> => binary:encode_hex(Input)}),
    ok = session_worker:command(CatWorker, #{<<"command">> => <<"close_stdin">>}),
    <<"completed">> = terminal(CatId),
    Input = output(Directory, CatId, <<"stdout">>),

    Hold = Base#{<<"executable">> => list_to_binary(filename:join(Root, "target/debug/lifetime_probe")), <<"argv">> => []},
    [begin
        Name = <<"murder-", Mode/binary>>,
        {Worker, Id} = start(Name, Hold#{<<"attachment">> => Mode}, Helper, Directory, 5000),
        Spawned = event(Id, <<"spawned">>),
        ready(Id, case Mode of <<"pipe">> -> <<"stdout">>; _ -> <<"pty_output">> end, <<>>),
        Pids = pids(Spawned),
        true = lists:all(fun(Pid) -> alive(Helper, Pid) end, Pids),
        Relay = maps:get(<<"helper_pid">>, maps:get(<<"data">>, Spawned)),
        ok = receipt_writer:event(Id, <<"fault_injection">>, #{kind => <<"helper_SIGKILL">>, pid => Relay}),
        0 = os_process("/bin/kill", ["-KILL", integer_to_list(Relay)]),
        <<"helper_failure">> = terminal(Id),
        dead_worker(Worker),
        gone(Helper, Pids),
        true = is_process_alive(Sup),
        note(Directory, Name, #{all_pids_absent => Pids, beam_alive => true})
    end || Mode <- [<<"pipe">>, <<"ctty">>]],

    {KilledWorker, KilledId} = start(<<"worker-kill">>, Hold#{<<"attachment">> => <<"ctty">>}, Helper, Directory, 5000),
    WorkerSpawn = event(KilledId, <<"spawned">>),
    ready(KilledId, <<"pty_output">>, <<>>),
    ok = receipt_writer:event(KilledId, <<"fault_injection">>, #{kind => <<"worker_kill">>}),
    exit(KilledWorker, kill),
    <<"worker_failure">> = terminal(KilledId),
    gone(Helper, pids(WorkerSpawn)),
    note(Directory, KilledId, #{all_pids_absent => pids(WorkerSpawn), beam_alive => true}),

    {TimeoutWorker, TimeoutId} = start(<<"timeout">>, Hold#{<<"attachment">> => <<"pipe">>}, Helper, Directory, 500),
    TimeoutSpawn = event(TimeoutId, <<"spawned">>),
    <<"timeout">> = terminal(TimeoutId),
    dead_worker(TimeoutWorker),
    gone(Helper, pids(TimeoutSpawn)),
    note(Directory, TimeoutId, #{all_pids_absent => pids(TimeoutSpawn), beam_alive => true}),

    {FinalWorker, FinalId} = start(<<"post-failure">>, Cat, Helper, Directory, 5000),
    _ = event(FinalId, <<"spawned">>),
    ok = session_worker:command(FinalWorker, #{<<"command">> => <<"close_stdin">>}),
    <<"completed">> = terminal(FinalId),
    dead_worker(FinalWorker),
    true = is_process_alive(Sup),
    true = is_process_alive(whereis(receipt_writer)),
    true = is_process_alive(whereis(session_sup)),
    [] = supervisor:which_children(session_sup),
    note(Directory, <<"result">>, #{outcome => <<"pass">>, sessions => 9, retries => 0,
        beam_pid => list_to_binary(os:getpid()), otp_release => list_to_binary(erlang:system_info(otp_release))}),
    ok.

start(Name, Spec, Helper, Directory, Deadline) ->
    Identity = #{<<"experiment">> => <<"ownership_001">>, <<"cell">> => Name, <<"session">> => Name},
    {ok, Worker} = session_sup:start_session(#{identity => Identity, spec => Spec, helper => Helper,
        receipt => filename:join(Directory, binary_to_list(Name) ++ ".jsonl"), owner => self(), deadline_ms => Deadline}),
    {Worker, Name}.
event(Id, Name) ->
    receive {session_event, Id, #{<<"event">> := Name} = Event} -> Event
    after 6000 -> error({event_timeout, Id, Name}) end.
terminal(Id) ->
    receive {session_terminal, Id, Outcome} -> Outcome
    after 7000 -> error({terminal_timeout, Id}) end.
dead_worker(Worker) ->
    Ref = monitor(process, Worker),
    receive {'DOWN', Ref, process, Worker, _} -> ok after 1000 -> error(worker_still_alive) end.
ready(Id, Stream, Acc) ->
    E = event(Id, Stream),
    Bytes = binary:decode_hex(maps:get(<<"hex">>, maps:get(<<"data">>, E))),
    Combined = <<Acc/binary, Bytes/binary>>,
    case binary:match(Combined, <<"ready">>) of nomatch -> ready(Id, Stream, Combined); _ -> ok end.
pids(#{<<"data">> := Data}) -> [maps:get(K, Data) || K <- [<<"helper_pid">>, <<"guardian_pid">>, <<"pid">>]].
alive(Helper, Pid) ->
    case os_process(Helper, ["--alive", integer_to_list(Pid)]) of
        0 -> true; 1 -> false; Other -> error({alive_check_failed, Pid, Other}) end.
gone(Helper, Pids) -> gone(Helper, Pids, erlang:monotonic_time(millisecond) + 3000).
gone(Helper, Pids, Deadline) ->
    case lists:any(fun(Pid) -> alive(Helper, Pid) end, Pids) of
        false -> ok;
        true ->
            case erlang:monotonic_time(millisecond) < Deadline of
                true -> receive after 10 -> gone(Helper, Pids, Deadline) end;
                false -> error({resources_still_alive, Pids})
            end
    end.
os_process(Executable, Args) ->
    Port = open_port({spawn_executable, Executable}, [binary, exit_status, {args, Args}, hide]),
    receive {Port, {exit_status, Code}} -> Code
    after 1500 -> erlang:port_close(Port), error({os_process_timeout, Executable}) end.
output(Directory, Id, Stream) ->
    {ok, Bytes} = file:read_file(filename:join(Directory, binary_to_list(Id) ++ ".jsonl")),
    iolist_to_binary([binary:decode_hex(maps:get(<<"hex">>, Data)) || Line <- binary:split(Bytes, <<"\n">>, [global]), Line =/= <<>>,
        #{<<"event">> := <<"helper_event">>, <<"data">> := #{<<"event">> := Kind, <<"data">> := Data}} <- [json:decode(Line)], Kind =:= Stream]).
note(Directory, Name, Data) ->
    File = filename:join(Directory, binary_to_list(Name) ++ ".check.json"),
    {ok, Fd} = file:open(File, [write, binary, exclusive]),
    ok = file:write(Fd, [json:encode(Data), $\n]), ok = file:sync(Fd), file:close(Fd).
