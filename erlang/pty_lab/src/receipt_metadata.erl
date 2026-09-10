-module(receipt_metadata).
-export([build/1, environment_hash/1]).

build(Options) ->
    Spec = maps:get(spec, Options),
    Helper = maps:get(helper, Options),
    Mode = maps:get(<<"attachment">>, Spec),
    #{receipt_schema => 2,
      run_id => maps:get(<<"run">>, maps:get(identity, Options)),
      spec => Spec,
      executable => fingerprint(maps:get(<<"executable">>, Spec)),
      helper => (fingerprint(Helper))#{reported => helper_metadata(Helper)},
      fingerprint_scope => <<"file bytes read before spawn; not exec-time attestation">>,
      environment_sha256 => environment_hash(maps:get(<<"environment">>, Spec)),
      environment_fingerprint_encoding => <<"sorted UTF-8 key/value pairs; each field u32 big-endian byte length then bytes">>,
      requested_topology => #{new_session => true, controlling_tty => Mode =:= <<"ctty">>,
          foreground_group => case Mode of <<"ctty">> -> <<"subject">>; _ -> <<"not_configured">> end},
      deadline_ms => maps:get(deadline_ms, Options), protocol_version => 1, retries => 0,
      input_policy => <<"ordered command entries are requests; input_written entries are observations">>,
      platform => #{os_type => printable(os:type()), os_version => printable(os:version()),
          architecture => list_to_binary(erlang:system_info(system_architecture)),
          otp_release => list_to_binary(erlang:system_info(otp_release)),
          system_version => list_to_binary(erlang:system_info(system_version))},
      erlang_modules => maps:from_list([{atom_to_binary(M), binary:encode_hex(M:module_info(md5))}
          || M <- [pty_lab_app, pty_lab_sup, session_sup, session_worker, port_protocol,
                   receipt_writer, receipt_metadata]]),
      erlang_module_fingerprint_encoding => <<"module_info(md5), code identity not cryptographic custody">>}.

environment_hash(Environment) ->
    Fields = [[field(Key), field(Value)] || {Key, Value} <- lists:sort(maps:to_list(Environment))],
    binary:encode_hex(crypto:hash(sha256, Fields)).
field(Bytes) when is_binary(Bytes) -> [<<(byte_size(Bytes)):32/unsigned-big>>, Bytes].

fingerprint(Path) ->
    Base = #{path => unicode:characters_to_binary(Path), captured_unix_ns => erlang:system_time(nanosecond)},
    case file:read_file(Path) of
        {ok, Bytes} -> Base#{sha256 => binary:encode_hex(crypto:hash(sha256, Bytes)), bytes => byte_size(Bytes)};
        {error, Reason} -> Base#{sha256 => null, error => atom_to_binary(Reason)}
    end.

helper_metadata(Helper) ->
    try open_port({spawn_executable, Helper}, [binary, exit_status, {args, ["--metadata"]}, hide]) of
        Port ->
            try collect(Port, <<>>, erlang:monotonic_time(millisecond) + 1000)
            after try erlang:port_close(Port) catch error:badarg -> ok end end
    catch Class:Reason -> #{error => printable({Class, Reason})} end.
collect(Port, Bytes, Deadline) ->
    Remaining = max(0, Deadline - erlang:monotonic_time(millisecond)),
    receive
        {Port, {data, Chunk}} when byte_size(Bytes) + byte_size(Chunk) =< 4096 ->
            collect(Port, <<Bytes/binary, Chunk/binary>>, Deadline);
        {Port, {data, _}} -> #{error => <<"metadata exceeds 4096 bytes">>};
        {Port, {exit_status, 0}} -> json:decode(Bytes);
        {Port, {exit_status, Code}} -> #{error => <<"metadata process failed">>, exit_code => Code}
    after Remaining -> #{error => <<"metadata timeout">>} end.
printable(Term) -> iolist_to_binary(io_lib:format("~p", [Term])).
