%% Unrecorded, owner-bound interactive policy over the shared framed helper.
-module(interactive_session).
-behaviour(gen_server).
-export([start_link/1, command/2]).
-export([init/1, handle_call/3, handle_cast/2, handle_info/2, terminate/2]).
start_link(Options) -> gen_server:start_link(?MODULE, Options, []).
command(Pid, Command) ->
    try gen_server:call(Pid, Command, 2000)
    catch exit:_ -> {error, session_closed} end.
init(#{owner := Owner, helper := Helper, spec := Spec, identity := Identity}) ->
    process_flag(trap_exit, true),
    monitor(process, Owner),
    Port = open_port({spawn_executable, Helper}, [binary,{packet,4},use_stdio,exit_status,
        {args,["--port"]},hide,{busy_limits_port,{65536,131072}}]),
    S = #{port=>Port,owner=>Owner,identity=>Identity,seq=>0,received=>0,outstanding=>0,closing=>false},
    case send(#{<<"command">>=><<"spawn">>,<<"spec">>=>Spec#{<<"interactive">>=>true}}, S) of
        {ok,Next} -> {ok,Next};
        {error,Reason,_} -> {stop,Reason}
    end.
handle_call(#{<<"command">> := <<"credit">>, <<"bytes">> := N} = C, {Owner,_},
            #{owner:=Owner,outstanding:=Pending,closing:=false}=S)
        when is_integer(N), N > 0, N =< Pending ->
    reply_send(C,S#{outstanding:=Pending-N});
handle_call(#{<<"command">> := <<"credit">>}, _, S) -> {reply,{error,invalid_credit},S};
handle_call(#{<<"command">> := Name}=C, {Owner,_}, #{owner:=Owner,closing:=false}=S)
        when Name =:= <<"write">>; Name =:= <<"resize">>; Name =:= <<"close">> ->
    case Name of
        <<"close">> -> erlang:send_after(2000,self(),cleanup_deadline), reply_send(C,S#{closing:=true});
        _ -> reply_send(C,S)
    end;
handle_call(_,_,S) -> {reply,{error,invalid_command},S}.
reply_send(C,S) ->
    case send(C,S) of
        {ok,Next} -> {reply,ok,Next};
        {error,R,Next} -> {stop,normal,{error,R},Next}
    end.
send(C,#{port:=P,identity:=Id,seq:=Seq}=S) ->
    case port_protocol:send(P,port_protocol:encode(C#{<<"v">>=>1,<<"identity">>=>Id,<<"seq">>=>Seq+1})) of
        ok -> {ok,S#{seq:=Seq+1}};
        {error,R} -> {error,R,S}
    end.
handle_cast(_,S) -> {noreply,S}.
handle_info({P,{data,B}},#{port:=P,owner:=Owner,identity:=Id,received:=Seq,outstanding:=Pending}=S) ->
    try port_protocol:decode(B,Id,Seq+1) of
        E ->
            N = case E of
                #{<<"event">> := <<"pty_output">>, <<"data">> := #{<<"hex">>:=Hex}} -> byte_size(Hex) div 2;
                _ -> 0
            end,
            true = Pending+N =< 65536,
            Owner ! {interactive_event,self(),E},
            {noreply,S#{received:=Seq+1,outstanding:=Pending+N}}
    catch _:_ -> Owner ! {interactive_failure,self(),protocol_failure}, {stop,normal,S} end;
handle_info({'DOWN',_,process,Owner,_},#{owner:=Owner}=S) ->
    %% No detach/rebind: input authority ends immediately; cleanup after 2 s grace.
    erlang:send_after(2000,self(),owner_expired), {noreply,S#{closing:=true}};
handle_info(owner_expired,S) ->
    erlang:send_after(2000,self(),cleanup_deadline),
    case send(#{<<"command">>=><<"close">>},S) of
        {ok,Next} -> {noreply,Next}; _ -> {stop,normal,S}
    end;
handle_info(cleanup_deadline,S) -> {stop,normal,S};
handle_info({P,{exit_status,Code}},#{port:=P,owner:=Owner}=S) ->
    Owner ! {interactive_end,self(),Code}, {stop,normal,S};
handle_info({'EXIT',P,normal},#{port:=P}=S) -> {noreply,S};
handle_info({'EXIT',P,Reason},#{port:=P,owner:=Owner}=S) ->
    Owner ! {interactive_failure,self(),Reason}, {stop,normal,S};
handle_info(_,S) -> {noreply,S}.
terminate(_,#{port:=P}) -> try erlang:port_close(P) catch error:badarg -> ok end, ok.
