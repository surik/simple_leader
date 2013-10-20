-module(leader_server).

-behaviour(gen_server).

%% API
-export([start_link/0, 
         new_election/0]).

%% gen_server callbacks
-export([init/1,
         handle_call/3,
         handle_cast/2,
         handle_info/2,
         terminate/2,
         code_change/3]).

-define(T, 300).
-define(PING, ping).
-define(PONG, pong).
-define(ALIVE, alive).
-define(FINETHANKS, fine).
-define(IMTHEKING, king).
-define(SET_STATE, set_state).

-record(state, {
        number :: integer(),
        timeout :: integer(),
        leader :: atom(),
        monitor_pid :: pid(),
        nodes :: list(atom())
}).

%%%===================================================================
%%% API
%%%===================================================================

%%--------------------------------------------------------------------
%% @doc
%% Starts the server
%%
%% @spec start_link() -> {ok, Pid} | ignore | {error, Error}
%% @end
%%--------------------------------------------------------------------
start_link() ->
    gen_server:start_link({global, {node(), server}}, ?MODULE, [], []).

%% @doc New leader election
new_election() ->
    gen_server:cast({global, {node(), server}}, new_election).

%%%===================================================================
%%% gen_server callbacks
%%%===================================================================

%%--------------------------------------------------------------------
%% @private
%% @doc
%% Initializes the server
%%
%% @spec init(Args) -> {ok, State} |
%%                     {ok, State, Timeout} |
%%                     ignore |
%%                     {stop, Reason}
%% @end
%%--------------------------------------------------------------------
init([]) ->
    case lists:member(node(), all_nodes_name()) of
        false -> {stop, no_a_cluster_member};
        true -> 
            Res = [net_adm:ping(N) || N <- all_nodes_name()],
            lager:debug("Ping result: ~p", [lists:zip(all_nodes_name(), Res)]),
            global:sync(),
            State = #state{timeout = application:get_env(leader, timeout, 300), 
                           number = get_number(), nodes = all_nodes_name()},
            MonitorPid = proc_lib:spawn_link(fun() -> monitor(State) end),
            yes = global:re_register_name({node(), monitor}, MonitorPid),
            {ok, State#state{monitor_pid = MonitorPid}}
    end.

%%--------------------------------------------------------------------
%% @private
%% @doc
%% Handling call messages
%%
%% @spec handle_call(Request, From, State) ->
%%                                   {reply, Reply, State} |
%%                                   {reply, Reply, State, Timeout} |
%%                                   {noreply, State} |
%%                                   {noreply, State, Timeout} |
%%                                   {stop, Reason, Reply, State} |
%%                                   {stop, Reason, State}
%% @end
%%--------------------------------------------------------------------
handle_call(_Request, _From, State) ->
    Reply = ok,
    {reply, Reply, State}.

%%--------------------------------------------------------------------
%% @private
%% @doc
%% Handling cast messages
%%
%% @spec handle_cast(Msg, State) -> {noreply, State} |
%%                                  {noreply, State, Timeout} |
%%                                  {stop, Reason, State}
%% @end
%%--------------------------------------------------------------------
handle_cast(new_election, State) ->
    {noreply, election(State)};

handle_cast(_Msg, State) ->
    {noreply, State}.

%%--------------------------------------------------------------------
%% @private
%% @doc
%% Handling all non call/cast messages
%%
%% @spec handle_info(Info, State) -> {noreply, State} |
%%                                   {noreply, State, Timeout} |
%%                                   {stop, Reason, State}
%% @end
%%--------------------------------------------------------------------
handle_info({?ALIVE, Node}, #state{nodes = Nodes, number = Number} = State) when length(Nodes) == Number ->
    lager:debug("receive {ALIVE, ~p}", [Node]),
    Res = [send({N, server}, {?IMTHEKING, node()}) || N <- Nodes],
    lager:debug("Send IMTHEKING to: ~p", [lists:zip(Nodes, Res)]),
    {noreply, monitor_set_state(State#state{leader = node()})};

handle_info({?ALIVE, Node}, State) ->
    lager:debug("receive {ALIVE, ~p}", [Node]),
    Res = send({Node, server}, {?FINETHANKS, node()}),
    lager:debug("Send FINETHANKS to: ~p", [{Node, Res}]),
    {noreply, election(State)};

handle_info({?PING, Node}, State) ->
    send({Node, monitor}, {?PONG, node()}), 
    {noreply, State};

handle_info({?IMTHEKING, Node}, State) ->
    lager:debug("receive {IMTHEKING, ~p}", [Node]),
    lager:info("Leader is ~p", [Node]),
    {noreply, monitor_set_state(State#state{leader = Node})};

handle_info(_Info, State) ->
    lager:warning("server: ~p", [_Info]),
    {noreply, State}.

%%--------------------------------------------------------------------
%% @private
%% @doc
%% This function is called by a gen_server when it is about to
%% terminate. It should be the opposite of Module:init/1 and do any
%% necessary cleaning up. When it returns, the gen_server terminates
%% with Reason. The return value is ignored.
%%
%% @spec terminate(Reason, State) -> void()
%% @end
%%--------------------------------------------------------------------
terminate(_Reason, _State) ->
    ok.

%%--------------------------------------------------------------------
%% @private
%% @doc
%% Convert process state when code is changed
%%
%% @spec code_change(OldVsn, State, Extra) -> {ok, NewState}
%% @end
%%--------------------------------------------------------------------
code_change(_OldVsn, State, _Extra) ->
    {ok, State}.

%%%===================================================================
%%% Internal functions
%%%===================================================================
monitor(State) ->
    ?MODULE:new_election(),
    monitor1(State).

monitor1(#state{timeout = Timeout} = State) ->
    send({State#state.leader, server}, {?PING, node()}),
    NewState = receive
        {?PONG, _Node} -> timer:sleep(Timeout), State;
        {?SET_STATE, State1} -> State1;
        _Info -> lager:warning("monitor: ~p", [_Info]), State
    after 4 * Timeout ->
        lager:debug("~p disappear. New election.", [State#state.leader]),
        new_election(),
        State
    end,
    monitor1(NewState).


-spec monitor_set_state(#state{}) -> #state{}.
monitor_set_state(State) ->
    send({node(), monitor}, {?SET_STATE, State}),
    State.

-spec election(State :: #state{}) -> NewState :: #state{}.
election(#state{timeout = Timeout, nodes = Nodes, number = Number} = State) ->
    lager:debug("election()"),
    Nodes1 = lists:sublist(Nodes, Number+1, length(Nodes)),
    Res = [send({N, server}, {?ALIVE, node()}) || N <- Nodes1],
    lager:debug("Send ALIVE to ~p", [lists:zip(Nodes1, Res)]),
    NewState = receive
        {?FINETHANKS, Node} -> 
            lager:debug("receive {FINETHANKS, ~p}", [Node]),
            receive
                {?IMTHEKING, Node} -> 
                    lager:debug("receive {IMTHEKING, ~p}", [Node]),
                    lager:info("Leader is ~p", [Node]),
                    State#state{leader = Node}
            after Timeout -> election(State)
            end;
        {?IMTHEKING, Node} -> 
            lager:debug("receive {IMTHEKING, ~p}", [Node]),
            lager:info("Leader is ~p", [Node]),
            State#state{leader = Node}
    after Timeout ->
        Res1 = [send({N, server}, {?IMTHEKING, node()}) || N <- Nodes],
        lager:debug("Send IMTHEKING to ~p", [lists:zip(Nodes, Res1)]),
        State#state{leader = node()}
    end,
    monitor_set_state(NewState).

-spec send(Name :: term(), Message :: term()) -> skip | pid().
send(Name, Msg) ->
    case global:whereis_name(Name) of
        undefined -> skip;
        _ -> global:send(Name, Msg)
    end.

-spec get_number() -> integer().
get_number() ->
    get_number(node(), all_nodes_name(), 1).

-spec get_number(Node :: atom(), Nodes :: [atom()], N :: integer()) -> integer(). 
get_number(_Node, [], _) -> 0;
get_number(Node, [Node | _], N) -> N;
get_number(Node, [_ | Nodes], N) -> get_number(Node, Nodes, N+1).

-spec all_nodes_name() -> [atom()].
all_nodes_name() ->
    application:get_env(leader, nodes, []).
