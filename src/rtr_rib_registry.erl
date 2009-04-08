%%%=====================================================================================================================
%%% Copyright (c) 2009, Bruno Rijsman
%%%
%%% Permission to use, copy, modify, and/or distribute this software for any purpose with or without fee is hereby 
%%% granted, provided that the above copyright notice and this permission notice appear in all copies.
%%%
%%% THE SOFTWARE IS PROVIDED "AS IS" AND THE AUTHOR DISCLAIMS ALL WARRANTIES WITH REGARD TO THIS SOFTWARE INCLUDING ALL 
%%% IMPLIED WARRANTIES OF MERCHANTABILITY AND FITNESS. IN NO EVENT SHALL THE AUTHOR BE LIABLE FOR ANY SPECIAL, DIRECT, 
%%% INDIRECT, OR CONSEQUENTIAL DAMAGES OR ANY DAMAGES WHATSOEVER RESULTING FROM LOSS OF USE, DATA OR PROFITS, WHETHER IN
%%% AN ACTION OF CONTRACT, NEGLIGENCE OR OTHER TORTIOUS ACTION, ARISING OUT OF OR IN CONNECTION WITH THE USE OR 
%%% PERFORMANCE OF THIS SOFTWARE.
%%%=====================================================================================================================

%% @author Bruno Rijsman
%% @copyright 2009 Bruno Rijsman

-module(rtr_rib_registry).
-author('Bruno Rijsman').

-behavior(gen_server).

-include("rtr_rib_registry.hrl").

%% public API

-export([start_link/0,
         stop/0,
         bind/3,
         unbind/3]).

%% gen_server callbacks

-export([init/1,
         handle_call/3,
         handle_cast/2,
         handle_info/2,
         terminate/2,
         code_change/3]).

%%----------------------------------------------------------------------------------------------------------------------

start_link() ->
    gen_server:start_link({local, rtr_rib_registry}, ?MODULE, [], []).

%%----------------------------------------------------------------------------------------------------------------------

stop() ->
    gen_server:call(rtr_rib_registry, {stop}).

%%----------------------------------------------------------------------------------------------------------------------

bind(RoutingInstance, Afi, Safi) ->
    gen_server:call(rtr_rib_registry, {bind, RoutingInstance, Afi, Safi}).

%%----------------------------------------------------------------------------------------------------------------------

unbind(RoutingInstance, Afi, Safi) ->
    gen_server:call(rtr_rib_registry, {unbind, RoutingInstance, Afi, Safi}).

%%----------------------------------------------------------------------------------------------------------------------

init([]) ->
    RibTable = ets:new(rtr_rib_table, []),
    State = #rtr_rib_registry_state{rib_table = RibTable},
    {ok, State}.

%%----------------------------------------------------------------------------------------------------------------------

handle_call({stop}, _From, State) ->
    #rtr_rib_registry_state{rib_table = RibTable} = State,
    ets:delete(RibTable),
    NewState = #rtr_rib_registry_state{rib_table = none},
    {stop, normal, stopped, NewState};

%%- - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - -

handle_call({bind, RoutingInstance, Afi, Safi}, _From, State) ->
    #rtr_rib_registry_state{rib_table = RibTable} = State,
    Key = #rtr_rib_table_key{routing_instance = RoutingInstance, afi = Afi, safi = Safi},
    NewValue = case ets:lookup(RibTable, Key) of
        [] ->
            RibPid = rtr_rib:start_link(RoutingInstance, Afi, Safi),
            #rtr_rib_table_value{ref_cnt = 1, rib_pid = RibPid};  
        [Value] ->
            #rtr_rib_table_value{ref_cnt = RefCnt} = Value,
            Value#rtr_rib_table_value{ref_cnt = RefCnt + 1}
    end,
    ets:insert(RibTable, {Key, NewValue}),
    {reply, ok, State};

%%- - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - -

handle_call({unbind, RoutingInstance, Afi, Safi}, _From, State) ->
    #rtr_rib_registry_state{rib_table = RibTable} = State,
    Key = #rtr_rib_table_key{routing_instance = RoutingInstance, afi = Afi, safi = Safi},
    [Value] = ets:lookup(RibTable, Key),
    #rtr_rib_table_value{ref_cnt = RefCnt, rib_pid = RibPid} = Value,
    if
        RefCnt == 0 ->
            rtr_rib:stop(RibPid),
            ets:delete(RibTable, Key);
        true ->
            NewValue = Value#rtr_rib_table_value{ref_cnt = RefCnt + 1},
            ets:insert(RibTable, {Key, NewValue})
    end,
    {reply, ok, State}.

%%----------------------------------------------------------------------------------------------------------------------

handle_cast(_Message, State) ->
    {noreply, State}.

%%----------------------------------------------------------------------------------------------------------------------

handle_info(_Info, State) ->
    {noreply, State}.

%%----------------------------------------------------------------------------------------------------------------------

terminate(_Reason, _State) ->
    ok.

%%----------------------------------------------------------------------------------------------------------------------

code_change(_OldVersion, State, _Extra) ->
    {ok, State}.

%%----------------------------------------------------------------------------------------------------------------------
