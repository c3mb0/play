-module(receipt_recovery).
-include_lib("kernel/include/file.hrl").
-export([recover/2, analyze/2]).
-define(LIMIT, 16777216).

%% No writer is started, no process is resumed, and no source file is modified.
recover(Source, Destination) ->
    try
        {Bytes, Stable} = snapshot(Source),
        Seal = case file:read_file(Source ++ ".sha256") of
            {ok, S} when byte_size(S) =< 4096 -> {present, S};
            {ok, _} -> {error, seal_too_large};
            {error, enoent} -> missing;
            {error, E} -> {error, E}
        end,
        Analysis0 = analyze(Bytes, Seal),
        Analysis = case Stable of
            true -> Analysis0;
            false -> Analysis0#{classification := <<"quarantined">>, source_changed => true}
        end,
        ok = file:make_dir(Destination),
        RawFile = filename:join(Destination, "snapshot.jsonl"),
        ok = write_new(RawFile, Bytes),
        SealHashes = case Seal of
            {present, SealBytes} ->
                ok = write_new(filename:join(Destination, "source.sha256"), SealBytes),
                #{<<"source.sha256">> => hash(SealBytes)};
            _ -> #{}
        end,
        Report = #{recovery_schema => 1, kind => <<"interpretation">>,
            source => unicode:characters_to_binary(filename:absname(Source)),
            captured_unix_ns => erlang:system_time(nanosecond), source_metadata_stable => Stable,
            raw_sha256 => hash(Bytes), analysis => Analysis,
            liveness => <<"unknown from journal bytes">>,
            policy => <<"snapshot only; no source modification, skipped records, synthesized events or replay">>},
        ReportBytes = iolist_to_binary([json:encode(Report), $\n]),
        ok = write_new(filename:join(Destination, "recovery.json"), ReportBytes),
        Hashes = SealHashes#{<<"snapshot.jsonl">> => hash(Bytes), <<"recovery.json">> => hash(ReportBytes)},
        ok = write_new(filename:join(Destination, "SHA256.json"), [json:encode(Hashes), $\n]),
        {ok, Report}
    catch Class:Reason -> {error, {Class, Reason}} end.

snapshot(Source) ->
    {ok, Fd} = file:open(Source, [read, binary, raw]),
    try
        {ok, Before} = file:read_file_info(Fd),
        true = Before#file_info.type =:= regular,
        true = Before#file_info.size =< ?LIMIT,
        Bytes = case file:read(Fd, ?LIMIT + 1) of {ok, B} -> B; eof -> <<>> end,
        true = byte_size(Bytes) =< ?LIMIT,
        {ok, After} = file:read_file_info(Fd),
        Stable = {Before#file_info.size, Before#file_info.mtime, Before#file_info.ctime, Before#file_info.inode}
              =:= {After#file_info.size, After#file_info.mtime, After#file_info.ctime, After#file_info.inode},
        {Bytes, Stable andalso byte_size(Bytes) =:= After#file_info.size}
    after file:close(Fd) end.

write_new(File, Bytes) ->
    {ok, Fd} = file:open(File, [write, binary, exclusive, raw]),
    try ok = file:write(Fd, Bytes), ok = file:sync(Fd)
    after file:close(Fd) end,
    file:change_mode(File, 8#444).

analyze(Bytes, Seal) when byte_size(Bytes) =< ?LIMIT ->
    Initial = #{seq => 0, identity => null, terminal => null, offset => 0,
                command_seq => 0, helper_seq => 0, metadata_complete => false,
                start_unix_ns => null, last_unix_ns => null, last_mono => undefined},
    {State, Error, Tail} = scan(Bytes, Initial),
    Integrity = integrity(Bytes, Seal),
    BadIntegrity = not lists:member(Integrity, [<<"absent">>, <<"verified">>]),
    Class = case {Error, BadIntegrity, maps:get(terminal, State)} of
        {null, false, null} -> <<"incomplete">>;
        {null, false, _} -> <<"complete">>;
        _ -> <<"quarantined">>
    end,
    #{classification => Class, integrity => Integrity, validation_error => Error,
      total_bytes => byte_size(Bytes), valid_prefix_bytes => maps:get(offset, State),
      valid_events => maps:get(seq, State), trailing_bytes => Tail,
      identity => maps:get(identity, State), metadata_complete => maps:get(metadata_complete, State),
      start_unix_ns => maps:get(start_unix_ns, State), last_observed_unix_ns => maps:get(last_unix_ns, State),
      observed_terminal => maps:get(terminal, State),
      outcome => case Class of <<"complete">> -> maps:get(<<"outcome">>, maps:get(terminal, State)); _ -> <<"unknown">> end}.

scan(<<>>, State) -> {State, null, 0};
scan(Bytes, #{terminal := T} = State) when T =/= null ->
    {State, #{offset => maps:get(offset, State), reason => <<"data after terminal event">>}, byte_size(Bytes)};
scan(Bytes, State) ->
    case binary:match(Bytes, <<"\n">>) of
        nomatch -> {State, null, byte_size(Bytes)};
        {Length, 1} when Length > 1048576 ->
            {State, #{offset => maps:get(offset, State), reason => <<"journal line exceeds 1 MiB">>}, byte_size(Bytes)};
        {Length, 1} ->
            <<Line:Length/binary, $\n, Rest/binary>> = Bytes,
            try validate(json:decode(Line), State) of
                Next -> scan(Rest, Next#{offset := maps:get(offset, State) + Length + 1})
            catch Class:Reason ->
                {State, #{offset => maps:get(offset, State), reason => printable({Class, Reason})}, byte_size(Bytes)}
            end
    end.

validate(Event, State) ->
    Expected = maps:get(seq, State) + 1,
    #{<<"v">> := 1, <<"seq">> := Expected, <<"identity">> := Id,
      <<"unix_ns">> := Unix, <<"monotonic_ns">> := Mono,
      <<"event">> := Kind, <<"data">> := Data} = Event,
    true = is_integer(Unix) andalso is_integer(Mono) andalso is_binary(Kind) andalso is_map(Data),
    true = maps:get(last_mono, State) =:= undefined orelse Mono >= maps:get(last_mono, State),
    case Expected of
        1 ->
            <<"session_start">> = Kind,
            [begin Value = maps:get(K, Id), true = is_binary(Value) andalso byte_size(Value) > 0 end
             || K <- [<<"experiment">>, <<"cell">>, <<"session">>]];
        _ -> Id = maps:get(identity, State), true = Kind =/= <<"session_start">>
    end,
    S = State#{seq := Expected, identity := Id, last_unix_ns := Unix, last_mono := Mono},
    case Kind of
        <<"session_start">> ->
            S#{start_unix_ns := Unix, metadata_complete := metadata_complete(Data)};
        <<"session_terminal">> ->
            true = is_binary(maps:get(<<"outcome">>, Data)), S#{terminal := Data};
        <<"command">> ->
            Next = maps:get(command_seq, S) + 1,
            #{<<"v">> := 1, <<"identity">> := Id, <<"seq">> := Next, <<"command">> := C} = Data,
            true = is_binary(C), S#{command_seq := Next};
        <<"helper_event">> ->
            Next = maps:get(helper_seq, S) + 1,
            _ = port_protocol:decode(iolist_to_binary(json:encode(Data)), Id, Next),
            S#{helper_seq := Next};
        _ -> S
    end.

metadata_complete(#{<<"receipt_schema">> := 2} = Data) ->
    [_ = maps:get(K, Data) || K <- [<<"run_id">>, <<"executable">>, <<"helper">>, <<"platform">>,
        <<"erlang_modules">>, <<"input_policy">>, <<"requested_topology">>, <<"deadline_ms">>, <<"protocol_version">>]],
    Spec = maps:get(<<"spec">>, Data),
    [_ = maps:get(K, Spec) || K <- [<<"executable">>, <<"argv">>, <<"environment">>, <<"cwd">>, <<"attachment">>]],
    Hash = receipt_metadata:environment_hash(maps:get(<<"environment">>, Spec)),
    Hash = maps:get(<<"environment_sha256">>, Data),
    true = is_binary(maps:get(<<"run_id">>, Data)),
    true = is_map(maps:get(<<"platform">>, Data)),
    true = is_map(maps:get(<<"erlang_modules">>, Data)),
    true = is_list(maps:get(<<"argv">>, Spec)),
    true = is_binary(maps:get(<<"cwd">>, Spec)),
    Executable = maps:get(<<"executable">>, Data),
    ExePath = maps:get(<<"executable">>, Spec),
    ExePath = maps:get(<<"path">>, Executable),
    Helper = maps:get(<<"helper">>, Data),
    ExeKnown = fingerprint_valid(Executable), HelperKnown = fingerprint_valid(Helper),
    Reported = maps:get(<<"reported">>, Helper),
    ExeKnown andalso HelperKnown andalso is_binary(maps:get(<<"helper_version">>, Reported, null))
        andalso maps:get(<<"protocol_version">>, Reported, null) =:= 1;
metadata_complete(_) -> false.

fingerprint_valid(#{<<"path">> := Path, <<"sha256">> := null, <<"error">> := Error}) ->
    true = is_binary(Path) andalso is_binary(Error), false;
fingerprint_valid(#{<<"path">> := Path, <<"sha256">> := Hash, <<"bytes">> := Size}) ->
    true = is_binary(Path) andalso is_integer(Size) andalso Size >= 0,
    32 = byte_size(binary:decode_hex(Hash)), true.

integrity(_Bytes, missing) -> <<"absent">>;
integrity(_Bytes, {error, _}) -> <<"unreadable">>;
integrity(Bytes, {present, Seal}) ->
    try binary:decode_hex(string:trim(Seal)) of
        Digest when byte_size(Digest) =:= 32 ->
            case crypto:hash(sha256, Bytes) =:= Digest of true -> <<"verified">>; false -> <<"mismatch">> end;
        _ -> <<"malformed">>
    catch _:_ -> <<"malformed">> end.
hash(Bytes) -> binary:encode_hex(crypto:hash(sha256, Bytes)).
printable(Term) -> iolist_to_binary(io_lib:format("~p", [Term])).
