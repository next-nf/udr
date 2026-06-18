%% SPDX-License-Identifier: AGPL-3.0-or-later
%%
%% Copyright (C) 2026 Nathan Foster <next-nf@proton.me>
%%
%% This program is free software: you can redistribute it and/or modify
%% it under the terms of the GNU Affero General Public License as
%% published by the Free Software Foundation, either version 3 of the
%% License, or (at your option) any later version.
%%
%% This program is distributed in the hope that it will be useful,
%% but WITHOUT ANY WARRANTY; without even the implied warranty of
%% MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
%% GNU Affero General Public License for more details.
%%
%% You should have received a copy of the GNU Affero General Public License
%% along with this program.  If not, see <https://www.gnu.org/licenses/>.
-module(udr_cluster_dist_SUITE).
-include_lib("common_test/include/ct.hrl").
-include_lib("eunit/include/eunit.hrl").
-export([all/0, init_per_suite/1, end_per_suite/1]).
-export([cross_node_mutex/0, cross_node_mutex/1]).
-export([node_down_releases_lock/0, node_down_releases_lock/1]).
%% Exported for use as MFA on peer nodes (avoids shipping funs across distribution).
-export([hold_entity/3]).

all() -> [cross_node_mutex, node_down_releases_lock].

cross_node_mutex() -> [{timetrap, {seconds, 30}}].

init_per_suite(Config) ->
    %% The CT node must already be distributed -- this suite controls a peer over
    %% Erlang distribution. We do not start distribution here; run CT distributed,
    %% e.g. `rebar3 ct --sname test`. Skip cleanly (never fail) otherwise.
    case erlang:is_alive() of
        true ->
            Config;
        false ->
            Reason = "CT node is not distributed -- run with `rebar3 ct --sname test`",
            io:format(user, "~n[udr_cluster_dist_SUITE] SKIPPED: ~s~n", [Reason]),
            {skip, Reason}
    end.

end_per_suite(_Config) ->
    ok.

cross_node_mutex(_Config) ->
    Scope = udr_cluster:scope(),
    {ok, _} = application:ensure_all_started(udr_cluster),
    %% Peer boots with the origin's full code path baked in (so udr_cluster/syn
    %% are loadable) and a generous wait_boot for cold CI runners. ?CT_PEER
    %% propagates the cookie, so no -setcookie is needed.
    {ok, Peer, PeerNode} = ?CT_PEER(#{name => ?CT_PEER_NAME(),
                                      args => ["-pa" | code:get_path()],
                                      wait_boot => 20000}),
    try
        {ok, _} = erpc:call(PeerNode, application, ensure_all_started, [udr_cluster]),

        Imsi = <<"001010123456789">>,
        Holder = erpc:call(PeerNode, erlang, spawn,
                           [fun() -> receive stop -> ok end end]),
        ok = erpc:call(PeerNode, syn, register, [Scope, Imsi, Holder]),
        wait_until(fun() -> udr_cluster:whereis_session(Imsi) =:= Holder end),

        ?assertEqual({error, session_busy},
                     udr_cluster:with_session(Imsi, fun() -> 1 end, 200)),

        Holder ! stop,
        wait_until(fun() -> udr_cluster:whereis_session(Imsi) =:= undefined end),
        ?assertEqual(ok, udr_cluster:with_session(Imsi, fun() -> ok end, 2000))
    after
        peer:stop(Peer),
        application:stop(udr_cluster)
    end,
    ok.

%% Distinct from cross_node_mutex (which tests process-death auto-release via
%% `Holder ! stop`): here the peer node itself goes down hard via peer:stop/1 while
%% a process on that node is parked inside with_entity/3, holding the syn lock.
%% syn must auto-release the downed node's registration so the origin can re-acquire
%% — this is the "node-down recovery" guarantee from database.md §8.3.
node_down_releases_lock() -> [{timetrap, {seconds, 30}}].

node_down_releases_lock(_Config) ->
    Scope = udr_cluster:scope(),
    {ok, _} = application:ensure_all_started(udr_cluster),
    {ok, Peer, PeerNode} = ?CT_PEER(#{name => ?CT_PEER_NAME(),
                                      args => ["-pa" | code:get_path()],
                                      wait_boot => 20000}),
    Key = <<"001010node-down-key">>,
    try
        {ok, _} = erpc:call(PeerNode, application, ensure_all_started, [udr_cluster]),

        %% Spawn a process ON the peer (MFA, no fun shipped) that acquires the lock
        %% and parks inside the critical section, signalling the CT node once held.
        Origin = self(),
        _PeerHolder = erlang:spawn(PeerNode, ?MODULE, hold_entity, [Scope, Key, Origin]),
        receive
            {held, _} -> ok
        after 5000 -> ct:fail(lock_not_acquired_on_peer)
        end,

        %% syn is eventually consistent: wait until the origin also sees the holder.
        wait_until(fun() -> udr_cluster:whereis_entity(Scope, Key) =/= undefined end),
        ?assertEqual({error, session_busy},
                     udr_cluster:with_entity(Scope, Key, fun() -> 1 end, 200)),

        %% Hard node-down: stop the peer (not a process kill on the origin).
        %% syn must detect the node-down and de-register the holder.
        peer:stop(Peer),

        %% Bounded retry: syn propagates node-down events asynchronously.
        %% Use with_entity itself as the probe — success means the lock was freed.
        wait_until(fun() ->
            ok =:= udr_cluster:with_entity(Scope, Key, fun() -> ok end, 0)
        end, 200)
    after
        %% peer:stop is idempotent; safe to call again if the test path already stopped it.
        catch peer:stop(Peer),
        application:stop(udr_cluster)
    end,
    ok.

%% Runs ON the peer node (exported MFA — no closure shipped across distribution).
%% Acquires the (Scope, Key) lock via the public API, signals Origin with {held, self()},
%% then parks indefinitely. The lock is freed when the node goes down.
hold_entity(Scope, Key, Origin) ->
    udr_cluster:with_entity(Scope, Key, fun() ->
        Origin ! {held, self()},
        receive _Any -> ok end
    end).

wait_until(F) -> wait_until(F, 100).
wait_until(_F, 0) -> erlang:error(timeout);
wait_until(F, N) ->
    case F() of
        true  -> ok;
        false -> timer:sleep(50), wait_until(F, N - 1)
    end.
