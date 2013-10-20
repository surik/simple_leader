-module(leader).

-compile([export_all]).

start() ->
    ok = application:start(lager),
    ok = application:start(leader).
    
stop() ->
    ok = application:stop(lager),
    ok = application:stop(leader).
