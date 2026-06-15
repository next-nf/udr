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
-module(udr_db_flush_SUITE).
-include_lib("common_test/include/ct.hrl").
-include_lib("eunit/include/eunit.hrl").
-export([all/0, init_per_testcase/2, end_per_testcase/2]).
-export([flush_empties_store/1, flush_denied_when_not_allowed/1]).

all() -> [flush_empties_store, flush_denied_when_not_allowed].

init_per_testcase(_TC, Config) ->
    application:set_env(udr_db, backend, udr_db_ets),
    {ok, Started} = application:ensure_all_started(udr_db),
    [{started, Started} | Config].

end_per_testcase(_TC, Config) ->
    [application:stop(A) || A <- lists:reverse(?config(started, Config))],
    ok.

flush_empties_store(_Config) ->
    application:set_env(udr_db, allow_flush, true),
    ok = udr_db:put(auth_subscription, <<"k1">>, #{<<"x">> => 1}),
    ok = udr_db:put(subscription_data, <<"k2">>, #{<<"y">> => 2}),
    ?assertMatch({ok, _}, udr_db:get(auth_subscription, <<"k1">>)),
    ok = udr_db:flush(),
    ?assertEqual({error, not_found}, udr_db:get(auth_subscription, <<"k1">>)),
    ?assertEqual({error, not_found}, udr_db:get(subscription_data, <<"k2">>)),
    ok.

flush_denied_when_not_allowed(_Config) ->
    application:set_env(udr_db, allow_flush, false),
    ok = udr_db:put(auth_subscription, <<"k3">>, #{<<"z">> => 3}),
    ?assertEqual({error, flush_not_allowed}, udr_db:flush()),
    ?assertMatch({ok, _}, udr_db:get(auth_subscription, <<"k3">>)),
    ok.
