-module(receipt_writer).
-behaviour(gen_server).
-export([start_link/0, open/4, event/3, finish/3]).
-export([init/1, handle_call/3, handle_cast/2, handle_info/2, terminate/2]).

start_link() -> gen_server:start_link({local, ?MODULE}, ?MODULE, [], []).
open(Worker, Options, Identity, Owner) -> gen_server:call(?MODULE, {open, Worker, Options, Identity, Owner}, 2000).
event(Id, Kind, Data) -> gen_server:call(?MODULE, {event, Id, Kind, Data}, 2000).
finish(Id, Outcome, Details) -> gen_server:call(?MODULE, {finish, Id, Outcome, Details}, 2000).
init([]) -> {ok, #{}}.

handle_call({open, Worker, Options, Identity, Owner}, _From, State) ->
    Id = maps:get(<<"session">>, Identity),
    false = maps:is_key(Id, State),
    File = maps:get(receipt, Options),
    {ok, Fd} = file:open(File, [write, binary, exclusive, raw]),
    Monitor = erlang:monitor(process, Worker),
    Entry = #{fd => Fd, file => File, identity => Identity, seq => 0, monitor => Monitor, owner => Owner},
    E = append(Entry, <<"session_start">>, #{spec => maps:get(spec, Options),
        deadline_ms => maps:get(deadline_ms, Options), protocol_version => 1,
        environment_sha256 => binary:encode_hex(crypto:hash(sha256,
            term_to_binary(lists:sort(maps:to_list(maps:get(<<"environment">>, maps:get(spec, Options))))))),
        environment_fingerprint_encoding => <<"Erlang external term: sorted key/value list">>,
        helper => list_to_binary(maps:get(helper, Options)), retries => 0}),
    {reply, ok, State#{Id => E}};
handle_call({event, Id, Kind, Data}, _From, State) ->
    E = append(maps:get(Id, State), Kind, Data),
    {reply, ok, State#{Id := E}};
handle_call({finish, Id, Outcome, Details}, _From, State) ->
    E = maps:get(Id, State),
    seal(E, Outcome, Details),
    {reply, ok, maps:remove(Id, State)}.

handle_cast(_Message, State) -> {noreply, State}.
handle_info({'DOWN', Ref, process, _Pid, Reason}, State) ->
    Matches = [{Id, E} || {Id, E} <- maps:to_list(State), maps:get(monitor, E) =:= Ref],
    case Matches of
        [{Id, E}] ->
            seal(E, <<"worker_failure">>, #{reason => printable(Reason)}),
            {noreply, maps:remove(Id, State)};
        [] -> {noreply, State}
    end;
handle_info(_, State) -> {noreply, State}.

append(E, Kind, Data) ->
    Seq = maps:get(seq, E) + 1,
    Bytes = [json:encode(#{v => 1, identity => maps:get(identity, E), seq => Seq,
        unix_ns => erlang:system_time(nanosecond), monotonic_ns => erlang:monotonic_time(nanosecond),
        event => Kind, data => Data}), $\n],
    ok = file:write(maps:get(fd, E), Bytes),
    ok = file:sync(maps:get(fd, E)),
    E#{seq := Seq}.

seal(E, Outcome, Details) ->
    _ = append(E, <<"session_terminal">>, #{outcome => Outcome, details => Details}),
    ok = file:close(maps:get(fd, E)),
    File = maps:get(file, E),
    {ok, Bytes} = file:read_file(File),
    {ok, HashFd} = file:open(File ++ ".sha256", [write, binary, exclusive]),
    ok = file:write(HashFd, [binary:encode_hex(crypto:hash(sha256, Bytes)), $\n]),
    ok = file:sync(HashFd),
    ok = file:close(HashFd),
    ok = file:change_mode(File, 8#444),
    ok = file:change_mode(File ++ ".sha256", 8#444),
    erlang:demonitor(maps:get(monitor, E), [flush]),
    maps:get(owner, E) ! {session_terminal, maps:get(<<"session">>, maps:get(identity, E)), Outcome},
    ok.
printable(Term) -> iolist_to_binary(io_lib:format("~p", [Term])).
terminate(_Reason, State) ->
    maps:foreach(fun(_, E) -> file:close(maps:get(fd, E)) end, State), ok.
