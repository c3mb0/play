-module(receipt_writer).
-behaviour(gen_server).
-export([start_link/0, open/4, event/3, finish/3, publish/4]).
-export([init/1, handle_call/3, handle_cast/2, handle_info/2, terminate/2]).

start_link() -> gen_server:start_link({local, ?MODULE}, ?MODULE, [], []).
open(Worker, Options, Identity, Owner) -> request({open, Worker, Options, Identity, Owner}).
event(KeyOrWorker, Kind, Data) -> request({event, KeyOrWorker, Kind, Data}).
finish(Key, Outcome, Details) -> request({finish, Key, Outcome, Details}).
request(Message) ->
    try gen_server:call(?MODULE, Message, 2000)
    catch exit:Reason -> {error, {writer_unavailable, Reason}} end.
init([]) -> {ok, #{sessions => #{}, used => #{}}}.

handle_call({open, Worker, Options, Identity, Owner}, _From, State) ->
    Key = session_identity:key(Identity),
    case maps:is_key(Key, maps:get(used, State)) of
        true -> {reply, {error, duplicate_identity}, State};
        false ->
            case attempt(fun() -> open_entry(Worker, Options, Identity, Owner) end) of
                {ok, E} ->
                    {reply, ok, State#{sessions := (maps:get(sessions, State))#{Key => E},
                        used := (maps:get(used, State))#{Key => true}}};
                {error, Reason} -> {reply, {error, Reason}, State}
            end
    end;
handle_call({event, Reference, Kind, Data}, _From, State) ->
    case lookup(Reference, maps:get(sessions, State)) of
        error -> {reply, {error, unknown_session}, State};
        {Key, E} ->
            case attempt(fun() -> append(E, Kind, Data) end) of
                {ok, Next} -> {reply, ok, State#{sessions := (maps:get(sessions, State))#{Key := Next}}};
                {error, Reason} ->
                    maps:get(worker, E) ! {receipt_failed, Key, Reason},
                    release(E),
                    {reply, {error, Reason}, remove(Key, State)}
            end
    end;
handle_call({finish, Key, Outcome, Details}, _From, State) ->
    case maps:find(Key, maps:get(sessions, State)) of
        error -> {reply, {error, unknown_session}, State};
        {ok, E} ->
            Result = attempt(fun() -> seal(E, Outcome, Details) end),
            release(E),
            case Result of
                {ok, ok} -> publish(E, Outcome, Details, sealed);
                {error, Reason} -> publish(E, <<"receipt_failure">>, Details#{receipt_error => printable(Reason)}, partial)
            end,
            {reply, ok, remove(Key, State)}
    end.
handle_cast(_, State) -> {noreply, State}.
handle_info({'DOWN', Ref, process, _Pid, Reason}, State) ->
    Matches = [{K,E} || {K,E} <- maps:to_list(maps:get(sessions, State)), maps:get(monitor,E) =:= Ref],
    case Matches of
        [{Key,E}] ->
            Details = #{reason => printable(Reason)},
            Result = attempt(fun() -> seal(E, <<"worker_failure">>, Details) end),
            release(E),
            case Result of
                {ok,ok} -> publish(E, <<"worker_failure">>, Details, sealed);
                {error,Error} -> publish(E, <<"receipt_failure">>, Details#{receipt_error => printable(Error)}, partial)
            end,
            {noreply, remove(Key,State)};
        [] -> {noreply, State}
    end;
handle_info(_, State) -> {noreply, State}.

open_entry(Worker, Options, Identity, Owner) ->
    File = maps:get(receipt,Options),
    Fd = checked(file:open(File,[write,binary,exclusive,raw]), open),
    try
        E = #{fd => Fd, file => File, identity => Identity, seq => 0, worker => Worker,
              owner => Owner, notify_id => maps:get(notify_id,Options,maps:get(<<"session">>,Identity)),
              api => maps:get(api,Options,false)},
        Next = append(E,<<"session_start">>,maps:get(metadata,Options)),
        Next#{monitor => monitor(process,Worker)}
    catch C:R:S -> file:close(Fd), erlang:raise(C,R,S) end.
append(E, Kind, Data) ->
    Seq = maps:get(seq,E)+1,
    Bytes = [json:encode(#{v=>1,identity=>maps:get(identity,E),seq=>Seq,
        unix_ns=>erlang:system_time(nanosecond),monotonic_ns=>erlang:monotonic_time(nanosecond),event=>Kind,data=>Data}),$\n],
    checked(file:write(maps:get(fd,E),Bytes),write),
    checked(file:sync(maps:get(fd,E)),sync), E#{seq:=Seq}.
seal(E, Outcome, Details) ->
    _ = append(E,<<"session_terminal">>,#{outcome=>Outcome,details=>Details}),
    checked(file:close(maps:get(fd,E)),close), File = maps:get(file,E),
    Bytes = checked(file:read_file(File),read_seal),
    Fd = checked(file:open(File++".sha256",[write,binary,exclusive]),open_seal),
    try
        checked(file:write(Fd,[binary:encode_hex(crypto:hash(sha256,Bytes)),$\n]),write_seal),
        checked(file:sync(Fd),sync_seal)
    after file:close(Fd) end,
    checked(file:change_mode(File,8#444),seal_mode),
    checked(file:change_mode(File++".sha256",8#444),checksum_mode), ok.
checked(ok,_) -> ok;
checked({ok,V},_) -> V;
checked({error,R},Stage) -> throw({receipt_io,Stage,R}).
attempt(Fun) -> try {ok,Fun()} catch throw:R -> {error,R}; C:R -> {error,{receipt_failure,C,R}} end.
lookup(Pid, Entries) when is_pid(Pid) ->
    case [{K,E} || {K,E} <- maps:to_list(Entries), maps:get(worker,E)=:=Pid] of [Pair] -> Pair; [] -> error end;
lookup(Key, Entries) -> case maps:find(Key,Entries) of {ok,E} -> {Key,E}; error -> error end.
remove(Key, State) -> State#{sessions := maps:remove(Key,maps:get(sessions,State))}.
release(E) -> file:close(maps:get(fd,E)), demonitor(maps:get(monitor,E),[flush]), ok.
publish(E, Outcome, Details, ReceiptStatus) ->
    case maps:get(api,E,false) of
        true ->
            Result = #{identity=>maps:get(identity,E),receipt=>maps:get(file,E),outcome=>Outcome,
                child_exit=>maps:get(child_exit,Details,null),receipt_status=>ReceiptStatus,
                cleanup=>#{state=>unverified,reported_pids=>maps:get(reported_pids,Details,[])},details=>Details},
            maps:get(owner,E) ! {session_result,session_identity:key(maps:get(identity,E)),Result};
        false -> maps:get(owner,E) ! {session_terminal,maps:get(notify_id,E),Outcome}
    end, ok.
printable(Term) -> iolist_to_binary(io_lib:format("~p",[Term])).
terminate(_, State) -> maps:foreach(fun(_,E)->file:close(maps:get(fd,E)) end,maps:get(sessions,State)),ok.
