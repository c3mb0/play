-module(pty_lab_sup).
-behaviour(supervisor).
-export([start_link/0, init/1]).
start_link() -> supervisor:start_link({local, ?MODULE}, ?MODULE, []).
init([]) ->
    {ok, {#{strategy => one_for_one, intensity => 3, period => 10}, [
        #{id => receipt_writer, start => {receipt_writer, start_link, []}},
        #{id => session_sup, start => {session_sup, start_link, []}, type => supervisor}
    ]}}.
