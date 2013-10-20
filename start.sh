#!/usr/bin/env sh

NAME=${1:-"1"}
erl -name $NAME@127.0.0.1 -pa ebin deps/*/ebin -config leader.config -s leader -cookie leader_cookie
