-module(session_identity).
-export([prepare/1, key/1]).
prepare(Options) ->
    Id0 = maps:get(identity, Options),
    Run = maps:get(<<"run">>, Id0, unicode:characters_to_binary(filename:basename(filename:dirname(maps:get(receipt, Options))))),
    Id = Id0#{<<"run">> => Run},
    _ = key(Id),
    Options#{identity := Id}.
key(Id) ->
    Values = [maps:get(K, Id) || K <- [<<"run">>, <<"experiment">>, <<"cell">>, <<"session">>]],
    true = lists:all(fun(V) -> is_binary(V) andalso byte_size(V) > 0 end, Values),
    list_to_tuple(Values).
