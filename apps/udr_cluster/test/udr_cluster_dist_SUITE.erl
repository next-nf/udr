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

all() -> [cross_node_mutex].

cross_node_mutex() -> [{timetrap, {seconds, 30}}].

init_per_suite(Config) ->
    case ensure_distributed() of
        ok ->
            Config;
        {skip, Reason} ->
            io:format(user, "~n[udr_cluster_dist_SUITE] SKIPPED: ~p~n", [Reason]),
            {skip, Reason}
    end.

end_per_suite(_Config) ->
    ok.

ensure_distributed() ->
    case net_kernel:start([udr_ct_origin, shortnames]) of
        {ok, _}                       -> ok;
        {error, {already_started, _}} -> ok;
        {error, Reason}               -> {skip, {no_distribution, Reason}}
    end.

cross_node_mutex(_Config) ->
    Scope = udr_cluster:scope(),
    {ok, _} = application:ensure_all_started(udr_cluster),
    {ok, Peer, PeerNode} =
        peer:start_link(#{name => peer:random_name(),
                          args => ["-setcookie", atom_to_list(erlang:get_cookie())]}),
    try
        ok = erpc:call(PeerNode, code, add_paths, [code:get_path()]),
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

wait_until(F) -> wait_until(F, 100).
wait_until(_F, 0) -> erlang:error(timeout);
wait_until(F, N) ->
    case F() of
        true  -> ok;
        false -> timer:sleep(50), wait_until(F, N - 1)
    end.
