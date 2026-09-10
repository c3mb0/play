-module(session_sup).
-behaviour(supervisor).
-export([start_link/0, start_session/1, init/1]).
start_link() -> supervisor:start_link({local, ?MODULE}, ?MODULE, []).
start_session(Options) ->
    supervisor:start_child(?MODULE, #{id => make_ref(),
        start => {session_worker, start_link, [Options]},
        restart => temporary, shutdown => 2000}).
init([]) -> {ok, {#{strategy => one_for_one, intensity => 3, period => 10}, []}}.
