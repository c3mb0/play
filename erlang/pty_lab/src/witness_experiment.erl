-module(witness_experiment).
-export([run/2]).

run(Root, Directory) ->
    {ok, _} = application:ensure_all_started(pty_lab),
    {ok, ConfigBytes} = file:read_file(filename:join(Root, "receipts/gate-20260910T194539Z/terminal-config.json")),
    Spec = #{<<"executable">> => list_to_binary(filename:join(Root, "target/debug/hello_witness")),
        <<"argv">> => [], <<"cwd">> => list_to_binary(Root),
        <<"environment">> => #{<<"LANG">> => <<"C">>, <<"PATH">> => <<"/usr/bin:/bin">>, <<"TERM">> => <<"xterm-256color">>},
        <<"terminal">> => json:decode(ConfigBytes)},
    Input = <<"hello\n">>,
    [cell(Mode, Spec#{<<"attachment">> => Mode}, Input, Root, Directory) || Mode <- [<<"pipe">>, <<"slave">>]],
    Pipe = journal(filename:join(Directory, "pipe.jsonl")),
    Pty = journal(filename:join(Directory, "slave.jsonl")),
    HeaderA = maps:get(<<"data">>, hd(Pipe)), HeaderB = maps:get(<<"data">>, hd(Pty)),
    [begin
        Equal = maps:get(Key, HeaderA), Equal = maps:get(Key, HeaderB)
     end || Key <- [<<"environment_sha256">>, <<"deadline_ms">>, <<"protocol_version">>, <<"requested_topology">>]],
    [begin
        HashA = maps:get(<<"sha256">>, maps:get(Key, HeaderA)),
        HashA = maps:get(<<"sha256">>, maps:get(Key, HeaderB))
     end || Key <- [<<"executable">>, <<"helper">>]],
    DefinitionA = maps:remove(<<"attachment">>, maps:get(<<"spec">>, HeaderA)),
    DefinitionA = maps:remove(<<"attachment">>, maps:get(<<"spec">>, HeaderB)),
    [begin
        Input = bytes(Entries, <<"input_written">>),
        [#{<<"code">> := 0, <<"signal">> := null}] = data(Entries, <<"child_exit">>),
        #{<<"event">> := <<"session_terminal">>, <<"data">> := #{<<"outcome">> := <<"completed">>}} = lists:last(Entries)
     end || Entries <- [Pipe, Pty]],
    PipeBytes = bytes(Pipe, <<"stdout">>), PtyBytes = bytes(Pty, <<"pty_output">>),
    <<>> = bytes(Pipe, <<"stderr">>),
    <<"received: hello\n">> = PipeBytes,
    true = lists:member(PtyBytes, [<<"input> hello\r\nreceived: hello\r\n">>,
                                  <<"hello\r\ninput> received: hello\r\n">>]),
    [] = supervisor:which_children(session_sup),
    File = filename:join(Directory, "comparison.json"),
    {ok, Fd} = file:open(File, [write, binary, exclusive]),
    Report = #{kind => <<"interpretation">>, outcome => <<"pass">>, pairs => 1, retries => 0,
        same_definition_except_attachment => true, same_input_written => true,
        pipe_output_hex => binary:encode_hex(PipeBytes), pty_output_hex => binary:encode_hex(PtyBytes),
        pipe_output => PipeBytes, pty_output => PtyBytes,
        prompt_flip => true, reply_content_equal => true, child_exit_codes => [0,0],
        interpretation => <<"Constructed witness enables prompt for terminal stdin; configured echo/ONLCR explain additional raw PTY bytes">>,
        limits => <<"One constructed pair; scheduling not identical; no inference about unmodified applications">>},
    ok = file:write(Fd, [json:encode(Report), $\n]), ok = file:sync(Fd), ok = file:close(Fd), ok.

cell(Mode, Spec, Input, Root, Directory) ->
    Identity = #{<<"experiment">> => <<"witness_001">>, <<"cell">> => Mode, <<"session">> => Mode},
    {ok, Worker} = session_sup:start_session(#{identity => Identity, spec => Spec,
        helper => filename:join(Root, "target/debug/pty_helper"),
        receipt => filename:join(Directory, binary_to_list(Mode) ++ ".jsonl"), deadline_ms => 5000, owner => self()}),
    receive {session_event, Mode, #{<<"event">> := <<"spawned">>}} -> ok
    after 3000 -> error({spawn_timeout, Mode}) end,
    SpawnReceived = erlang:monotonic_time(nanosecond),
    ok = receipt_writer:event(Mode, <<"input_timing_policy">>, #{delay_ms => 100,
        anchor => <<"experiment receives spawned">>, spawn_received_monotonic_ns => SpawnReceived}),
    receive after 100 -> ok end,
    RequestedAt = erlang:monotonic_time(nanosecond),
    ok = receipt_writer:event(Mode, <<"input_timing_observation">>, #{delay_ns => RequestedAt - SpawnReceived,
        meaning => <<"elapsed to write-request preparation, not exact OS delivery">>}),
    ok = session_worker:command(Worker, #{<<"command">> => <<"write">>, <<"hex">> => binary:encode_hex(Input)}),
    receive {session_terminal, Mode, <<"completed">>} -> ok
    after 6500 -> error({session_not_completed, Mode}) end,
    Monitor = monitor(process, Worker),
    receive
        {'DOWN', Monitor, process, Worker, Reason} when Reason =:= normal; Reason =:= noproc -> ok;
        {'DOWN', Monitor, process, Worker, Reason} -> error({worker_exit, Reason})
    after 1000 -> error(worker_not_ended) end.

journal(File) ->
    {ok, Bytes} = file:read_file(File), {ok, Seal} = file:read_file(File ++ ".sha256"),
    #{classification := <<"complete">>, integrity := <<"verified">>, metadata_complete := true} =
        receipt_recovery:analyze(Bytes, {present, Seal}),
    [json:decode(Line) || Line <- binary:split(Bytes, <<"\n">>, [global]), Line =/= <<>>].
data(Entries, Name) ->
    [Data || #{<<"event">> := <<"helper_event">>,
        <<"data">> := #{<<"event">> := Kind, <<"data">> := Data}} <- Entries, Kind =:= Name].
bytes(Entries, Name) -> iolist_to_binary([binary:decode_hex(maps:get(<<"hex">>, Data)) || Data <- data(Entries, Name)]).
