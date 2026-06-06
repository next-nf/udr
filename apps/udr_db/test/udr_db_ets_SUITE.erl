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
-module(udr_db_ets_SUITE).
-include_lib("common_test/include/ct.hrl").
-include_lib("eunit/include/eunit.hrl").
-export([all/0, init_per_testcase/2, end_per_testcase/2]).
-export([put_then_get/1, get_missing/1, delete_removes_doc/1,
         find_by_field/1, find_no_matches/1,
         update_matching_version/1, update_stale_version/1, update_missing_key/1,
         conformance/1]).

all() ->
    [put_then_get, get_missing, delete_removes_doc,
     find_by_field, find_no_matches,
     update_matching_version, update_stale_version, update_missing_key,
     conformance].

init_per_testcase(_TestCase, Config) ->
    application:set_env(udr_db, backend, udr_db_ets),
    {ok, Pid} = udr_db_ets:start_link(),
    [{pid, Pid} | Config].

end_per_testcase(_TestCase, Config) ->
    gen_server:stop(?config(pid, Config)),
    ok.

%% crud

put_then_get(_Config) ->
    ok = udr_db:put(auth_subscription, <<"imsi-1">>, #{<<"ki">> => <<"abc">>}),
    {ok, Doc} = udr_db:get(auth_subscription, <<"imsi-1">>),
    ?assertEqual(<<"abc">>, maps:get(<<"ki">>, Doc)),
    ?assertEqual(1, maps:get(<<"version">>, Doc)),
    ok.

get_missing(_Config) ->
    ?assertEqual({error, not_found}, udr_db:get(auth_subscription, <<"nope">>)),
    ok.

delete_removes_doc(_Config) ->
    ok = udr_db:put(auth_subscription, <<"imsi-2">>, #{<<"ki">> => <<"x">>}),
    ok = udr_db:delete(auth_subscription, <<"imsi-2">>),
    ?assertEqual({error, not_found}, udr_db:get(auth_subscription, <<"imsi-2">>)),
    ok.

%% find

find_by_field(_Config) ->
    ok = udr_db:put(subscription_data, <<"i1">>, #{<<"msisdn">> => <<"49100">>}),
    ok = udr_db:put(subscription_data, <<"i2">>, #{<<"msisdn">> => <<"49200">>}),
    ok = udr_db:put(subscription_data, <<"i3">>, #{<<"msisdn">> => <<"49100">>}),
    {ok, Docs} = udr_db:find(subscription_data, #{<<"msisdn">> => <<"49100">>}),
    ?assertEqual(2, length(Docs)),
    ?assert(lists:all(fun(D) -> maps:get(<<"msisdn">>, D) =:= <<"49100">> end, Docs)),
    ok.

find_no_matches(_Config) ->
    ?assertEqual({ok, []}, udr_db:find(subscription_data, #{<<"msisdn">> => <<"x">>})),
    ok.

%% update_cas

update_matching_version(_Config) ->
    ok = udr_db:put(auth_subscription, <<"i">>, #{<<"sqn">> => 1000, <<"algo">> => <<"milenage">>}),
    {ok, New} = udr_db:update(auth_subscription, <<"i">>, 1,
                              #{set => #{<<"algo">> => <<"tuak">>}, inc => #{<<"sqn">> => 32}}),
    ?assertEqual(1032, maps:get(<<"sqn">>, New)),
    ?assertEqual(<<"tuak">>, maps:get(<<"algo">>, New)),
    ?assertEqual(2, maps:get(<<"version">>, New)),
    ok.

update_stale_version(_Config) ->
    ok = udr_db:put(auth_subscription, <<"i">>, #{<<"sqn">> => 1000}),
    ?assertEqual({error, version_conflict},
                 udr_db:update(auth_subscription, <<"i">>, 99, #{inc => #{<<"sqn">> => 1}})),
    {ok, D} = udr_db:get(auth_subscription, <<"i">>),
    ?assertEqual(1000, maps:get(<<"sqn">>, D)),
    ok.

update_missing_key(_Config) ->
    ?assertEqual({error, not_found},
                 udr_db:update(auth_subscription, <<"nope">>, 1, #{inc => #{<<"sqn">> => 1}})),
    ok.

%% conformance

conformance(_Config) ->
    [ begin ct:log("scenario: ~s", [Name]), Fun() end
      || {Name, Fun} <- udr_db_conformance:scenarios() ],
    ok.
