-module(receipt_experiment).
-export([capture/3, recover/2]).

capture(Root, Directory, Mode) ->
    {ok, _} = application:ensure_all_started(pty_lab),
    Executable = case Mode of
        "normal" -> filename:join(Root, "target/debug/topology_probe");
        "interrupt" -> filename:join(Root, "target/debug/lifetime_probe")
    end,
    Args = case Mode of
        "normal" -> [<<"--snapshot">>, list_to_binary(filename:join(Directory, "observation.json"))];
        "interrupt" -> []
    end,
    Spec = #{<<"executable">> => list_to_binary(Executable), <<"argv">> => Args,
             <<"environment">> => #{<<"LANG">> => <<"C">>, <<"PATH">> => <<"/usr/bin:/bin">>, <<"TERM">> => <<"xterm-256color">>},
             <<"cwd">> => list_to_binary(Root), <<"attachment">> => <<"pipe">>},
    Id = list_to_binary(Mode),
    Identity = #{<<"experiment">> => <<"receipt_001">>, <<"cell">> => Id, <<"session">> => Id},
    {ok, _Worker} = session_sup:start_session(#{identity => Identity, spec => Spec,
        helper => filename:join(Root, "target/debug/pty_helper"),
        receipt => filename:join(Directory, Mode ++ ".jsonl"), deadline_ms => 5000, owner => self()}),
    case Mode of
        "normal" ->
            receive {session_terminal, Id, <<"completed">>} -> ok after 7000 -> error(normal_timeout) end;
        "interrupt" ->
            Spawned = receive {session_event, Id, #{<<"event">> := <<"spawned">>, <<"data">> := Data}} -> Data
                      after 3000 -> error(spawn_timeout) end,
            ready(Id, <<>>, erlang:monotonic_time(millisecond) + 3000),
            ok = receipt_writer:event(Id, <<"fault_injection_armed">>, #{kind => <<"external_BEAM_SIGKILL">>}),
            File = filename:join(Directory, "armed.json"),
            Pending = filename:join(Directory, "armed.pending.json"),
            {ok, Fd} = file:open(Pending, [write, binary, exclusive]),
            ok = file:write(Fd, [json:encode(Spawned#{<<"beam_pid">> => list_to_binary(os:getpid())}), $\n]),
            ok = file:sync(Fd), ok = file:close(Fd),
            ok = file:make_link(Pending, File),
            receive after 10000 -> error(fault_not_injected) end
    end.
ready(Id, Acc, Deadline) ->
    Remaining = max(0, Deadline - erlang:monotonic_time(millisecond)),
    receive {session_event, Id, #{<<"event">> := <<"stdout">>, <<"data">> := #{<<"hex">> := Hex}}} ->
        Bytes = binary:decode_hex(Hex), Combined = <<Acc/binary, Bytes/binary>>,
        case binary:match(Combined, <<"ready">>) of
            nomatch -> ready(Id, Combined, Deadline);
            _ -> ok
        end
    after Remaining -> error(ready_timeout) end.

recover(Source, Destination) ->
    {ok, _} = application:ensure_all_started(crypto),
    case receipt_recovery:recover(Source, Destination) of
        {ok, _} -> ok;
        {error, Reason} -> error({recovery_failed, Reason})
    end.
